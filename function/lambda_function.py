import json
import logging
import boto3
import os
import re
import ast

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)
cb = boto3.client('codebuild')

def lambda_handler(event, context):
    """
    Runs the associated CodeBuild project with repo specific configurations.

    Requirements:
        - Lambda Function must be invoked asynchronously
        - Payload body must be mapped to the key `body`
        - Payload headers must be mapped to the key `headers`
    """

    payload = json.loads(event['requestPayload']['body'])
    event = event['requestPayload']['headers']['X-GitHub-Event']
    repo_name = payload['repository']['name']
    
    with open(f'{os.getcwd()}/repo_cfg.json') as f:
      repo_cfg = json.load(f)[repo_name]

    if event == "pull_request":
        # if event was a PR merge
        if payload['action'] == 'closed' and payload['merged']:
            source_version = payload['pull_request']['base']['ref']
        # if event was PR activity that wasn't merged
        else:
            source_version = f'pr/{payload["pull_request"]["number"]}'
    elif event == "push":
        # gets branch that was pushed to
        source_version = str(payload['ref'].split('/')[-1])

    log.debug(f'Source Version: {source_version}')

    log.info(f'Starting CodeBuild project: {os.environ["CODEBUILD_NAME"]}')

    response = cb.start_build(
        projectName=os.environ['CODEBUILD_NAME'],
        sourceLocationOverride=payload['repository']['html_url'],
        sourceTypeOverride='GITHUB',
        sourceVersion=source_version,
        **repo_cfg['codebuild_cfg']
    )

    return {'message': 'Build was successfully started'}