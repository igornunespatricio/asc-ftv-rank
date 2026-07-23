#!/usr/bin/env bash
set -euo pipefail

# Creates (or updates, idempotently) the IAM OIDC provider + IAM role that
# GitHub Actions assumes to run Terraform against AWS for this project.
#
# - Reuses the account's existing GitHub OIDC provider if one is already
#   present (an AWS account can only have ONE provider per URL — trying to
#   create a second for token.actions.githubusercontent.com fails).
# - Creates (or updates) a role SCOPED TO THIS REPO ONLY. Do not reuse a
#   role from another project — trust conditions and permissions here are
#   specific to asc-ftv-rank's repo name and state bucket.
# - Trust policy allows: pushes to `main` (dev auto-apply), and
#   workflow_dispatch runs against the `test` / `prod` GitHub Environments
#   (manual applies) — matching the CI/CD workflow trigger strategy.
# - Permissions are scoped to this project's state bucket prefix
#   (workspace_key_prefix "asc-ftv-rank") and the AWS services this stack
#   actually uses: DynamoDB, Lambda, API Gateway, S3, CloudFront, plus the
#   IAM actions needed to manage Lambda execution roles.
#
# Sources the state bucket name from the GitHub repo variable
# TF_STATE_BUCKET (set by 01_create_terraform_state_bucket.sh) — errors out
# if it isn't set.
#
# Assumes this script lives in scripts/ (repo-root/scripts/).
# Assumes it's run from inside a clone of the GitHub repo (gh infers the
# repo from the local git remote) and that `gh auth login` and
# `aws configure` (or equivalent credentials) are already set up.
#
# Usage:
#   ./04_create_github_oidc_role.sh

ROLE_NAME="asc-ftv-rank-github-actions-role"
POLICY_NAME="asc-ftv-rank-terraform-deploy-policy"
OIDC_URL="token.actions.githubusercontent.com"
# GitHub's current intermediate CA thumbprint. AWS no longer actually
# validates against this value for GitHub's provider (it verifies via TLS
# automatically) but the CLI still requires a value to be supplied.
THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"

command -v aws >/dev/null || { echo "aws CLI not found."; exit 1; }
command -v gh >/dev/null || { echo "gh CLI not found. Install: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null || { echo "Run 'gh auth login' first."; exit 1; }

REPO_FULL="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "Using repo: ${REPO_FULL}"

echo "Reading TF_STATE_BUCKET from GitHub repo variables..."
BUCKET_NAME="$(gh api "repos/${REPO_FULL}/actions/variables/TF_STATE_BUCKET" --jq .value 2>/dev/null || true)"
if [ -z "${BUCKET_NAME}" ]; then
  echo "Error: repo variable TF_STATE_BUCKET not found on ${REPO_FULL}."
  echo "Run scripts/01_create_terraform_state_bucket.sh first."
  exit 1
fi
echo "Using state bucket: ${BUCKET_NAME}"

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_URL}"

# --- 1. OIDC provider: reuse if it exists, create if it doesn't ---
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${PROVIDER_ARN}" --query "Url" --output text >/dev/null 2>&1; then
  echo "OIDC provider already exists, reusing: ${PROVIDER_ARN}"
else
  echo "Creating OIDC provider for ${OIDC_URL}..."
  aws iam create-open-id-connect-provider \
    --url "https://${OIDC_URL}" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "${THUMBPRINT}"
fi

# --- 2. Trust policy, scoped to this repo only ---
TRUST_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "${PROVIDER_ARN}" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_URL}:sub": [
            "repo:${REPO_FULL}:ref:refs/heads/main",
            "repo:${REPO_FULL}:environment:test",
            "repo:${REPO_FULL}:environment:prod"
          ]
        }
      }
    }
  ]
}
JSON
)

if aws iam get-role --role-name "${ROLE_NAME}" --query "Role.RoleName" --output text >/dev/null 2>&1; then
  echo "Role '${ROLE_NAME}' already exists, updating trust policy..."
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document "${TRUST_POLICY}"
else
  echo "Creating role '${ROLE_NAME}'..."
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "GitHub Actions OIDC role for asc-ftv-rank Terraform deploys"
fi

# --- 3. Permissions policy, scoped to this project's state prefix + stack ---
PERMISSIONS_POLICY=$(cat <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/asc-ftv-rank/*"
    },
    {
      "Sid": "TerraformStateBucketList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Sid": "ProjectServices",
      "Effect": "Allow",
      "Action": [
        "dynamodb:*",
        "lambda:*",
        "apigateway:*",
        "cloudfront:*",
        "s3:*",
        "logs:*",
        "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole",
        "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"
      ],
      "Resource": "*"
    },
    {
      "Sid": "JwtSecretParameter",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:DeleteParameter",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "ssm:ListTagsForResource"
      ],
      "Resource": "arn:aws:ssm:*:${AWS_ACCOUNT_ID}:parameter/footvolley/*"
    }
  ]
}
JSON
)

echo "Setting permissions policy '${POLICY_NAME}' on role '${ROLE_NAME}'..."
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document "${PERMISSIONS_POLICY}"

# --- 4. Push the role ARN into GitHub repo variables ---
ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text)"
echo "Confirmed role ARN: ${ROLE_ARN}"

echo "Setting GitHub repo variable AWS_ROLE_ARN..."
gh variable set AWS_ROLE_ARN --repo "${REPO_FULL}" --body "${ROLE_ARN}"

echo
echo "Done."
echo "OIDC provider: ${PROVIDER_ARN}"
echo "Role ARN:      ${ROLE_ARN}"
echo "GitHub repo variable AWS_ROLE_ARN set on: ${REPO_FULL}"