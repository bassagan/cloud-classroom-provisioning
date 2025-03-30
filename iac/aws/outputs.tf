output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.user_management.arn
}

output "lambda_function_url" {
  description = "URL of the Lambda function"
  value       = aws_lambda_function_url.create_user_url.function_url
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.lambda_code.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.lambda_code.id
}
