variable "common_tags" {
  description = "Tags to add to all resources"
  type        = map(string)
  default     = {}
}

# SSM #

## github-token ##

variable "create_github_token_ssm_param" {
  description = "Determines if an AWS System Manager Parameter Store value should be created for the Github token"
  type        = bool
  default     = true
}

variable "github_token_ssm_description" {
  description = "Github token SSM parameter description"
  type        = string
  default     = "Github token used to give read access to the payload validator function to get file that differ between commits" #tfsec:ignore:GEN001
}

variable "github_token_ssm_key" {
  description = "AWS SSM Parameter Store key for sensitive Github personal token"
  type        = string
  default     = "github-payload-validator" #tfsec:ignore:GEN001
}

variable "github_token_ssm_value" {
  description = "Registered Github webhook token associated with the Github provider. If not provided, module looks for pre-existing SSM parameter via `github_token_ssm_key`"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_token_ssm_tags" {
  description = "Tags for Github token SSM parameter"
  type        = map(string)
  default     = {}
}

## github-secret ##

variable "github_secret_ssm_key" {
  description = "SSM parameter store key for github webhook secret. Secret used within Lambda function for Github request validation."
  type        = string
  default     = "github-webhook-secret" #tfsec:ignore:GEN001 #tfsec:ignore:GEN003
}

variable "github_secret_ssm_description" {
  description = "Github secret SSM parameter description"
  type        = string
  default     = "Secret value for Github Webhooks" #tfsec:ignore:GEN001 #tfsec:ignore:GEN003
}

variable "github_secret_ssm_tags" {
  description = "Tags for Github webhook secret SSM parameter"
  type        = map(string)
  default     = {}
}

# Github #

variable "repos" {
  description = <<EOF
List of named repos to create github webhooks for and their respective filter groups used to select
what type of activity will trigger the associated Codebuild.
Params:
  `name`: Repository name
  `filter_groups`: List of filter groups that the Github event has to meet. The event has to meet all filters of atleast one group in order to succeed. 
    [
      [ (Filter Group)
        {
          `type`: The type of filter
            (
              `event` - List of Github Webhook events that will invoke the API. Currently only supports: `push` and `pull_request`.
              `pr_actions` - List of pull request actions (e.g. opened, edited, reopened, closed). See more under the action key at: https://docs.github.com/en/developers/webhooks-and-events/webhook-events-and-payloads#pull_request
              `base_refs` - List of base refs
              `head_refs` - List of head refs
              `actor_account_ids` - List of Github user IDs
              `commit_messages` - List of commit messages
              `file_paths` - List of file paths
            )
          `pattern`: Regex pattern that is searched for within the related event attribute. For `type` = `event`, use a single Github webhook event and not a regex pattern.
          `exclude_matched_filter` - If set to true, labels filter group as invalid if it is matched
        }
      ]
    ]
  `codebuild_cfg`: CodeBuild configurations used specifically for the repository
EOF

  type = list(object({
    name = string

    filter_groups = optional(list(list(object({
      type = string
      pattern = string
      exclude_matched_filter = optional(bool)
    }))))

    codebuild_cfg = optional(object({
      buildspec = optional(string)
      timeout   = optional(string)
      cache = optional(object({
        type     = optional(string)
        location = optional(string)
        modes    = optional(list(string))
      }))
      report_build_status = optional(bool)
      environment_type    = optional(string)
      compute_type        = optional(string)
      image               = optional(string)
      environment_variables = optional(list(object({
        name  = string
        value = string
        type  = optional(string)
      })))
      privileged_mode = optional(bool)
      certificate     = optional(string)
      artifacts = optional(object({
        type                   = optional(string)
        artifact_identifier    = optional(string)
        encryption_disabled    = optional(bool)
        override_artifact_name = optional(bool)
        location               = optional(string)
        name                   = optional(string)
        namespace_type         = optional(string)
        packaging              = optional(string)
        path                   = optional(string)
      }))
      secondary_artifacts = optional(object({
        type                   = optional(string)
        artifact_identifier    = optional(string)
        encryption_disabled    = optional(bool)
        override_artifact_name = optional(bool)
        location               = optional(string)
        name                   = optional(string)
        namespace_type         = optional(string)
        packaging              = optional(string)
        path                   = optional(string)
      }))
      role_arn = optional(string)
      logs_cfg = optional(object({
        cloudWatchLogs = optional(object({
          status     = string
          groupName  = string
          streamName = string
        }))
        s3Logs = optional(object({
          status   = string
          location = string
        }))
      }))
    }))
  }))
  default = []
}

