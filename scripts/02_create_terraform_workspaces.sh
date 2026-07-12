#!/usr/bin/env bash
set -euo pipefail

# Creates the dev, test, and prod Terraform workspaces.
#
# Sources the S3 backend's bucket + region from the GitHub repo variables
# TF_STATE_BUCKET / TF_STATE_BUCKET_REGION (set by
# 01_create_terraform_state_bucket.sh), and runs `terraform init` with them
# before creating workspaces — so this script is self-sufficient and doesn't
# depend on 02_initialize_terraform.sh having been run first in the same
# session (terraform init is idempotent, safe to re-run).
#
# Can be run from anywhere (e.g. the project root) — it locates infra/
# relative to this script's own location and runs terraform there.
# Assumes this script lives in scripts/ and infra/ is a sibling folder
# (e.g. repo-root/scripts/03_create_terraform_workspaces.sh, repo-root/infra/).
# Assumes it's run from inside a clone of the GitHub repo (gh infers the
# repo from the local git remote) and that `gh auth login` has been run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"

command -v gh >/dev/null || { echo "gh CLI not found. Install: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null || { echo "Run 'gh auth login' first."; exit 1; }

REPO_FULL="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo "Reading backend info from GitHub repo variables on ${REPO_FULL}..."

BUCKET_NAME="$(gh api "repos/${REPO_FULL}/actions/variables/TF_STATE_BUCKET" --jq .value 2>/dev/null || true)"
if [ -z "${BUCKET_NAME}" ]; then
  echo "Error: repo variable TF_STATE_BUCKET not found on ${REPO_FULL}."
  echo "Run scripts/01_create_terraform_state_bucket.sh first."
  exit 1
fi

REGION="$(gh api "repos/${REPO_FULL}/actions/variables/TF_STATE_BUCKET_REGION" --jq .value 2>/dev/null || true)"
if [ -z "${REGION}" ]; then
  echo "Error: repo variable TF_STATE_BUCKET_REGION not found on ${REPO_FULL}."
  echo "Run scripts/01_create_terraform_state_bucket.sh first."
  exit 1
fi

echo "Using bucket '${BUCKET_NAME}' in region '${REGION}'."

cd "${INFRA_DIR}"

echo "Initializing Terraform in ${INFRA_DIR}..."
terraform init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="region=${REGION}"

WORKSPACES=("dev" "test" "prod")

for ws in "${WORKSPACES[@]}"; do
  if terraform workspace list | grep -qE "^\*?\s*${ws}\$"; then
    echo "Workspace '${ws}' already exists, skipping."
  else
    echo "Creating workspace '${ws}'..."
    terraform workspace new "${ws}"
  fi
done

echo
echo "Done. Current workspaces:"
terraform workspace list

echo
echo "Switching to 'dev' workspace..."
terraform workspace select dev