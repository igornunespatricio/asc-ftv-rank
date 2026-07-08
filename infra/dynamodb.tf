# -----------------------------------------------------------------------------
# Users table
# -----------------------------------------------------------------------------
# Primary key: id (UUID string)
# GSI: EmailIndex — used by the login Lambda to look up a user by email.
#
# Note: status and is_admin are stored as plain attributes (not projected into
# a GSI). Per CLAUDE.md, a StatusIndex GSI is a possible future addition if
# scanning for active players becomes a measured bottleneck — not added yet.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "users" {
  name         = "${var.project_name}-${local.environment}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "EmailIndex"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Project     = var.project_name
    Environment = local.environment
  }
}

# -----------------------------------------------------------------------------
# Matches table
# -----------------------------------------------------------------------------
# Primary key: id (UUID string)
# GSI: MatchDateIndex — supports "matches in date range" queries without a
# full table scan.
#
# Partition strategy chosen: MONTH-BUCKET (not a constant key). Each match
# item stores a computed `match_month` attribute in "YYYY-MM" format at write
# time (derived from match_date in the Lambda handler, not user-supplied).
# The GSI hash key is match_month, range key is match_date (ISO date string),
# so queries filter to relevant month(s) and Terraform doesn't need to change
# as data grows. This is the default noted in CLAUDE.md's open decisions —
# confirm before relying on it, since a constant partition key ("MATCH") was
# the alternative and is simpler at low volume but doesn't scale as well.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "matches" {
  name         = "${var.project_name}-${local.environment}-matches"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "match_month"
    type = "S"
  }

  attribute {
    name = "match_date"
    type = "S"
  }

  global_secondary_index {
    name            = "MatchDateIndex"
    hash_key        = "match_month"
    range_key       = "match_date"
    projection_type = "ALL"
  }

  tags = {
    Project     = var.project_name
    Environment = local.environment
  }
}
