output "api_invoke_url" {
  description = "API invoke URL the github webhook will ping"
  value       = module.github_webhook_request_validator.invoke_url
}

output "request_validator_function_arn" {
  description = "ARN of the Lambda function that validates the Github request"
  value       = module.github_webhook_request_validator.function_arn
}

output "request_validator_cw_log_group_arn" {
  description = "Name of the Cloudwatch log group associated with the request validator Lambda Function"
  value       = module.lambda.cw_log_group_arn
}

output "payload_validator_function_arn" {
  description = "ARN of the Lambda function that validates the Github payload"
  value       = module.lambda.function_arn
}

output "payload_validator_cw_log_group_arn" {
  description = "Name of the Cloudwatch log group associated with the payload validator Lambda Function"
  value       = module.github_webhook_request_validator.cw_log_group_arn
}

output "codebuild_arn" {
  description = "ARN of the CodeBuild project will be conditionally triggered from the payload validator Lambda function"
  value       = module.codebuild.arn
}

