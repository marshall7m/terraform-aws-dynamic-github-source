variable "testing_github_token" {
  description = "GitHub token to create GitHub webhook for repos defined in var.repos (permission: )"
  type        = string
  sensitive   = true
  default     = null
}

variable "repos" {
  description = <<EOF
Map of keys with GitHub repo names and values representing their respective filter groups used to select
what type of activities will trigger the associated Codebuild project.
Params:
  {
    <repo full name (e.g user/repo)> : {
      `filter_groups`: List of filter groups that the Github activity has to meet. The activity has to meet all filters of atleast one group in order to succeed. 
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
              `pattern`: Regex pattern that is searched for within the activity's related payload attribute. For `type` = `event`, use a single Github webhook event and not a regex pattern.
              `exclude_matched_filter` - If set to true, labels filter group as invalid if matched
            }
          ]
        ]
      `codebuild_cfg`: CodeBuild configurations used specifically for the repository. See AWS docs for details: https://docs.aws.amazon.com/codebuild/latest/APIReference/API_StartBuild.html
    }
  
EOF

  type = map(object({

    filter_groups = optional(list(list(object({
      type                   = string
      pattern                = string
      exclude_matched_filter = optional(bool)
    }))))

    codebuild_cfg = optional(any)
  }))
  default = {}
}