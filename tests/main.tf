locals {
  mut = "mut-terraform-aws-infrastructure-modules-ci"
}

resource "github_repository" "test" {
  name        = local.mut
  description = "Test repo for mut: ${local.mut}"
  auto_init   = true
  visibility  = "public"
}

resource "github_repository_file" "test_pr" {
  repository          = github_repository.test.name
  branch              = github_branch.test_pr.branch
  file                = "test_pr.py"
  content             = "used to trigger repo's webhook for testing associated mut: ${local.mut}"
  commit_message      = "test file"
  overwrite_on_create = true
  depends_on = [
    module.mut_dynamic_github_source
  ]
}

resource "github_branch" "test_pr" {
  repository    = github_repository.test.name
  branch        = "test-branch"
  source_branch = "master"
}

resource "github_repository_pull_request" "test_pr" {
  base_repository = github_repository.test.name
  base_ref        = "master"
  head_ref        = github_branch.test_pr.branch
  title           = "Test webhook PR filter"
  body            = "Check Cloudwatch logs for results"
  depends_on = [
    github_repository_file.test_pr
  ]
}

resource "github_repository_file" "test_push" {
  repository          = github_repository.test.name
  branch              = "master"
  file                = "test_push.py"
  content             = "used to trigger repo's webhook for testing associated mut: ${local.mut}"
  commit_message      = "test webhook push filter"
  overwrite_on_create = true
  depends_on = [
    module.mut_dynamic_github_source
  ]
}

module "mut_dynamic_github_source" {
  source                 = "..//"

  create_github_token_ssm_param = false
  github_token_ssm_key = "github-webhook-request-validator-github-token"
  codebuild_name         = local.mut
  codebuild_buildspec    = file("buildspec.yaml")
  repos = [
    {
      name = github_repository.test.name
      codebuild_cfg = {
        environment_variables = [
          {
            name  = "TEST"
            value = "FOO"
            type  = "PLAINTEXT"
          }
        ]
      }
      filter_groups = [
        {
          events     = ["push"]
          file_paths = ["CHANGELOG.md"]
        },
        {
          events     = ["pull_request"]
          pr_actions = ["opened", "edited", "synchronize"]
          file_paths = [".*\\.py$"]
          head_refs  = ["test-branch"]
        }
      ]
    }
  ]

  depends_on = [
    github_repository.test
  ]
}