#!/usr/bin/env bash
set -euo pipefail

# End-to-end matches Lambda smoke test:
#   1. Seeds a temporary admin (for auth) and four temporary players directly
#      into DynamoDB (match creation needs four distinct real player IDs)
#   2. POST /matches -> creates a match: Team 1 (A1+A2) beats Team 2 (B1+B2)
#   3. GET /matches (public, date-scoped, bet filter) -> confirms match
#      appears with enriched player names
#   4. GET /ranking (public, date-scoped) -> confirms computed stats match
#      expected win/loss/points values for all four players
#   5. PUT /matches/:id -> updates the score, confirms it persists and
#      ranking recalculates accordingly
#   6. DELETE /matches/:id -> confirms deletion
#   7. Cleans up admin, all four players, and the match (if still present),
#      regardless of pass/fail
#
# Requires: aws CLI, curl, jq, node (with backend/auth/node_modules already
# installed locally — reuses its bcryptjs to hash the seed admin's password).
#
# Usage:
#   ./test_matches.sh <dev|test|prod>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INFRA_DIR="${REPO_ROOT}/infra"
AUTH_DIR="${REPO_ROOT}/backend/auth"

PROJECT_NAME="footvolley"
TEST_ADMIN_EMAIL="e2e-test-admin-matches@example.com"
TEST_ADMIN_PASSWORD="e2e-test-password-$(date +%s)"
TEST_ADMIN_ID="e2e-test-admin-matches-$(date +%s)"
PLAYER_A1_ID="e2e-test-player-a1-$(date +%s)"
PLAYER_A2_ID="e2e-test-player-a2-$(date +%s)"
PLAYER_B1_ID="e2e-test-player-b1-$(date +%s)"
PLAYER_B2_ID="e2e-test-player-b2-$(date +%s)"
MATCH_DATE="$(date -u +%Y-%m-%d)"
TEST_MATCH_ID=""  # set once created via the API

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
MATCHES_TABLE="${PROJECT_NAME}-${ENVIRONMENT}-matches"

echo "==> Fetching API invoke URL for workspace '${ENVIRONMENT}'..."
API_URL="$(TF_WORKSPACE="${ENVIRONMENT}" terraform -chdir="${INFRA_DIR}" output -raw api_invoke_url)"
if [[ -z "${API_URL}" ]]; then
  echo "Error: could not read api_invoke_url output from Terraform."
  exit 1
fi
echo "API URL: ${API_URL}"

cleanup() {
  echo "==> Cleaning up temporary data..."
  if [[ -n "${TEST_MATCH_ID}" ]]; then
    aws dynamodb delete-item \
      --table-name "${MATCHES_TABLE}" \
      --key "{\"id\": {\"S\": \"${TEST_MATCH_ID}\"}}" \
      >/dev/null 2>&1 || echo "  (match cleanup failed or already gone — may already be deleted by the test itself)"
  fi
  for id in "${TEST_ADMIN_ID}" "${PLAYER_A1_ID}" "${PLAYER_A2_ID}" "${PLAYER_B1_ID}" "${PLAYER_B2_ID}"; do
    aws dynamodb delete-item --table-name "${USERS_TABLE}" \
      --key "{\"id\": {\"S\": \"${id}\"}}" >/dev/null 2>&1 || true
  done
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

echo "==> Seeding temporary admin and four players into ${USERS_TABLE}..."
aws dynamodb put-item --table-name "${USERS_TABLE}" --item "{
  \"id\": {\"S\": \"${TEST_ADMIN_ID}\"},
  \"name\": {\"S\": \"E2E Test Admin (matches)\"},
  \"email\": {\"S\": \"${TEST_ADMIN_EMAIL}\"},
  \"password_hash\": {\"S\": \"${PASSWORD_HASH}\"},
  \"is_admin\": {\"BOOL\": true},
  \"status\": {\"BOOL\": true}
}"
aws dynamodb put-item --table-name "${USERS_TABLE}" --item "{
  \"id\": {\"S\": \"${PLAYER_A1_ID}\"},
  \"name\": {\"S\": \"E2E Player A1\"},
  \"is_admin\": {\"BOOL\": false},
  \"status\": {\"BOOL\": true}
}"
aws dynamodb put-item --table-name "${USERS_TABLE}" --item "{
  \"id\": {\"S\": \"${PLAYER_A2_ID}\"},
  \"name\": {\"S\": \"E2E Player A2\"},
  \"is_admin\": {\"BOOL\": false},
  \"status\": {\"BOOL\": true}
}"
aws dynamodb put-item --table-name "${USERS_TABLE}" --item "{
  \"id\": {\"S\": \"${PLAYER_B1_ID}\"},
  \"name\": {\"S\": \"E2E Player B1\"},
  \"is_admin\": {\"BOOL\": false},
  \"status\": {\"BOOL\": true}
}"
aws dynamodb put-item --table-name "${USERS_TABLE}" --item "{
  \"id\": {\"S\": \"${PLAYER_B2_ID}\"},
  \"name\": {\"S\": \"E2E Player B2\"},
  \"is_admin\": {\"BOOL\": false},
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

