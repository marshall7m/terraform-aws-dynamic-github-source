variable "github_token" {
  description = "Github token used to authorize Codebuild to clone target repos"
  type        = string
  sensitive   = true
}