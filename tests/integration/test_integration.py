from time import sleep
import timeout_decorator
import pytest
import os
import boto3
import logging
import datetime
import re
import uuid
import github
import json
from tests.integration.utils import push

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

os.environ["AWS_DEFAULT_REGION"] = os.environ["AWS_REGION"]
tf_dirs = [f"{os.path.dirname(__file__)}/fixtures"]
gh = github.Github(os.environ["TF_VAR_testing_github_token"]).get_user()
cb = boto3.client("codebuild")


def pytest_generate_tests(metafunc):

    if "terraform_version" in metafunc.fixturenames:
        tf_versions = [pytest.param("latest")]
        metafunc.parametrize(
            "terraform_version",
            tf_versions,
            indirect=True,
            scope="session",
            ids=[f"tf_{v.values[0]}" for v in tf_versions],
        )

    if "tf" in metafunc.fixturenames:
        metafunc.parametrize("tf", tf_dirs, indirect=True, scope="session")


@pytest.fixture
def function_start_time():
    """Returns timestamp of when the function testing started"""
    start_time = datetime.datetime.now(datetime.timezone.utc)
    return start_time


@pytest.fixture(scope="module")
def repo():
    repos = []

    def _get_or_create(name=None):
        if name:
            try:
                repo = gh.get_repo(name)
            except github.UnknownObjectException:
                log.info(f"Creating repo: {name}")
                repo = gh.create_repo(name, auto_init=True)
                repos.append(repo)
            return repo

        return repos

    yield _get_or_create

    for repo in repos:
        log.info(f"Deleting repo: {repo.name}")
        try:
            repo.delete()
        except github.UnknownObjectException:
            log.info("GitHub repo does not exist")


@timeout_decorator.timeout(120)
def assert_builds_overrides(repos, build_name, wait=10):
    "Waits for all test-related builds to start and pass assertions"
    tested_ids = []
    while len(tested_ids) != len(repos):
        log.info(f"Waiting {wait} second(s")
        sleep(wait)
        build_ids = cb.list_builds_for_project(
            projectName=build_name, sortOrder="DESCENDING"
        )["ids"]

        if len(build_ids) == 0:
            continue

        for build in cb.batch_get_builds(ids=build_ids)["builds"]:
            id = build["id"]
            if id in tested_ids:
                continue
            for name, cfg in repos.items():
                if build["source"]["location"] == cfg["clone_url"]:
                    log.info(
                        "Assert repo-specific CodeBuild override attributes were set"
                    )
                    log.debug(f"Target Repo: {name}")
                    log.debug(f"Build ID: {id}")

                    assert all(
                        [
                            (re.search(r".+(?=Override)", key).group(0), value)
                            in build.items()
                            for key, value in cfg["codebuild_cfg"].items()
                        ]
                    )
                    tested_ids.append(id)


@pytest.mark.parametrize(
    "codebuild_cfgs,expect_builds",
    [
        pytest.param(
            [{"timeoutInMinutesOverride": 10}, {"timeoutInMinutesOverride": 20}], True
        ),
        pytest.param([{"invalid_attr": "foo"}, {"invalid_attr": "foo"}], False),
    ],
)
def test_codebuild_override_attributes(tf, repo, codebuild_cfgs, expect_builds):
    """
    For each dummy repo, creates a GitHub push event and assert that the expected
    override attributes are present. If the override attributes are invalid, the upstream
    Lambda Function is expected to fail and the build is expected not to run.
    """
    tf_vars = {"repos": {}}
    for cfg in codebuild_cfgs:
        tf_vars["repos"][
            repo(f"mut-terraform-aws-dynamic-github-source-{uuid.uuid4()}").name
        ] = {
            "filter_groups": [[{"type": "event", "pattern": "push"}]],
            "codebuild_cfg": cfg,
        }
    with open(f"{tf.tfdir}/terraform.tfvars.json", "w", encoding="utf-8") as f:
        json.dump(tf_vars, f, ensure_ascii=False, indent=4)

    log.info("Runnning Terraform apply")
    tf.apply(auto_approve=True)

    tf_output = tf.output()

    for name in list(tf_vars["repos"].keys()):
        log.info(f"Creating Github event for repo: {name}")
        git_repo = repo(name)
        push(name, git_repo.default_branch, {str(uuid.uuid4()) + ".py": "dummy"})

    repos = {
        name: {**{"clone_url": gh.get_repo(name).clone_url}, **cfg}
        for name, cfg in tf_vars["repos"].items()
    }

    if expect_builds:
        log.info("Assert build overrides are present")
        assert_builds_overrides(repos, tf_output["codebuild_name"])
    else:
        log.info("Assert builds are failed to be created")
        with pytest.raises(timeout_decorator.TimeoutError):
            assert_builds_overrides(repos, tf_output["codebuild_name"])