# Lambda #

variable "lambda_trigger_codebuild_function_name" {
  description = "Name of AWS Lambda function that will start the AWS CodeBuild with the override configurations"
  type        = string
  default     = "infrastructure-modules-ci-trigger-build"
}

# Codebuild #

variable "codebuild_name" {
  description = "Name of Codebuild project"
  type        = string
  default     = "infrastructure-modules-ci-build"
}

variable "codebuild_description" {
  description = "CodeBuild project description"
  type        = string
  default     = null
}

variable "codebuild_assumable_role_arns" {
  description = "List of IAM role ARNS the Codebuild project can assume"
  type        = list(string)
  default     = []
}

variable "codebuild_buildspec" {
  description = "Content of the default buildspec file"
  type        = string
  default     = null
}

variable "codebuild_timeout" {
  description = "Minutes till build run is timed out"
  type        = string
  default     = null
}

variable "codebuild_cache" {
  description = "Cache configuration for Codebuild project"
  type = object({
    type     = optional(string)
    location = optional(string)
    modes    = optional(list(string))
  })
  default = {}
}

variable "codebuild_environment" {
  description = "Codebuild environment configuration"
  type = object({
    compute_type                = optional(string)
    image                       = optional(string)
    type                        = optional(string)
    image_pull_credentials_type = optional(string)
    environment_variables = optional(list(object({
      name  = string
      value = string
      type  = optional(string)
    })))
    privileged_mode = optional(bool)
    certificate     = optional(string)
    registry_credential = optional(object({
      credential          = optional(string)
      credential_provider = optional(string)
    }))
  })
  default = {}
}

variable "codebuild_artifacts" {
  description = <<EOF
Build project's primary output artifacts configuration
see for more info: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project#argument-reference
EOF
  type = object({
    type                   = optional(string)
    artifact_identifier    = optional(string)
    encryption_disabled    = optional(bool)
    override_artifact_name = optional(bool)
    location               = optional(string)
    name                   = optional(string)
    namespace_type         = optional(string)
    packaging              = optional(string)
    path                   = optional(string)
  })
  default = {}
}

variable "codebuild_secondary_artifacts" {
  description = "Build project's secondary output artifacts configuration"
  type = object({
    type                   = optional(string)
    artifact_identifier    = optional(string)
    encryption_disabled    = optional(bool)
    override_artifact_name = optional(bool)
    location               = optional(string)
    name                   = optional(string)
    namespace_type         = optional(string)
    packaging              = optional(string)
    path                   = optional(string)
  })
  default = {}
}

variable "enable_codebuild_s3_logs" {
  description = "Determines if S3 logs should be enabled"
  type        = bool
  default     = false
}

variable "codebuild_s3_log_key" {
  description = "Bucket path where the build project's logs will be stored (don't include bucket name)"
  type        = string
  default     = null
}

variable "codebuild_s3_log_bucket" {
  description = "Name of S3 bucket where the build project's logs will be stored"
  type        = string
  default     = null
}

variable "codebuild_s3_log_encryption" {
  description = "Determines if encryption should be disabled for the build project's S3 logs"
  type        = bool
  default     = false
}

variable "enable_codebuild_cw_logs" {
  description = "Determines if CloudWatch logs should be enabled"
  type        = bool
  default     = true
}

variable "codebuild_cw_group_name" {
  description = "CloudWatch group name"
  type        = string
  default     = null
}

variable "codebuild_cw_stream_name" {
  description = "CloudWatch stream name"
  type        = string
  default     = null
}

variable "codebuild_role_arn" {
  description = "Existing IAM role ARN to attach to CodeBuild project"
  type        = string
  default     = null
}

variable "codebuild_role_policy_statements" {
  description = "IAM policy statements to add to CodeBuild project's role"
  type = list(object({
    sid       = optional(string)
    effect    = string
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "codebuild_tags" {
  description = "Tags to attach to Codebuild project"
  type        = map(string)
  default     = {}
}

variable "codebuild_create_source_auth" {
  description = <<EOF
Determines if a CodeBuild source credential resource should be created. Only one credential
resource is needed/allowed per AWS account and region. See more at: https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_codebuild.GitHubSourceCredentials.html
EOF
  type        = bool
  default     = false
}

# AGW #

variable "api_name" {
  description = "Name of API-Gateway"
  type        = string
  default     = "github-webhook"
}

variable "api_description" {
  description = "Description for API-Gateway"
  type        = string
  default     = null
}