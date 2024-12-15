output "bucket_name" {
  description = "Name of the S3 bucket used to store function code."
  value = aws_s3_bucket.lambda_bucket.id
}

output "gateway_url" {
  description = "Base URL for API Gateway stage."
  value = module.api_gateway.default_apigatewayv2_stage_invoke_url
}

output "secret_manager" {
  description = "ARN of secret manager for redshift"
  value = aws_secretsmanager_secret.redshift.arn
}
