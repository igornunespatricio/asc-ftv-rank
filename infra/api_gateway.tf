# -----------------------------------------------------------------------------
# HTTP API
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-${local.environment}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"] # tighten to the CloudFront domain once it exists
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = local.environment
  auto_deploy = true
}

# -----------------------------------------------------------------------------
# Lambda authorizer (REQUEST type, simple response, reads Authorization header)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "${var.project_name}-${local.environment}-jwt-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_result_ttl_in_seconds  = 300
}

resource "aws_lambda_permission" "authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# Integrations
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "matches" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.matches.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "users" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.users.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "auth" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "matches_invoke" {
  statement_id  = "AllowAPIGatewayInvokeMatches"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.matches.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "users_invoke" {
  statement_id  = "AllowAPIGatewayInvokeUsers"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "auth_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# -----------------------------------------------------------------------------
# Routes — public
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "login" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /auth/login"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

resource "aws_apigatewayv2_route" "get_matches" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /matches"
  target    = "integrations/${aws_apigatewayv2_integration.matches.id}"
}

resource "aws_apigatewayv2_route" "get_ranking" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /ranking"
  target    = "integrations/${aws_apigatewayv2_integration.matches.id}"
}

resource "aws_apigatewayv2_route" "get_active_players" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /players/active"
  target    = "integrations/${aws_apigatewayv2_integration.users.id}"
}

# -----------------------------------------------------------------------------
# Routes — admin-only (JWT authorizer attached)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "create_match" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /matches"
  target             = "integrations/${aws_apigatewayv2_integration.matches.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "update_match" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "PUT /matches/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.matches.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "delete_match" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "DELETE /matches/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.matches.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "get_users" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /users"
  target             = "integrations/${aws_apigatewayv2_integration.users.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "create_user" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /users"
  target             = "integrations/${aws_apigatewayv2_integration.users.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "update_user" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "PUT /users/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.users.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "delete_user" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "DELETE /users/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.users.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------
output "api_invoke_url" {
  value = aws_apigatewayv2_stage.main.invoke_url
}
