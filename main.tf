locals {
  codebuild_artifacts = defaults(var.codebuild_artifacts, {
    type = "NO_ARTIFACTS"
  })
  codebuild_environment = defaults(var.codebuild_environment, {
    compute_type = "BUILD_GENERAL1_SMALL"
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/standard:3.0"
  })

  codebuild_override_keys = {
    buildspec             = "buildspecOverride"
    timeout               = "timeoutInMinutesOverride"
    cache                 = "cacheOverride"
    privileged_mode       = "privilegedModeOverride"
    report_build_status   = "reportBuildStatusOverride"
    environment_type      = "environmentTypeOverride"
    compute_type          = "computeTypeOverride"
    image                 = "imageOverride"
    environment_variables = "environmentVariablesOverride"
    artifacts             = "artifactsOverride"
    secondary_artifacts   = "secondaryArtifactsOverride"
    role_arn              = "serviceRoleOverride"
    logs_cfg              = "logsConfigOverride"
    certificate           = "certificateOverride"
  }
}

module "github_webhook_request_validator" {
  source = "github.com/marshall7m/terraform-aws-github-webhook"

  api_name        = var.api_name
  api_description = var.api_description
  #TODO: index only attr needed for module
  repos                           = var.repos
  github_secret_ssm_key           = var.github_secret_ssm_key         #tfsec:ignore:GEN003
  github_secret_ssm_description   = var.github_secret_ssm_description #tfsec:ignore:GEN003
  github_secret_ssm_tags          = var.github_secret_ssm_tags
  lambda_success_destination_arns = [module.lambda.function_arn]
  async_lambda_invocation         = true
}

data "aws_iam_policy_document" "lambda" {

  statement {
    sid    = "TriggerCodeBuild"
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:StartBuildBatch",
      "codebuild:UpdateProject"
    ]
    resources = [module.codebuild.arn]
  }
}

resource "aws_iam_policy" "lambda" {
  name   = var.function_name
  policy = data.aws_iam_policy_document.lambda.json
}

module "codebuild" {
  source = "github.com/marshall7m/terraform-aws-codebuild"

  name        = var.codebuild_name
  description = var.codebuild_description

  source_auth_token       = var.github_token_ssm_value
  source_auth_server_type = "GITHUB"
  source_auth_type        = "PERSONAL_ACCESS_TOKEN"

  assumable_role_arns = var.codebuild_assumable_role_arns
  artifacts           = local.codebuild_artifacts
  environment         = local.codebuild_environment
  build_timeout       = var.codebuild_timeout
  cache               = var.codebuild_cache
  secondary_artifacts = var.codebuild_secondary_artifacts
  build_source = {
    buildspec = coalesce(var.codebuild_buildspec, file("${path.module}/buildspec_placeholder.yaml"))
    type      = "NO_SOURCE"
  }

  s3_logs                    = var.enable_codebuild_s3_logs
  s3_log_key                 = var.codebuild_s3_log_key
  s3_log_bucket              = var.codebuild_s3_log_bucket
  s3_log_encryption_disabled = var.codebuild_s3_log_encryption
  cw_logs                    = var.enable_codebuild_cw_logs
  role_arn                   = var.codebuild_role_arn
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
  depends_on = [
    local_file.repo_cfg
  ]
}

#using lambda layer file for codebuild override cfg given lambda functions have a size limit of 4KB for env vars and easier parsing
resource "local_file" "repo_cfg" {
  content = jsonencode({ for repo in local.repos :
    repo.name => {
      #converts terraform codebuild params to python boto3 start_build() params
      codebuild_cfg = repo.codebuild_cfg != null ? { for key in keys(repo.codebuild_cfg) : local.codebuild_override_keys[key] => lookup(repo.codebuild_cfg, key) if lookup(repo.codebuild_cfg, key) != null } : {}
    }
  })
  filename = "${path.module}/function/repo_cfg.json"
}
