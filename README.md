# dynamic-github-source

## Problem ##

Current implementation of AWS CodeBuild (as of: 6/19/21) doesn't allow for dynamic repo and branch source. CodeBuild does allow for up to 12 secondary sources, although the buildspec would have to have additional logic to explicitly switch to the secondary source that was trigger via the CodeBuild Webhook. Another painful workaround is to create a Codebuild project for each repository. If each repo requires the same CodeBuild configurations, this can lead to multiple copies of the same CodeBuild project but with different sources. This can consequently clutter your AWS CodeBuild workspace especially if there are hundreds of repositories are included in this process.

## Process ##

![cloudcraft](cloudcraft.png)

### Steps ###

1. Github event is performed (e.g. user pushes new file, opens PR, etc.) that falls under one of the repository's event filters
2. Github webhook sends a POST HTTP method request to the API Gateway's (AGW) REST API 
3. AGW request integration maps the request to a format friendly format `{'headers': <Webhook headers>, 'body': <Webhook payload>}` Processed request is passed to the request validator function.
4. Request validator function compares the `sha256` value from the request header with the `sha256` value created with the Github secret value and request payload. If the values are are not equal, then an error response is sent to the Github webhook. If the values are not equal, the Lambda function validates the payload against the filter groups defined for that repository. If the payload passes atleast one filter group, then the Lambda function succeeds invokes the next Lambda function asynchronously.
5. The second Lambda function triggers the Codebuild project with the repository's respective CodeBuild configurations ONLY for that build (after this build, CodeBuild project reverts to original configurations). The main attribute that is changed is the source configurations for the build which allow one CodeBuild to use a dynamic source.
6. CodeBuild performs the defined buildspec logic. User can define a global or repo-level buildspec that can be used for CI/CD, building AMIs, etc. 

## Non-Provider related Requirements
- The environment in which the Terraform module is applied must have pip within it's `$PATH`. The `resource "null_resource" "lambda_pip_deps" {}` installs the `PyGithub` package locally via `pip` and then is used within the payload validator function. 

## Usage

Minimal viable configuration:

```
module "dynamic_github_source" {
  source                         = "github.com/marshall7m/terraform-aws-infrastructure-modules-ci"
  create_github_secret_ssm_param = true
  github_secret_ssm_value        = var.github_secret_ssm_value
  github_token_ssm_value         = var.github_token
  codebuild_buildspec            = file("buildspec.yaml")
  repos = [
    {
      name = "test-repo"
      filter_groups = [
        {
          events     = ["push"]
        }
      ]
    }
  ]
}
```

Configure repo specific codebuild configurations via `codebuild_cfg` within `repos` list:

