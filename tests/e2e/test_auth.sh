#!/usr/bin/env bash
set -euo pipefail

# End-to-end auth smoke test:
#   1. Seeds a temporary admin user into the Users table (bcrypt-hashed password)
#   2. Calls POST /auth/login and extracts the JWT
#   3. Calls an admin-only route (GET /users) WITH the token -> expect success
#   4. Calls the same route WITHOUT a token -> expect denial (401/403)
#   5. Deletes the temporary user, regardless of pass/fail
#
# Verifies the auth Lambda (issues tokens) and the authorizer Lambda (verifies
# them) are wired correctly end-to-end against a real deployed environment.
#
# Requires: aws CLI, curl, jq, node (with backend/auth/node_modules already
# installed locally — reuses its bcryptjs to hash the test password).
#
# Usage:
#   ./06_test_auth_e2e.sh <dev|test|prod>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"
AUTH_DIR="${REPO_ROOT}/backend/auth"

PROJECT_NAME="footvolley"
TEST_EMAIL="e2e-test-admin@example.com"
TEST_PASSWORD="e2e-test-password-$(date +%s)"
TEST_USER_ID="e2e-test-$(date +%s)"

command -v aws >/dev/null || { echo "aws CLI not found."; exit 1; }
command -v curl >/dev/null || { echo "curl not found."; exit 1; }
command -v jq >/dev/null || { echo "jq not found."; exit 1; }
command -v node >/dev/null || { echo "node not found."; exit 1; }

ENVIRONMENT="${1:-}"
if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev|test|prod>"
  exit 1
fi
case "${ENVIRONMENT}" in
  dev|test|prod) ;;
  *) echo "Error: environment must be one of dev, test, prod — got '${ENVIRONMENT}'."; exit 1 ;;
esac

if [[ ! -d "${AUTH_DIR}/node_modules/bcryptjs" ]]; then
  echo "Error: ${AUTH_DIR}/node_modules/bcryptjs not found."
  echo "Run 'npm install' in backend/auth first (needed to hash the test password)."
  exit 1
fi

USERS_TABLE="${PROJECT_NAME}-${ENVIRONMENT}-users"

echo "==> Fetching API invoke URL for workspace '${ENVIRONMENT}'..."
API_URL="$(TF_WORKSPACE="${ENVIRONMENT}" terraform -chdir="${INFRA_DIR}" output -raw api_invoke_url)"
if [[ -z "${API_URL}" ]]; then
  echo "Error: could not read api_invoke_url output from Terraform."
  exit 1
fi
echo "API URL: ${API_URL}"

cleanup() {
  echo "==> Cleaning up test user..."
  aws dynamodb delete-item \
    --table-name "${USERS_TABLE}" \
    --key "{\"id\": {\"S\": \"${TEST_USER_ID}\"}}" \
    >/dev/null 2>&1 || echo "  (cleanup delete failed or already gone — check manually if needed)"
}
trap cleanup EXIT

echo "==> Hashing test password..."
PASSWORD_HASH="$(node -e "
  const bcrypt = require('${AUTH_DIR}/node_modules/bcryptjs');
  console.log(bcrypt.hashSync(process.argv[1], 10));
" "${TEST_PASSWORD}")"

echo "==> Seeding temporary admin user into ${USERS_TABLE}..."
aws dynamodb put-item \
  --table-name "${USERS_TABLE}" \
  --item "{
    \"id\": {\"S\": \"${TEST_USER_ID}\"},
    \"name\": {\"S\": \"E2E Test Admin\"},
    \"email\": {\"S\": \"${TEST_EMAIL}\"},
    \"password_hash\": {\"S\": \"${PASSWORD_HASH}\"},
    \"is_admin\": {\"BOOL\": true},
    \"status\": {\"BOOL\": true}
  }"

echo "==> Calling POST /auth/login..."
LOGIN_RESPONSE="$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"${TEST_EMAIL}\", \"password\": \"${TEST_PASSWORD}\"}")"

LOGIN_STATUS="$(echo "${LOGIN_RESPONSE}" | tail -n1)"
LOGIN_BODY="$(echo "${LOGIN_RESPONSE}" | sed '$d')"

if [[ "${LOGIN_STATUS}" != "200" ]]; then
  echo "FAIL: login returned status ${LOGIN_STATUS}"
  echo "Body: ${LOGIN_BODY}"
  exit 1
fi

TOKEN="$(echo "${LOGIN_BODY}" | jq -r '.token')"
if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "FAIL: login succeeded but no token in response"
  echo "Body: ${LOGIN_BODY}"
  exit 1
fi
echo "PASS: login succeeded, token received"

echo "==> Calling GET /users WITH token (expect success)..."
AUTHED_STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users" \
  -H "Authorization: Bearer ${TOKEN}")"

if [[ "${AUTHED_STATUS}" != "200" ]]; then
  echo "FAIL: authorized request to /users returned ${AUTHED_STATUS}, expected 200"
  exit 1
fi
echo "PASS: authorized request succeeded (${AUTHED_STATUS})"

echo "==> Calling GET /users WITHOUT token (expect denial)..."
UNAUTHED_STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users")"

if [[ "${UNAUTHED_STATUS}" != "401" && "${UNAUTHED_STATUS}" != "403" ]]; then
  echo "FAIL: unauthenticated request to /users returned ${UNAUTHED_STATUS}, expected 401/403"
  exit 1
fi
echo "PASS: unauthenticated request correctly denied (${UNAUTHED_STATUS})"

echo
echo "All checks passed for environment '${ENVIRONMENT}'."