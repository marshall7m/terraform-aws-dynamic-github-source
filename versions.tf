terraform {
  required_version = ">=1.0.0"
  experiments      = [module_variable_optional_attrs]
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.23"
    }
    github = {
      source  = "integrations/github"
      version = ">= 4.4.0"
    }
  }
}