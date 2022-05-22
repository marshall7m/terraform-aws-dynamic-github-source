from time import sleep
import pytest
import os
import boto3
import subprocess
import logging
import sys
import shutil
from pprint import pformat
import datetime
import requests
import re
import uuid
import github

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

from tests.integration.utils import wait_for_lambda_invocation, push, get_latest_log_stream_events, TimeoutError

os.environ['AWS_DEFAULT_REGION'] = os.environ['AWS_REGION']
tf_dirs = [f'{os.path.dirname(__file__)}/fixtures']
def pytest_generate_tests(metafunc):
    
    if 'terraform_version' in metafunc.fixturenames:
        tf_versions = [pytest.param('latest')]
        metafunc.parametrize('terraform_version', tf_versions, indirect=True, scope='session', ids=[f'tf_{v.values[0]}' for v in tf_versions])

    if 'tf' in metafunc.fixturenames:
        metafunc.parametrize('tf', tf_dirs, indirect=True, scope='session')

@pytest.fixture
def function_start_time():
    '''Returns timestamp of when the function testing started'''
    start_time = datetime.datetime.now(datetime.timezone.utc)
    return start_time

@pytest.fixture(scope='module')
def repo():
    repos = []
    gh = github.Github(os.environ['TF_VAR_testing_github_token']).get_user()
    def _get_or_create(name=None):
        if name:
            try:
                repo = gh.get_repo(name)
            except github.UnknownObjectException:
                log.info(f'Creating repo: {name}')
                repo = gh.create_repo(name, auto_init=True)
                repos.append(repo)
            return repo
        
        return repos

    yield _get_or_create

    for repo in repos:
        log.info(f'Deleting repo: {repo.name}')
        try:
            repo.delete()
        except github.UnknownObjectException:
            log.info('GitHub repo does not exist')

def test_failed_github_validation(tf, function_start_time, tf_apply, tf_output, repo):
    '''Sends request to the AGW API invoke URL with an invalid signature to the Lambda Function and skips invoking the trigger CodeBuild Lambda Function'''
    dummy_repo = repo(f'mut-terraform-aws-dynamic-github-source-{uuid.uuid4()}')
    log.info('Runnning Terraform apply')
    tf_apply(update=True, repos={dummy_repo.name: {'filter_groups': [[{'type': 'event', 'pattern': 'push'}]]}})

    headers = {
        'content-type': 'application/json', 
        'X-Hub-Signature-256': 'invalid-sig', 
        'X-GitHub-Event': 'push'
    }

    tf_output = tf.output()
    response = requests.post(tf_output['api_deployment_invoke_url'], json={'body': {}}, headers=headers).json()
    log.debug(f'Response:\n{response}')

    log.info('Assert that the trigger CodeBuild Lambda Function was not invoked')
    try:
        wait_for_lambda_invocation(tf_output['trigger_codebuild_function_name'], function_start_time, timeout=30)
    except TimeoutError:
        return

    pytest.fail('Trigger CodeBuild Lambda Function was invoked')

