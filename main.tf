locals {
  codebuild_artifacts = defaults(var.codebuild_artifacts, {
    type = "NO_ARTIFACTS"
  })
  codebuild_environment = defaults(var.codebuild_environment, {
    compute_type = "BUILD_GENERAL1_SMALL"
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/standard:3.0"
  })
}

module "github_webhook_request_validator" {
  source = "github.com/marshall7m/terraform-aws-github-webhook?ref=v0.1.4"

  create_api      = true
  api_name        = var.api_name
  api_description = var.api_description
  repos = [for name, cfg in var.repos : {
    name          = name
    filter_groups = cfg.filter_groups
  }]
  github_secret_ssm_key         = var.github_secret_ssm_key
  github_secret_ssm_description = var.github_secret_ssm_description
  github_secret_ssm_tags        = var.github_secret_ssm_tags

  lambda_destination_on_success = module.lambda_trigger_codebuild.lambda_function_arn
  async_lambda_invocation       = true
  lambda_create_async_event_config = true
  lambda_attach_async_event_policy = true
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

resource "local_file" "repo_cfg" {
  content  = jsonencode(var.repos)
  filename = "${path.module}/function/repo_cfg.json"
}

module "lambda_trigger_codebuild" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "3.3.1"

  function_name = var.lambda_trigger_codebuild_function_name
  description   = "Start the target CodeBuild project with GitHub source repository-specific configurations"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  source_path   = "${path.module}/function"

  allowed_triggers = {
    LambdaInvokeAccess = {
      service    = "lambda"
      source_arn = module.github_webhook_request_validator.function_arn
    }
  }
  environment_variables = {
    CODEBUILD_NAME = var.codebuild_name
  }

  publish = true
  policies = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    aws_iam_policy.lambda.arn
  ]
  attach_policies               = true
  number_of_policies            = 2
  role_force_detach_policies    = true
  attach_cloudwatch_logs_policy = true

  depends_on = [
    local_file.repo_cfg
  ]
}

module "codebuild" {
  source = "github.com/marshall7m/terraform-aws-codebuild?ref=v0.1.0"

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