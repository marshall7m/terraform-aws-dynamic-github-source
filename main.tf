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

  create_api = true
  api_name        = var.api_name
  api_description = var.api_description
  repos = [for repo in var.repos : {
    name          = repo.name
    filter_groups = repo.filter_groups
  }]
  github_secret_ssm_key         = var.github_secret_ssm_key        
  github_secret_ssm_description = var.github_secret_ssm_description
  github_secret_ssm_tags        = var.github_secret_ssm_tags

  lambda_success_destination_arns = [module.lambda_trigger_codebuild.function_arn]
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
  name   = var.lambda_trigger_codebuild_function_name
  policy = data.aws_iam_policy_document.lambda.json
}

module "lambda_trigger_codebuild" {
  source           = "github.com/marshall7m/terraform-aws-lambda"
  filename         = data.archive_file.lambda_function.output_path
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  function_name    = var.lambda_trigger_codebuild_function_name
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  allowed_to_invoke = [
    {
      statement_id = "LambdaInvokeAccess"
      principal    = "lambda.amazonaws.com"
      arn          = module.github_webhook_request_validator.function_arn
    }
  ]
  enable_cw_logs = true

  env_vars = {
    CODEBUILD_NAME = var.codebuild_name
  }
  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.lambda.arn
  ]
}

module "codebuild" {
  source = "github.com/marshall7m/terraform-aws-codebuild"

  name        = var.codebuild_name
  description = var.codebuild_description

  create_source_auth      = var.codebuild_source_auth_token != null ? true : false
  source_auth_token       = var.codebuild_source_auth_token
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
  role_policy_statements     = var.codebuild_role_policy_statements
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
  depends_on = [
    local_file.repo_cfg
  ]
}

resource "local_file" "repo_cfg" {
  content = jsonencode({ for repo in var.repos :
    repo.name => {
      #converts terraform codebuild params to python boto3 start_build() params
      codebuild_cfg = repo.codebuild_cfg != null ? { for key in keys(repo.codebuild_cfg) : local.codebuild_override_keys[key] => lookup(repo.codebuild_cfg, key) if lookup(repo.codebuild_cfg, key) != null } : {}
    }
  })
  filename = "${path.module}/function/repo_cfg.json"
}