# Team 1 (A1+A2) vs Team 2 (B1+B2), Team 1 wins 21-15, marked as a bet match.
echo
echo "==> POST /matches (create a match: Team A beats Team B, 21-15, has_bet)..."
CREATE_RESPONSE="$(curl -s -w "\n%{http_code}" -X POST "${API_URL}/matches" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"match_date\": \"${MATCH_DATE}\",
    \"player1_team1\": \"${PLAYER_A1_ID}\",
    \"player2_team1\": \"${PLAYER_A2_ID}\",
    \"player1_team2\": \"${PLAYER_B1_ID}\",
    \"player2_team2\": \"${PLAYER_B2_ID}\",
    \"score_team1\": 21,
    \"score_team2\": 15,
    \"has_bet\": true
  }")"

CREATE_STATUS="$(echo "${CREATE_RESPONSE}" | tail -n1)"
CREATE_BODY="$(echo "${CREATE_RESPONSE}" | sed '$d')"
check "POST /matches returns 201" "$([[ "${CREATE_STATUS}" == "201" ]]; echo $?)"

TEST_MATCH_ID="$(echo "${CREATE_BODY}" | jq -r '.match.id // empty')"
if [[ -z "${TEST_MATCH_ID}" ]]; then
  echo "FAIL: no match id in create response — aborting remaining checks."
  echo "Body: ${CREATE_BODY}"
  exit 1
fi

echo
echo "==> GET /matches?start=&end=&bet=true (confirm match appears, names enriched)..."
LIST_BODY="$(curl -s "${API_URL}/matches?start=${MATCH_DATE}&end=${MATCH_DATE}&bet=true")"
FOUND_MATCH="$(echo "${LIST_BODY}" | jq --arg id "${TEST_MATCH_ID}" '[.matches[] | select(.id == $id)] | length')"
check "created match appears in GET /matches" "$([[ "${FOUND_MATCH}" == "1" ]]; echo $?)"

PLAYER_A1_NAME="$(echo "${LIST_BODY}" | jq -r --arg id "${TEST_MATCH_ID}" '.matches[] | select(.id == $id) | .player1_team1_name')"
check "player names are enriched in match response" "$([[ "${PLAYER_A1_NAME}" == "E2E Player A1" ]]; echo $?)"

echo
echo "==> GET /ranking?start=&end= (confirm computed stats for all four players)..."
RANKING_BODY="$(curl -s "${API_URL}/ranking?start=${MATCH_DATE}&end=${MATCH_DATE}")"

A1_ROW="$(echo "${RANKING_BODY}" | jq --arg id "${PLAYER_A1_ID}" '.ranking[] | select(.player_id == $id)')"
A2_ROW="$(echo "${RANKING_BODY}" | jq --arg id "${PLAYER_A2_ID}" '.ranking[] | select(.player_id == $id)')"
B1_ROW="$(echo "${RANKING_BODY}" | jq --arg id "${PLAYER_B1_ID}" '.ranking[] | select(.player_id == $id)')"
B2_ROW="$(echo "${RANKING_BODY}" | jq --arg id "${PLAYER_B2_ID}" '.ranking[] | select(.player_id == $id)')"