```
module "dynamic_github_source" {
  source                         = "github.com/marshall7m/terraform-aws-infrastructure-modules-ci"
  create_github_secret_ssm_param = true
  github_secret_ssm_value        = var.github_secret_ssm_value
  github_token_ssm_value         = var.github_token
  codebuild_name                 = "test-codebuild"
  codebuild_buildspec            = file("buildspec.yaml")
  repos = [
    {
      name = "test-repo"
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
}
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >=0.15.0 |
| aws | >= 2.23 |
| github | >= 4.4.0 |

## Providers

| Name | Version |
|------|---------|
| archive | n/a |
| aws | >= 2.23 |
| local | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| api\_description | Description for API-Gateway | `string` | `null` | no |
| api\_name | Name of API-Gateway | `string` | `"github-webhook"` | no |
| codebuild\_artifacts | Build project's primary output artifacts configuration<br>see for more info: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project#argument-reference | <pre>object({<br>    type                   = optional(string)<br>    artifact_identifier    = optional(string)<br>    encryption_disabled    = optional(bool)<br>    override_artifact_name = optional(bool)<br>    location               = optional(string)<br>    name                   = optional(string)<br>    namespace_type         = optional(string)<br>    packaging              = optional(string)<br>    path                   = optional(string)<br>  })</pre> | `{}` | no |
| codebuild\_assumable\_role\_arns | List of IAM role ARNS the Codebuild project can assume | `list(string)` | `[]` | no |
| codebuild\_buildspec | Content of the default buildspec file | `string` | `null` | no |
| codebuild\_cache | Cache configuration for Codebuild project | <pre>object({<br>    type     = optional(string)<br>    location = optional(string)<br>    modes    = optional(list(string))<br>  })</pre> | `{}` | no |
| codebuild\_cw\_group\_name | CloudWatch group name | `string` | `null` | no |
| codebuild\_cw\_stream\_name | CloudWatch stream name | `string` | `null` | no |
| codebuild\_description | CodeBuild project description | `string` | `null` | no |
| codebuild\_environment | Codebuild environment configuration | <pre>object({<br>    compute_type                = optional(string)<br>    image                       = optional(string)<br>    type                        = optional(string)<br>    image_pull_credentials_type = optional(string)<br>    environment_variables = optional(list(object({<br>      name  = string<br>      value = string<br>      type  = optional(string)<br>    })))<br>    privileged_mode = optional(bool)<br>    certificate     = optional(string)<br>    registry_credential = optional(object({<br>      credential          = optional(string)<br>      credential_provider = optional(string)<br>    }))<br>  })</pre> | `{}` | no |
| codebuild\_name | Name of Codebuild project | `string` | n/a | yes |
| codebuild\_role\_arn | Existing IAM role ARN to attach to CodeBuild project | `string` | `null` | no |
| codebuild\_s3\_log\_bucket | Name of S3 bucket where the build project's logs will be stored | `string` | `null` | no |
| codebuild\_s3\_log\_encryption | Determines if encryption should be disabled for the build project's S3 logs | `bool` | `false` | no |
| codebuild\_s3\_log\_key | Bucket path where the build project's logs will be stored (don't include bucket name) | `string` | `null` | no |
| codebuild\_secondary\_artifacts | Build project's secondary output artifacts configuration | <pre>object({<br>    type                   = optional(string)<br>    artifact_identifier    = optional(string)<br>    encryption_disabled    = optional(bool)<br>    override_artifact_name = optional(bool)<br>    location               = optional(string)<br>    name                   = optional(string)<br>    namespace_type         = optional(string)<br>    packaging              = optional(string)<br>    path                   = optional(string)<br>  })</pre> | `{}` | no |
| codebuild\_tags | Tags to attach to Codebuild project | `map(string)` | `{}` | no |
| codebuild\_timeout | Minutes till build run is timed out | `string` | `null` | no |
| common\_tags | Tags to add to all resources | `map(string)` | `{}` | no |
| enable\_codebuild\_cw\_logs | Determines if CloudWatch logs should be enabled | `bool` | `true` | no |
| enable\_codebuild\_s3\_logs | Determines if S3 logs should be enabled | `bool` | `false` | no |
| function\_name | Name of AWS Lambda function | `string` | `"github-webhook-payload-validator"` | no |
| github\_secret\_ssm\_description | Github secret SSM parameter description | `string` | `"Secret value for Github Webhooks"` | no |
| github\_secret\_ssm\_key | SSM parameter store key for github webhook secret. Secret used within Lambda function for Github request validation. | `string` | `"github-webhook-secret"` | no |
| github\_secret\_ssm\_tags | Tags for Github webhook secret SSM parameter | `map(string)` | `{}` | no |
| github\_token\_ssm\_description | Github token SSM parameter description | `string` | `"Github token used to give read access to the payload validator function to get file that differ between commits"` | no |
| github\_token\_ssm\_key | AWS SSM Parameter Store key for sensitive Github personal token | `string` | `"github-payload-validator"` | no |
| github\_token\_ssm\_tags | Tags for Github token SSM parameter | `map(string)` | `{}` | no |
| github\_token\_ssm\_value | Registered Github webhook token associated with the Github provider. If not provided, module looks for pre-existing SSM parameter via `github_token_ssm_key` | `string` | `""` | no |
| repos | List of named repos to create github webhooks for and their respective filter groups used to select<br>what type of activity will trigger the associated Codebuild.<br>Params:<br>  `name`: Repository name<br>  `codebuild_cfg`: CodeBuild configurations specifically for the repository | <pre>list(object({<br>    name = string<br><br>    codebuild_cfg = optional(object({<br>      buildspec = optional(string)<br>      timeout   = optional(string)<br>      cache = optional(object({<br>        type     = optional(string)<br>        location = optional(string)<br>        modes    = optional(list(string))<br>      }))<br>      report_build_status = optional(bool)<br>      environment_type    = optional(string)<br>      compute_type        = optional(string)<br>      image               = optional(string)<br>      environment_variables = optional(list(object({<br>        name  = string<br>        value = string<br>        type  = optional(string)<br>      })))<br>      privileged_mode = optional(bool)<br>      certificate     = optional(string)<br>      artifacts = optional(object({<br>        type                   = optional(string)<br>        artifact_identifier    = optional(string)<br>        encryption_disabled    = optional(bool)<br>        override_artifact_name = optional(bool)<br>        location               = optional(string)<br>        name                   = optional(string)<br>        namespace_type         = optional(string)<br>        packaging              = optional(string)<br>        path                   = optional(string)<br>      }))<br>      secondary_artifacts = optional(object({<br>        type                   = optional(string)<br>        artifact_identifier    = optional(string)<br>        encryption_disabled    = optional(bool)<br>        override_artifact_name = optional(bool)<br>        location               = optional(string)<br>        name                   = optional(string)<br>        namespace_type         = optional(string)<br>        packaging              = optional(string)<br>        path                   = optional(string)<br>      }))<br>      role_arn = optional(string)<br>      logs_cfg = optional(object({<br>        cloudWatchLogs = optional(object({<br>          status     = string<br>          groupName  = string<br>          streamName = string<br>        }))<br>        s3Logs = optional(object({<br>          status   = string<br>          location = string<br>        }))<br>      }))<br>    }))<br>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| api\_invoke\_url | API invoke URL the github webhook will ping |
| codebuild\_arn | ARN of the CodeBuild project will be conditionally triggered from the payload validator Lambda function |
| payload\_validator\_cw\_log\_group\_arn | Name of the Cloudwatch log group associated with the payload validator Lambda Function |
| payload\_validator\_function\_arn | ARN of the Lambda function that validates the Github payload |
| request\_validator\_cw\_log\_group\_arn | Name of the Cloudwatch log group associated with the request validator Lambda Function |
| request\_validator\_function\_arn | ARN of the Lambda function that validates the Github request |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->


## Features:
- Interval builds:
  - Runs CodeBuild only within specified time period
  - Checks if commit is within time period via Lambda function

## TODO:
- Add CodeBuild report group to check if test buildspec succeeds
  - Use build-in terraform test resource to check report group status