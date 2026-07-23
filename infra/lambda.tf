# -----------------------------------------------------------------------------
# Lambda source packaging
# -----------------------------------------------------------------------------
# Grouped-by-resource: matches, users, auth, authorizer (see CLAUDE.md
# conventions). Each directory is zipped independently.
# -----------------------------------------------------------------------------
data "archive_file" "matches" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/matches"
  output_path = "${path.module}/../build/matches.zip"
}

data "archive_file" "users" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/users"
  output_path = "${path.module}/../build/users.zip"
}

data "archive_file" "auth" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/auth"
  output_path = "${path.module}/../build/auth.zip"
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/authorizer"
  output_path = "${path.module}/../build/authorizer.zip"
}

# -----------------------------------------------------------------------------
# IAM — one role per Lambda, least-privilege inline policy per table it needs.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- matches Lambda ---
# Full CRUD on Matches. Read-only on Users (BatchGetItem) to resolve player
# names — per CLAUDE.md default: batch-get from Users rather than denormalize.
resource "aws_iam_role" "matches" {
  name               = "${var.project_name}-${local.environment}-matches-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "matches_logs" {
  role       = aws_iam_role.matches.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "matches_policy" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      aws_dynamodb_table.matches.arn,
      "${aws_dynamodb_table.matches.arn}/index/*",
    ]
  }
  statement {
    actions   = ["dynamodb:BatchGetItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.users.arn]
  }
}

resource "aws_iam_role_policy" "matches" {
  name   = "${var.project_name}-${local.environment}-matches-policy"
  role   = aws_iam_role.matches.id
  policy = data.aws_iam_policy_document.matches_policy.json
}

# --- users Lambda ---
# Full CRUD on Users, including the EmailIndex GSI.
resource "aws_iam_role" "users" {
  name               = "${var.project_name}-${local.environment}-users-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "users_logs" {
  role       = aws_iam_role.users.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "users_policy" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [
      aws_dynamodb_table.users.arn,
      "${aws_dynamodb_table.users.arn}/index/*",
    ]
  }
}

resource "aws_iam_role_policy" "users" {
  name   = "${var.project_name}-${local.environment}-users-policy"
  role   = aws_iam_role.users.id
  policy = data.aws_iam_policy_document.users_policy.json
}

# --- auth Lambda ---
# Read-only on Users (EmailIndex lookup for login), plus read on the JWT
# secret to sign tokens.
resource "aws_iam_role" "auth" {
  name               = "${var.project_name}-${local.environment}-auth-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "auth_logs" {
  role       = aws_iam_role.auth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "auth_policy" {
  statement {
    actions   = ["dynamodb:Query"]
    resources = ["${aws_dynamodb_table.users.arn}/index/EmailIndex"]
  }
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.jwt_secret.arn]
  }
}

resource "aws_iam_role_policy" "auth" {
  name   = "${var.project_name}-${local.environment}-auth-policy"
  role   = aws_iam_role.auth.id
  policy = data.aws_iam_policy_document.auth_policy.json
}

# --- authorizer Lambda ---
# Only needs to verify a JWT signature — no DynamoDB access. is_admin and
# other claims travel inside the token itself, so no DB round-trip per request.
resource "aws_iam_role" "authorizer" {
  name               = "${var.project_name}-${local.environment}-authorizer-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "authorizer_policy" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.jwt_secret.arn]
  }
}

resource "aws_iam_role_policy" "authorizer" {
  name   = "${var.project_name}-${local.environment}-authorizer-policy"
  role   = aws_iam_role.authorizer.id
  policy = data.aws_iam_policy_document.authorizer_policy.json
}

# -----------------------------------------------------------------------------
# Lambda functions
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "matches" {
  function_name    = "${var.project_name}-${local.environment}-matches"
  role             = aws_iam_role.matches.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.matches.output_path
  source_code_hash = data.archive_file.matches.output_base64sha256

  environment {
    variables = {
      MATCHES_TABLE_NAME = aws_dynamodb_table.matches.name
      USERS_TABLE_NAME   = aws_dynamodb_table.users.name
    }
  }
}

resource "aws_lambda_function" "users" {
  function_name    = "${var.project_name}-${local.environment}-users"
  role             = aws_iam_role.users.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.users.output_path
  source_code_hash = data.archive_file.users.output_base64sha256

  environment {
    variables = {
      USERS_TABLE_NAME = aws_dynamodb_table.users.name
    }
  }
}

resource "aws_lambda_function" "auth" {
  function_name    = "${var.project_name}-${local.environment}-auth"
  role             = aws_iam_role.auth.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.auth.output_path
  source_code_hash = data.archive_file.auth.output_base64sha256

  environment {
    variables = {
      USERS_TABLE_NAME = aws_dynamodb_table.users.name
      JWT_SECRET_PARAM = aws_ssm_parameter.jwt_secret.name
    }
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-${local.environment}-authorizer"
  role             = aws_iam_role.authorizer.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256

  environment {
    variables = {
      JWT_SECRET_PARAM = aws_ssm_parameter.jwt_secret.name
    }
  }
}