check "A1 has 1 win, 0 losses" "$([[ "$(echo "${A1_ROW}" | jq '.wins')" == "1" && "$(echo "${A1_ROW}" | jq '.losses')" == "0" ]]; echo $?)"
check "A2 has 1 win, 0 losses" "$([[ "$(echo "${A2_ROW}" | jq '.wins')" == "1" && "$(echo "${A2_ROW}" | jq '.losses')" == "0" ]]; echo $?)"
check "A1 has 3 points" "$([[ "$(echo "${A1_ROW}" | jq '.points')" == "3" ]]; echo $?)"
check "A1 points_scored=21, points_against=15" "$([[ "$(echo "${A1_ROW}" | jq '.points_scored')" == "21" && "$(echo "${A1_ROW}" | jq '.points_against')" == "15" ]]; echo $?)"
check "B1 has 0 wins, 1 loss, 0 points" "$([[ "$(echo "${B1_ROW}" | jq '.wins')" == "0" && "$(echo "${B1_ROW}" | jq '.losses')" == "1" && "$(echo "${B1_ROW}" | jq '.points')" == "0" ]]; echo $?)"
check "B2 points_scored=15, points_against=21" "$([[ "$(echo "${B2_ROW}" | jq '.points_scored')" == "15" && "$(echo "${B2_ROW}" | jq '.points_against')" == "21" ]]; echo $?)"
check "A1 bet_wins=1 (has_bet match)" "$([[ "$(echo "${A1_ROW}" | jq '.bet_wins')" == "1" ]]; echo $?)"
check "B1 bet_matches=1, bet_wins=0" "$([[ "$(echo "${B1_ROW}" | jq '.bet_matches')" == "1" && "$(echo "${B1_ROW}" | jq '.bet_wins')" == "0" ]]; echo $?)"

echo
echo "==> PUT /matches/:id (flip the score: Team B now wins 10-21)..."
UPDATE_RESPONSE="$(curl -s -w "\n%{http_code}" -X PUT "${API_URL}/matches/${TEST_MATCH_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"score_team1": 10, "score_team2": 21}')"

UPDATE_STATUS="$(echo "${UPDATE_RESPONSE}" | tail -n1)"
UPDATE_BODY="$(echo "${UPDATE_RESPONSE}" | sed '$d')"
check "PUT /matches/:id returns 200" "$([[ "${UPDATE_STATUS}" == "200" ]]; echo $?)"

NEW_SCORE_TEAM2="$(echo "${UPDATE_BODY}" | jq '.match.score_team2')"
check "updated score persisted (score_team2 = 21)" "$([[ "${NEW_SCORE_TEAM2}" == "21" ]]; echo $?)"

echo
echo "==> GET /ranking again (confirm win flips to Team B after update)..."
RANKING_AFTER="$(curl -s "${API_URL}/ranking?start=${MATCH_DATE}&end=${MATCH_DATE}")"
B1_ROW_AFTER="$(echo "${RANKING_AFTER}" | jq --arg id "${PLAYER_B1_ID}" '.ranking[] | select(.player_id == $id)')"
B2_ROW_AFTER="$(echo "${RANKING_AFTER}" | jq --arg id "${PLAYER_B2_ID}" '.ranking[] | select(.player_id == $id)')"
check "B1 now shows 1 win after score update" "$([[ "$(echo "${B1_ROW_AFTER}" | jq '.wins')" == "1" ]]; echo $?)"
check "B2 now shows 1 win after score update" "$([[ "$(echo "${B2_ROW_AFTER}" | jq '.wins')" == "1" ]]; echo $?)"

echo
echo "==> DELETE /matches/:id..."
DELETE_STATUS="$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}/matches/${TEST_MATCH_ID}" \
  -H "Authorization: Bearer ${TOKEN}")"
check "DELETE /matches/:id returns 204" "$([[ "${DELETE_STATUS}" == "204" ]]; echo $?)"

echo
echo "==> GET /matches (confirm deletion)..."
LIST_AFTER_DELETE="$(curl -s "${API_URL}/matches?start=${MATCH_DATE}&end=${MATCH_DATE}")"
FOUND_AFTER_DELETE="$(echo "${LIST_AFTER_DELETE}" | jq --arg id "${TEST_MATCH_ID}" '[.matches[] | select(.id == $id)] | length')"
check "deleted match no longer appears in GET /matches" "$([[ "${FOUND_AFTER_DELETE}" == "0" ]]; echo $?)"

echo
if [[ ${FAILURES} -gt 0 ]]; then
  echo "${FAILURES} case(s) failed."
  exit 1
fi

echo "All matches checks passed for environment '${ENVIRONMENT}'."