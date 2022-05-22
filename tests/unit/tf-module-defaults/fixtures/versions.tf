terraform {
  experiments      = [module_variable_optional_attrs]
  required_version = ">=1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.15.1"
    }
    github = {
      source  = "integrations/github"
      version = ">= 4.4.0"
    }
  }
}