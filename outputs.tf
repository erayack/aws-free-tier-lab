output "lambda_url" {
  value = aws_lambda_function_url.demo.function_url
}

output "ec2_instance_id" {
  value = aws_instance.demo.id
}

output "rds_identifier" {
  value = aws_db_instance.demo.identifier
}
