#!/usr/bin/env bash
set -euo pipefail

# End-to-end authorizer smoke test. Crafts JWTs directly (signed with the
# real deployed JWT secret, pulled from SSM) rather than going through
# POST /auth/login — this lets us exercise cases auth would never itself
# produce (expired, malformed, non-admin) without faking time or seeding
# fake Users rows.
#
# Cases covered, all against GET /users (an admin-only route):
#   1. No Authorization header          -> expect denial
#   2. Malformed token                  -> expect denial
#   3. Valid signature, is_admin=false  -> expect denial
#   4. Valid signature, expired         -> expect denial
#   5. Valid signature, is_admin=true   -> expect success
#
# Requires: aws CLI, curl, jq, node (with backend/authorizer/node_modules
# already installed locally — reuses its jsonwebtoken to sign test tokens).
#
# Usage:
#   ./test_authorizer.sh <dev|test|prod>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"
AUTHORIZER_DIR="${REPO_ROOT}/backend/authorizer"

PROJECT_NAME="footvolley"

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

if [[ ! -d "${AUTHORIZER_DIR}/node_modules/jsonwebtoken" ]]; then
  echo "Error: ${AUTHORIZER_DIR}/node_modules/jsonwebtoken not found."
  echo "Run 'npm install' in backend/authorizer first (needed to sign test tokens)."
  exit 1
fi

echo "==> Fetching API invoke URL for workspace '${ENVIRONMENT}'..."
API_URL="$(TF_WORKSPACE="${ENVIRONMENT}" terraform -chdir="${INFRA_DIR}" output -raw api_invoke_url)"
if [[ -z "${API_URL}" ]]; then
  echo "Error: could not read api_invoke_url output from Terraform."
  exit 1
fi
echo "API URL: ${API_URL}"

echo "==> Fetching JWT secret from SSM (/${PROJECT_NAME}/${ENVIRONMENT}/jwt-secret)..."
JWT_SECRET="$(aws ssm get-parameter \
  --name "/${PROJECT_NAME}/${ENVIRONMENT}/jwt-secret" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)"

if [[ -z "${JWT_SECRET}" || "${JWT_SECRET}" == "None" ]]; then
  echo "Error: could not fetch JWT secret from SSM."
  exit 1
fi

sign_token() {
  # Usage: sign_token <is_admin: true|false> <expires_in: e.g. "8h" or "-10s">
  node -e "
    const jwt = require('${AUTHORIZER_DIR}/node_modules/jsonwebtoken');
    console.log(jwt.sign(
      { sub: 'test-user', email: 'test@example.com', is_admin: process.argv[1] === 'true' },
      process.argv[3],
      { expiresIn: process.argv[2] }
    ));
  " "$1" "$2" "${JWT_SECRET}"
}

FAILURES=0

check_status() {
  # Usage: check_status <description> <actual_status> <expected_status_regex>
  local description="$1"
  local actual="$2"
  local expected_regex="$3"

  if [[ "${actual}" =~ ${expected_regex} ]]; then
    echo "PASS: ${description} (status ${actual})"
  else
    echo "FAIL: ${description} — got status ${actual}, expected match for '${expected_regex}'"
    FAILURES=$((FAILURES + 1))
  fi
}

echo
echo "==> Case 1: no Authorization header..."
STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users")"
check_status "request with no token is denied" "${STATUS}" "^(401|403)$"

echo
echo "==> Case 2: malformed token..."
STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users" \
  -H "Authorization: Bearer not-a-real-jwt")"
check_status "request with malformed token is denied" "${STATUS}" "^(401|403)$"

echo
echo "==> Case 3: valid signature, non-admin..."
NON_ADMIN_TOKEN="$(sign_token false 8h)"
STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users" \
  -H "Authorization: Bearer ${NON_ADMIN_TOKEN}")"
check_status "request with non-admin token is denied" "${STATUS}" "^(401|403)$"

echo
echo "==> Case 4: valid signature, expired..."
EXPIRED_TOKEN="$(sign_token true -- -10s)"
# Note: "-10s" needs the -- separator above so node's arg parsing doesn't
# treat it as a flag.
STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users" \
  -H "Authorization: Bearer ${EXPIRED_TOKEN}")"
check_status "request with expired token is denied" "${STATUS}" "^(401|403)$"

echo
echo "==> Case 5: valid signature, admin, not expired..."
VALID_TOKEN="$(sign_token true 8h)"
STATUS="$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/users" \
  -H "Authorization: Bearer ${VALID_TOKEN}")"
check_status "request with valid admin token succeeds" "${STATUS}" "^200$"

echo
if [[ ${FAILURES} -gt 0 ]]; then
  echo "${FAILURES} case(s) failed."
  exit 1
fi

echo "All authorizer checks passed for environment '${ENVIRONMENT}'."