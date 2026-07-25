#!/usr/bin/env bash
set -euo pipefail

# End-to-end users Lambda smoke test:
#   1. Seeds a temporary admin user directly into DynamoDB, logs in for a token
#      (same approach as test_auth.sh — needed since there's no admin yet to
#      authenticate through the API itself)
#   2. POST /users -> creates a temporary viewer user, checks no password_hash leaks
#   3. GET /users (admin) -> confirms the new user appears in the list
#   4. PUT /users/:id -> deactivates the user, confirms status change persists
#   5. GET /players/active (public, no token) -> confirms deactivated user is excluded
#   6. DELETE /users/:id -> confirms deletion
#   7. GET /users (admin) -> confirms the user no longer appears
#   8. Cleans up both temporary users, regardless of pass/fail
#
# Requires: aws CLI, curl, jq, node (with backend/auth/node_modules already
# installed locally — reuses its bcryptjs to hash the seed admin's password).
#
# Usage:
#   ./test_users.sh <dev|test|prod>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"
AUTH_DIR="${REPO_ROOT}/backend/auth"

PROJECT_NAME="footvolley"
TEST_ADMIN_EMAIL="e2e-test-admin-users@example.com"
TEST_ADMIN_PASSWORD="e2e-test-password-$(date +%s)"
TEST_ADMIN_ID="e2e-test-admin-$(date +%s)"

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
  echo "Run 'npm install' in backend/auth first (needed to hash the seed admin's password)."
  exit 1
fi

USERS_TABLE="${PROJECT_NAME}-${ENVIRONMENT}-users"
TEST_VIEWER_ID=""  # set once created via the API

echo "==> Fetching API invoke URL for workspace '${ENVIRONMENT}'..."
API_URL="$(TF_WORKSPACE="${ENVIRONMENT}" terraform -chdir="${INFRA_DIR}" output -raw api_invoke_url)"
if [[ -z "${API_URL}" ]]; then
  echo "Error: could not read api_invoke_url output from Terraform."
  exit 1
fi
echo "API URL: ${API_URL}"

cleanup() {
  echo "==> Cleaning up temporary users..."
  aws dynamodb delete-item \
    --table-name "${USERS_TABLE}" \
    --key "{\"id\": {\"S\": \"${TEST_ADMIN_ID}\"}}" \
    >/dev/null 2>&1 || echo "  (admin cleanup failed or already gone)"

  if [[ -n "${TEST_VIEWER_ID}" ]]; then
    aws dynamodb delete-item \
      --table-name "${USERS_TABLE}" \
      --key "{\"id\": {\"S\": \"${TEST_VIEWER_ID}\"}}" \
      >/dev/null 2>&1 || echo "  (viewer cleanup failed or already gone — may already be deleted by the test itself)"
  fi
}
trap cleanup EXIT

FAILURES=0

check() {
  # Usage: check <description> <condition: 0 = pass>
  local description="$1"
  local condition="$2"
  if [[ "${condition}" -eq 0 ]]; then
    echo "PASS: ${description}"
  else
    echo "FAIL: ${description}"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "==> Hashing seed admin password..."
PASSWORD_HASH="$(node -e "
  const bcrypt = require('${AUTH_DIR}/node_modules/bcryptjs');
  console.log(bcrypt.hashSync(process.argv[1], 10));
" "${TEST_ADMIN_PASSWORD}")"

echo "==> Seeding temporary admin user into ${USERS_TABLE}..."
aws dynamodb put-item \
  --table-name "${USERS_TABLE}" \
  --item "{
    \"id\": {\"S\": \"${TEST_ADMIN_ID}\"},
    \"name\": {\"S\": \"E2E Test Admin (users)\"},
    \"email\": {\"S\": \"${TEST_ADMIN_EMAIL}\"},
    \"password_hash\": {\"S\": \"${PASSWORD_HASH}\"},
    \"is_admin\": {\"BOOL\": true},
    \"status\": {\"BOOL\": true}
  }"

