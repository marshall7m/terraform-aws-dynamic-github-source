terraform {
  before_hook "before_hook" {
    commands = ["validate", "plan", "apply"]
    execute  = ["bash", "-c", local.before_hook]
  }
}

locals {
  provider_switches = merge(
    read_terragrunt_config(find_in_parent_folders("provider_switches.hcl", "null.hcl"), {}),
    read_terragrunt_config("provider_switches.hcl", {})
  )

  before_hook = <<-EOF
  %{if try(local.provider_switches.locals.include_github, false)}
  if [[ -z $GITHUB_TOKEN ]]; then echo Getting Github Token && export GITHUB_TOKEN=$(pass github/token); fi 
  %{endif}
  if [[ -z $SKIP_TFENV ]]; then 
  echo Scanning Terraform files for Terraform binary version constraint 
  tfenv use min-required || tfenv install min-required \
  && tfenv use min-required
  else 
  echo Skip scanning Terraform files for Terraform binary version constraint
  tfenv version-name
  fi
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "skip"
  contents  = <<-EOF
  terraform {
    required_version = ">=0.15.0"
    required_providers {
  %{if try(local.provider_switches.locals.include_aws, false)}
    aws = {
      source = "hashicorp/aws"
      version = "3.35.0"
    }
  %{endif}
  %{if try(local.provider_switches.locals.include_github, false)}
    github = {
      source  = "integrations/github"
      version = ">=4.4.0"
    }
  %{endif}
  %{if try(local.provider_switches.locals.include_test, false)}
    test = {
      source  = "terraform.io/builtin/test"
    }
  %{endif}
    }
  }
  provider "testing" {}
  %{if try(local.provider_switches.locals.include_aws, false)}
  provider "aws" {
    region = "us-west-2"  
    profile = "sandbox-admin"
  }
  %{endif}
  %{if try(local.provider_switches.locals.include_github, false)}
  provider "github" {
      owner = "marshall7m"
  }
  %{endif}
  EOF
}

remote_state {
  backend = "local"
  config  = {}
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}