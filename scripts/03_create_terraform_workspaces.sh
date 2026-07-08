#!/usr/bin/env bash
set -euo pipefail

# Creates the dev, test, and prod Terraform workspaces.
#
# Can be run from anywhere (e.g. the project root) — it locates infra/
# relative to this script's own location and runs terraform there.
# Assumes this script lives in scripts/ and infra/ is a sibling folder
# (e.g. repo-root/scripts/create_workspaces.sh, repo-root/infra/).
#
# infra/ must already be initialized with `terraform init`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"

cd "${INFRA_DIR}"

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