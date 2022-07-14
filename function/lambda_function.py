import json
import logging
import boto3
import botocore
import os

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)
cb = boto3.client("codebuild")


def lambda_handler(event, context):
    """
    Runs the associated CodeBuild project with repo specific configurations.

    Requirements:
        - Lambda Function must be invoked asynchronously
        - Payload body must be mapped to the key `body`
        - Payload headers must be mapped to the key `headers`
    """

    try:
        payload = json.loads(event["requestPayload"]["body"])
        git_event = event["requestPayload"]["headers"]["X-GitHub-Event"]
        repo_name = payload["repository"]["name"]

        log.debug(f"Repo: {repo_name}")

        with open(f"{os.getcwd()}/repo_cfg.json") as f:
            repo_cfg = json.load(f)[repo_name]

        log.debug(
            f'Repo-scoped CodeBuild override attributes:\n{repo_cfg["codebuild_cfg"]}'
        )

        if git_event == "pull_request":
            if payload["action"] == "closed" and payload["merged"]:
                # if event was a PR merge use base ref
                source_version = payload["pull_request"]["base"]["ref"]
            else:
                # if event was PR activity that wasn't merged use PR #
                source_version = f'pr/{payload["pull_request"]["number"]}'
        elif git_event == "push":
            # gets branch that was pushed to
            source_version = str(payload["ref"].split("/")[-1])

        log.debug(f"Source Version: {source_version}")

        log.info(f'Starting CodeBuild project: {os.environ["CODEBUILD_NAME"]}')

        try:
            response = cb.start_build(
                projectName=os.environ["CODEBUILD_NAME"],
                sourceLocationOverride=payload["repository"]["clone_url"],
                sourceTypeOverride="GITHUB",
                sourceVersion=source_version,
                **repo_cfg["codebuild_cfg"],
            )
        except botocore.exceptions.ParamValidationError as e:
            log.error(e, exc_info=True)
            response = {
                "statusCode": 400,
                "message": "One or more CodeBuild override attributes are invalid",
            }
            log.debug(f"Response:\n{response}")
            return response

        log.info(f'Build ID: {response["build"]["id"]}')
        response = {"statusCode": 302, "message": "Build was successfully started"}
        log.debug(f"Response:\n{response}")
        return response
    except Exception as e:
        log.error(e, exc_info=True)
        response = {"statusCode": 500, "message": "Error while processing request"}
        log.debug(f"Response:\n{response}")
        return response
