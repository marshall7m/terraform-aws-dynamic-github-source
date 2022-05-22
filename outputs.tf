output "api_deployment_invoke_url" {
  description = "API invoke URL the github webhook will ping"
  value       = module.github_webhook_request_validator.deployment_invoke_url
}

output "request_validator_function_arn" {
  description = "ARN of the Lambda function that validates incoming requests"
  value       = module.github_webhook_request_validator.function_arn
}

output "request_validator_cw_log_group_arn" {
  description = "ARN of the Cloudwatch log group associated with the Lambda function that validates the incoming requests"
  value       = module.github_webhook_request_validator.lambda_log_group_arn
}

output "request_validator_function_name" {
  description = "Name of the Cloudwatch log group associated with the Lambda function that validates the incoming requests"
  value       = module.lambda_trigger_codebuild.function_name
}

output "trigger_codebuild_function_arn" {
  description = "ARN of the Lambda function that triggers the downstream CodeBuild project with repo specific configurations"
  value       = module.lambda_trigger_codebuild.function_arn
}

output "trigger_codebuild_function_name" {
  description = "Name of the Lambda function that triggers the downstream CodeBuild project with repo specific configurations"
  value       = module.lambda_trigger_codebuild.function_name
}

output "trigger_codebuild_cw_log_group_arn" {
  description = "ARN of the Cloudwatch log group associated with the Lambda function that triggers the downstream CodeBuild project"
  value       = module.lambda_trigger_codebuild.cw_log_group_arn
}

output "codebuild_arn" {
  description = "ARN of the CodeBuild project will be conditionally triggered from the payload validator Lambda function"
  value       = module.codebuild.arn
}

