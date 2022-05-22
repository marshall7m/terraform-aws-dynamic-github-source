variable "testing_github_token" {
  description = "GitHub token to create GitHub webhook for repos defined in var.repos (permission: )"
  type        = string
  sensitive   = true
  default     = null
}

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
      type                   = string
      pattern                = string
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