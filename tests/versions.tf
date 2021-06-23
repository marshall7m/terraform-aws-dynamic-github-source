terraform {
  required_version = ">=0.15.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
    testing = {
      source  = "apparentlymart/testing"
      version = "0.0.2"
    }
    test = {
      source = "terraform.io/builtin/test"
    }
    github = {
      source  = "integrations/github"
      version = "4.9.3"
    }
    # bash = {
    #   source = "apparentlymart/bash"
    #   version = ">= 0.1.0"
    # }
  }
}
