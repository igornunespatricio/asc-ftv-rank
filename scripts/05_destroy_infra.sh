#!/usr/bin/env bash
# scripts/05_destroy_infrastructure.sh
#
# Destroys the Terraform-managed infrastructure for asc-ftv-rank.
# Reads bucket_name and region (and bucket_arn, if needed) from
# local/terraform_state_bucket_info.json rather than GitHub repo
# variables, since this is a destructive, local-only operation and
# should not depend on CI state.
#
# Usage:
#   ./scripts/05_destroy_infrastructure.sh [workspace]
#
# workspace defaults to "dev". "prod" requires typed confirmation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${PROJECT_ROOT}/infra"
BUCKET_INFO_FILE="${PROJECT_ROOT}/local/terraform_state_bucket_info.json"

WORKSPACE="${1:-dev}"

# ---- Dependency check ----------------------------------------------------
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed." >&2
  exit 1
fi

# ---- Load state bucket info ----------------------------------------------
if [[ ! -f "${BUCKET_INFO_FILE}" ]]; then
  echo "ERROR: ${BUCKET_INFO_FILE} not found. Run 01_create_terraform_state_bucket.sh first." >&2
  exit 1
fi

TF_STATE_BUCKET="$(jq -r '.bucket_name // empty' "${BUCKET_INFO_FILE}")"
TF_STATE_BUCKET_REGION="$(jq -r '.region // empty' "${BUCKET_INFO_FILE}")"
TF_STATE_BUCKET_ARN="$(jq -r '.bucket_arn // empty' "${BUCKET_INFO_FILE}")"

if [[ -z "${TF_STATE_BUCKET}" ]]; then
  echo "ERROR: bucket_name missing from ${BUCKET_INFO_FILE}." >&2
  exit 1
fi

if [[ -z "${TF_STATE_BUCKET_REGION}" ]]; then
  echo "ERROR: region missing from ${BUCKET_INFO_FILE}." >&2
  exit 1
fi

echo "Using state bucket: ${TF_STATE_BUCKET} (${TF_STATE_BUCKET_REGION})"

# ---- Guard against the default workspace ---------------------------------
if [[ "${WORKSPACE}" == "default" ]]; then
  echo "ERROR: refusing to operate on the 'default' workspace." >&2
  exit 1
fi

cd "${INFRA_DIR}"

# ---- Init backend against the target state bucket ------------------------
terraform init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${TF_STATE_BUCKET_REGION}" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_lockfile=true" \
  1>/dev/null

echo "Backend initialized."

# ---- Select workspace -----------------------------------------------------
terraform workspace select "${WORKSPACE}"
echo "Workspace: $(terraform workspace show)"

# ---- Extra guard for prod --------------------------------------------------
if [[ "${WORKSPACE}" == "prod" ]]; then
  read -r -p "You are about to DESTROY PROD. Type the workspace name to confirm: " CONFIRM
  if [[ "${CONFIRM}" != "prod" ]]; then
    echo "Confirmation failed. Aborting." >&2
    exit 1
  fi
fi

# ---- Plan destroy first, then require final confirmation ------------------
terraform plan -destroy -out=destroy.tfplan
read -r -p "Review the plan above. Type 'destroy' to apply it: " FINAL_CONFIRM
if [[ "${FINAL_CONFIRM}" != "destroy" ]]; then
  echo "Aborting. No changes applied." >&2
  rm -f destroy.tfplan
  exit 1
fi

terraform apply destroy.tfplan
rm -f destroy.tfplan

echo "Destroy complete for workspace '${WORKSPACE}'."