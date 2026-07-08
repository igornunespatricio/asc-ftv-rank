#!/usr/bin/env bash
set -euo pipefail

# Creates an S3 bucket (random suffix) for Terraform remote state, writes the
# resulting bucket name + ARN to a JSON file inside a gitignored local folder
# at the project root (local-state-info/), and pushes the bucket name + ARN
# into the current GitHub repo's Actions variables so CI/CD can use them.
#
# The JSON file is for local reference only — CI/CD does NOT read it; it
# reconstructs the same values from the GitHub repo variables set at the
# end of this script.
#
# Assumes this script lives in scripts/ (repo-root/scripts/01_create_terraform_state_bucket.sh).
#
# Assumes it's run from inside a clone of the GitHub repo (gh infers the
# repo from the local git remote) and that `gh auth login` has been run.
#
# No versioning is configured — recovering a prior state after an
# accidental overwrite/delete won't be possible without it.
#
# Usage:
#   ./01_create_terraform_state_bucket.sh [aws-region]
#
# Example:
#   ./01_create_terraform_state_bucket.sh us-east-1
#   (produces local/terraform_state_bucket_info.json —
#   this folder is gitignored, see local/ in .gitignore)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_DIR="${PROJECT_ROOT}/local"   # gitignored — local reference only
mkdir -p "${LOCAL_DIR}"

REGION="${1:-us-east-1}"
SUFFIX=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
BUCKET_NAME="terraform-state-files-${SUFFIX}"
BUCKET_ARN="arn:aws:s3:::${BUCKET_NAME}"

JSON_FILE="${LOCAL_DIR}/terraform_state_bucket_info.json"

echo json_file="${JSON_FILE}"

# --- Preflight: needed for the GitHub variables step later ---
command -v gh >/dev/null || { echo "gh CLI not found. Install: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null || { echo "Run 'gh auth login' first."; exit 1; }

echo "Creating bucket '${BUCKET_NAME}' in region '${REGION}'..."

if [ "${REGION}" = "us-east-1" ]; then
  # us-east-1 is the one region that rejects a LocationConstraint
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}"
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

echo "Enabling default encryption (AES256)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

echo "Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Writing bucket name and ARN to '${JSON_FILE}'..."
cat > "${JSON_FILE}" << INFO
{
  "bucket_name": "${BUCKET_NAME}",
  "bucket_arn": "${BUCKET_ARN}",
  "region": "${REGION}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
INFO

echo "Setting GitHub repository variables for CI/CD..."
REPO_FULL="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
gh variable set TF_STATE_BUCKET --repo "${REPO_FULL}" --body "${BUCKET_NAME}"
gh variable set TF_STATE_BUCKET_ARN --repo "${REPO_FULL}" --body "${BUCKET_ARN}"
gh variable set TF_STATE_BUCKET_REGION --repo "${REPO_FULL}" --body "${REGION}"

echo
echo "Done."
echo "Bucket name: ${BUCKET_NAME}"
echo "Bucket ARN:  ${BUCKET_ARN}"
echo "JSON details written to: ${JSON_FILE}"
echo "GitHub repo variables set on: ${REPO_FULL} (TF_STATE_BUCKET, TF_STATE_BUCKET_ARN, TF_STATE_BUCKET_REGION)"
echo
echo "Note: with AWS provider v6.x+, use 'use_lockfile = true' in your backend"
echo "config for native S3 state locking — no DynamoDB lock table needed."