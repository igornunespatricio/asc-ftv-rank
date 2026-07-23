# -----------------------------------------------------------------------------
# JWT signing secret
# -----------------------------------------------------------------------------
# Generated once per environment (workspace), stored as a SecureString in SSM
# Parameter Store. Both the auth Lambda (issues tokens) and the authorizer
# Lambda (verifies tokens) read this at invoke time via GetParameter.
# -----------------------------------------------------------------------------
resource "random_password" "jwt_secret" {
  length  = 64
  special = true
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/${var.project_name}/${local.environment}/jwt-secret"
  type  = "SecureString"
  value = random_password.jwt_secret.result

  tags = {
    Project     = var.project_name
    Environment = local.environment
  }
}
