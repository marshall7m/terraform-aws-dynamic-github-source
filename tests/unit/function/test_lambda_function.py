import pytest
import unittest
import os
import logging
import json
import sys
from unittest.mock import patch, mock_open

log = logging.getLogger(__name__)
stream = logging.StreamHandler(sys.stdout)
log.addHandler(stream)
log.setLevel(logging.DEBUG)

@pytest.fixture(scope='function')
def aws_credentials():
    '''
    Mocked AWS credentials needed to be set before importing Lambda Functions that define global boto3 clients. 
    This prevents the region_name not specified errors.
    '''
    os.environ.get('AWS_ACCESS_KEY_ID', 'testing')
    os.environ.get('AWS_SECRET_ACCESS_KEY', 'testing')
    os.environ.get('AWS_SECURITY_TOKEN', 'testing')
    os.environ.get('AWS_SESSION_TOKEN', 'testing')
    os.environ.get('AWS_DEFAULT_REGION', 'us-west-2')

def run_lambda(event=None, context=None):
    '''Imports Lambda function after boto3 client patch has been created to prevent boto3 region_name not specified error'''
    from function.lambda_function import lambda_handler
    return lambda_handler(event, context)

repo_cfg = {
    'dummy-repo': {
        'codebuild_cfg': {
            'environment_variables': [
                {
                    'name': 'foo',
                    'type': 'PLAINTEXT',
                    'value': 'bar'
                }
            ]   
        }
    }
}

@pytest.mark.parametrize('event,expected_status_code,expect_start_build', [
    pytest.param(
        {
            'requestPayload': {
                'headers': {
                    'X-GitHub-Event': 'push'
                },
                'body': {
                    'repository': {'name': 'dummy-repo', 'html_url': 'https://github.com/user/dummy-repo.git'},
                    'ref': 'ref/heads/master'
                }
            }
        },
        302,
        True,
        id='successful_push'
    ),
    pytest.param(
        {
            'requestPayload': {
                'headers': {
                    'X-GitHub-Event': 'push'
                },
                'body': {
                    'repository': {'name': 'dummy-repo', 'html_url': 'https://github.com/user/dummy-repo.git'},
                    'action': 'closed',
                    'merged': True,
                    'pull_request': {
                        'base': {'ref': 'master'},
                        'head': {'ref': 'feature-1'},
                        'numbder': 1
                    },
                    'ref': 'ref/heads/master'
                }
            }
        },
        302,
        True,
        id='successful_pr'
    ),
    pytest.param(
        {
            'requestPayload': {
                'headers': {
                    'X-GitHub-Event': 'starred'
                },
                'body': {}
            }
        },
        500,
        False,
        id='invalid_event'
    )
])

@patch('builtins.open', new_callable=mock_open, read_data=json.dumps(repo_cfg))
@patch('function.lambda_function.cb')
@patch.dict(os.environ, {'CODEBUILD_NAME': 'test-build'}, clear=True)
@pytest.mark.usefixtures('aws_credentials')
def test_lambda_handler(mock_client, mock_repo_cfg, event, expected_status_code, expect_start_build):
    event['requestPayload']['body'] = json.dumps(event['requestPayload']['body'])
    log.info('Running Lambda Function')
    response = run_lambda(event, {})

    assert response['statusCode'] == expected_status_code

    if expect_start_build:
        mock_client.start_build.assert_called_once()