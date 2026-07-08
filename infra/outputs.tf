output "users_table_name" {
  description = "Name of the Users DynamoDB table"
  value       = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  description = "ARN of the Users DynamoDB table"
  value       = aws_dynamodb_table.users.arn
}

output "matches_table_name" {
  description = "Name of the Matches DynamoDB table"
  value       = aws_dynamodb_table.matches.name
}

output "matches_table_arn" {
  description = "ARN of the Matches DynamoDB table"
  value       = aws_dynamodb_table.matches.arn
}