echo "==> Logging in as seed admin..."
LOGIN_BODY="$(curl -s -X POST "${API_URL}/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"${TEST_ADMIN_EMAIL}\", \"password\": \"${TEST_ADMIN_PASSWORD}\"}")"
TOKEN="$(echo "${LOGIN_BODY}" | jq -r '.token')"

if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "FAIL: could not log in as seed admin — aborting."
  echo "Body: ${LOGIN_BODY}"
  exit 1
fi
echo "  logged in"

echo
echo "==> POST /users (create a temporary viewer)..."
CREATE_RESPONSE="$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "E2E Test Viewer", "is_admin": false, "status": true}')"

CREATE_STATUS="$(echo "${CREATE_RESPONSE}" | tail -n1)"
CREATE_BODY="$(echo "${CREATE_RESPONSE}" | sed '$d')"

check "POST /users returns 201" "$([[ "${CREATE_STATUS}" == "201" ]]; echo $?)"

TEST_VIEWER_ID="$(echo "${CREATE_BODY}" | jq -r '.user.id // empty')"
if [[ -z "${TEST_VIEWER_ID}" ]]; then
  echo "FAIL: no user id in create response — aborting remaining checks."
  echo "Body: ${CREATE_BODY}"
  exit 1
fi

HAS_PASSWORD_HASH="$(echo "${CREATE_BODY}" | jq 'has("password_hash") or (.user | has("password_hash"))')"
check "created user response has no password_hash field" "$([[ "${HAS_PASSWORD_HASH}" == "false" ]]; echo $?)"

echo
echo "==> GET /users (confirm new user appears in list)..."
LIST_BODY="$(curl -s "${API_URL}/users" -H "Authorization: Bearer ${TOKEN}")"
FOUND_IN_LIST="$(echo "${LIST_BODY}" | jq --arg id "${TEST_VIEWER_ID}" '[.users[] | select(.id == $id)] | length')"
check "created user appears in GET /users" "$([[ "${FOUND_IN_LIST}" == "1" ]]; echo $?)"

echo
echo "==> PUT /users/:id (deactivate the viewer)..."
UPDATE_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${API_URL}/users/${TEST_VIEWER_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"status": false}')"
check "PUT /users/:id returns 200" "$([[ "${UPDATE_STATUS}" == "200" ]]; echo $?)"

echo
echo "==> GET /players/active (public, no token — confirm deactivated user excluded)..."
ACTIVE_BODY="$(curl -s "${API_URL}/players/active")"
FOUND_IN_ACTIVE="$(echo "${ACTIVE_BODY}" | jq --arg id "${TEST_VIEWER_ID}" '[.players[] | select(.id == $id)] | length')"
check "deactivated user is excluded from /players/active" "$([[ "${FOUND_IN_ACTIVE}" == "0" ]]; echo $?)"

echo
echo "==> DELETE /users/:id..."
DELETE_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}/users/${TEST_VIEWER_ID}" \
  -H "Authorization: Bearer ${TOKEN}")"
check "DELETE /users/:id returns 204" "$([[ "${DELETE_STATUS}" == "204" ]]; echo $?)"

echo
echo "==> GET /users (confirm deletion)..."
LIST_AFTER_DELETE="$(curl -s "${API_URL}/users" -H "Authorization: Bearer ${TOKEN}")"
FOUND_AFTER_DELETE="$(echo "${LIST_AFTER_DELETE}" | jq --arg id "${TEST_VIEWER_ID}" '[.users[] | select(.id == $id)] | length')"
check "deleted user no longer appears in GET /users" "$([[ "${FOUND_AFTER_DELETE}" == "0" ]]; echo $?)"

echo
if [[ ${FAILURES} -gt 0 ]]; then
  echo "${FAILURES} case(s) failed."
  exit 1
fi

echo "All users checks passed for environment '${ENVIRONMENT}'."