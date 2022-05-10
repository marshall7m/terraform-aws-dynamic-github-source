from time import sleep
import pytest
import os
import boto3
import subprocess
import logging
import sys
import shutil
from pprint import pformat
from datetime import datetime
from pytest_dependency import depends

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

'''

fixtures:
    create github event
        - modify files
        - push/pr

    run tf apply with pytest parametrized var.repo
    OR
    create separate tf fixture dirs with:
        - variations in var.repos
        - variations in github resources (push/PR changes)

tests:
    tf_plan
    start param start_time for log group filter
    tf_apply
    
    assert Lambda validator function succeeds using log group start time
    assert lambda trigger codebuild succeds using log group start time
    assert codebuild succeeds using source version filter

    assert codebuild cfg meets repo specification using codebuild describe build method

'''

def pytest_generate_tests(metafunc):
    if 'tf' in metafunc.fixturenames:
        metafunc.parametrize('tf', metafunc.module.tf_fixtures, indirect=True)

    if 'terraform_version' in metafunc.fixturenames:
        metafunc.parametrize('terraform_version', metafunc.module.terraform_versions, indirect=True)

terraform_versions = ['latest']
tf_fixtures = [
    pytest.param(f'{os.path.dirname(__file__)}/fixtures/test_successful_build'),
    pytest.param(f'{os.path.dirname(__file__)}/fixtures/test_invalid_codebuild_cfg', marks=pytest.mark.skip())
]

@pytest.fixture(scope='module', autouse=True)
def class_start_time(tf) -> datetime:
    '''Datetime of when the class testing started'''
    time = datetime.today()
    return time

@pytest.fixture(scope='module')
def param_lambda_invocation_count(class_start_time):
    '''Factory fixture that returns the number of times a Lambda function has runned since the class testing started'''
    invocations = []

    def _get_count(function_name: str, refresh=False) -> int:
        '''
        Argruments:
            function_name: Name of the AWS Lambda function
            refresh: Determines if a refreshed invocation count should be returned. If False, returns the locally stored invocation count.
        '''
        if refresh:
            log.info('Refreshing the invocation count')
            end_time = datetime.today()
            log.debug(f'Start Time: {class_start_time} -- End Time: {end_time}')

            cw = boto3.client('cloudwatch')

            response = cw.get_metric_statistics(
                Namespace='AWS/Lambda',
                MetricName='Invocations',
                Dimensions=[
                    {
                        'Name': 'FunctionName',
                        'Value': function_name
                    }
                ],
                StartTime=class_start_time, 
                EndTime=end_time,
                Period=60,
                Statistics=[
                    'SampleCount'
                ],
                Unit='Count'
            )
            for data in response['Datapoints']:
                invocations.append(data['SampleCount'])
                
        return len(invocations)

    yield _get_count

    invocations = []

@pytest.mark.dependency()
def test_tf_plan(tf_plan):
    pass

@pytest.mark.dependency()
def test_tf_apply(request, tf, tf_apply, class_start_time):
    depends(request, [f'test_tf_plan[{request.node.callspec.id}]'])
    pass

@pytest.mark.dependency()
def test_lambda_github_validator_function(request, tf_output, param_lambda_invocation_count):
    depends(request, [f'test_tf_apply[{request.node.callspec.id}]'])
    pass

@pytest.mark.dependency()
def test_lambda_trigger_codebuild_function(request, tf_output, param_lambda_invocation_count):
    depends(request, [f'test_lambda_github_validator_function[{request.node.callspec.id}]'])
    pass

@pytest.mark.dependency()
def test_codebuild_status(request, tf_output):
    depends(request, [f'test_lambda_trigger_codebuild_function[{request.node.callspec.id}]'])
    pass