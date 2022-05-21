module "mut_terraform_infrastructure_modules_defaults" {
  source = "../../../.."

  repos = [
    {
      name = "test-user/dummy-repo"
      filter_groups = [
        [
          {
            type = "event"
            pattern = "push"
          },
          {
            type = "file_paths"
            pattern = ".+\\.tf$"
          }
        ],
        [
          {
            type = "event"
            pattern = "pull_request"
          },
          {
            type = "pr_actions"
            pattern = "(opened|edited|reopened)"
          },
          {
            type = "file_paths" 
            pattern = ".+\\.tf$"
          },
          {
            type = "head_ref"
            pattern = "test-branch"
          }
        ]
      ]
    }
  ]
}

