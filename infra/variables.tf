variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name, used as a prefix for resource naming"
  type        = string
  default     = "footvolley"
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for all Lambda functions in this project."
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Memory (MB) allocated to all Lambda functions in this project."
  type        = number
  default     = 256
}