def test_successful_build(tf, tf_apply, tf_output, repo):
    '''For each dummy repo, creates a GitHub event that passes the GitHub validator Lambda Function and successfully starts a CodeBuild project with the expected override attributes'''
    dummy_repos = {
        repo(f'mut-terraform-aws-dynamic-github-source-1-{uuid.uuid4()}').name: {
            'filter_groups': [
                [
                    {
                        'type': 'event',
                        'pattern': 'push'
                    }
                ]
            ],
            'codebuild_cfg': {'timeoutInMinutesOverride': 10}
        },
        repo(f'mut-terraform-aws-dynamic-github-source-2-{uuid.uuid4()}').name: {
            'filter_groups': [
                [
                    {
                        'type': 'event',
                        'pattern': 'push'
                    }
                ]
            ],
            'codebuild_cfg': {'timeoutInMinutesOverride': 20}
        }
    }

    log.info('Runnning Terraform apply')
    tf_apply(update=True, repos=dummy_repos)
    tf_output = tf.output()

    for name, cfg in dummy_repos.items():
        repo_start_time = datetime.datetime.now(datetime.timezone.utc)
        log.debug(f'Testing repo start time: {repo_start_time}')
        
        log.info(f'Creating Github event for repo: {name}')
        git_repo = repo(name)
        push(name, git_repo.default_branch, {str(uuid.uuid4()) + '.py': 'dummy'})

        log.info(f'Waiting for Lambda Function invocation count to increase by one: {tf_output["request_validator_function_name"]}')
        wait_for_lambda_invocation(tf_output['request_validator_function_name'], repo_start_time)

        log.info(f'Waiting for Lambda Function invocation count to increase by one: {tf_output["trigger_codebuild_function_name"]}')
        wait_for_lambda_invocation(tf_output['trigger_codebuild_function_name'], repo_start_time)

        results = get_latest_log_stream_events(tf_output['trigger_codebuild_cw_log_group_name'], filter_pattern='"Build was successfully started"', start_time=int(repo_start_time.timestamp() * 1000), end_time=int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000))
        log.debug(f'Cloudwatch Events:\n{pformat(results)}')
        assert len(results) >= 1

        build_id_logs = get_latest_log_stream_events(tf_output['trigger_codebuild_cw_log_group_name'], filter_pattern='"Build ID"', start_time=int(repo_start_time.timestamp() * 1000), end_time=int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000))
        log.debug(f'Build ID filtered logs:\n{build_id_logs}')

        # gets build IDs logged within recent CW streams
        build_ids = [re.search(r"(?<=Build\sID:\s).+", log['message']).group(0) for log in build_id_logs]
        log.debug(f'Cloudwatch streams parsed build IDs: {build_ids}')

        cb = boto3.client('codebuild')
        
        # get build associated with repo
        build = [build for build in cb.batch_get_builds(ids=build_ids)['builds'] if build['source']['location'] == git_repo.clone_url][0]
        log.debug(f'Target Build:\n{build}')
        log.info('Assert repo-specific CodeBuild override attributes were set')
        assert all([(re.search(r".+(?=Override)", key).group(0), value) in build.items() for key, value in cfg['codebuild_cfg'].items()])

def test_invalid_codebuild_override_cfg(tf, function_start_time, tf_apply, tf_output, repo):
    '''Creates a GitHub event that passes the GitHub validator Lambda Function and returns the appropriate response for invalid CodeBuild override attributes for the triggered repo'''
    dummy_repo = repo(f'mut-terraform-aws-dynamic-github-source-{uuid.uuid4()}')
    log.info('Runnning Terraform apply')
    tf_apply(update=True, repos={
        dummy_repo.name: {
            'filter_groups': [
                [
                    {
                        'type': 'event',
                        'pattern': 'push'
                    }
                ]
            ],
            'codebuild_cfg': {'invalid_attr': 10}
        }
    })

    push(dummy_repo.name, dummy_repo.default_branch, {str(uuid.uuid4()) + '.py': 'dummy'})

    tf_output = tf.output()
    log.info(f'Waiting for Lambda Function invocation count to increase by one: {tf_output["request_validator_function_name"]}')
    wait_for_lambda_invocation(tf_output['request_validator_function_name'], function_start_time)

    log.info(f'Waiting for Lambda Function invocation count to increase by one: {tf_output["trigger_codebuild_function_name"]}')
    wait_for_lambda_invocation(tf_output['trigger_codebuild_function_name'], function_start_time)

    results = get_latest_log_stream_events(tf_output['trigger_codebuild_cw_log_group_name'], filter_pattern='"One or more CodeBuild override attributes are invalid"', start_time=int(function_start_time.timestamp() * 1000), end_time=int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000))
    log.debug(f'Cloudwatch Events:\n{pformat(results)}')
    assert len(results) >= 1