#!/usr/bin/env bash
set -uo pipefail
# Note: NOT using -e here deliberately — we want to run every test file even
# if one fails, then report a full summary. Each individual test script still
# uses `set -euo pipefail` internally for its own step-by-step correctness.

# Runs every tests/e2e/test_*.sh script against a given environment and
# reports a pass/fail summary. Add a new smoke test by dropping a
# `test_<name>.sh` file in this directory — no changes needed here or in the
# GitHub Actions workflow to pick it up.
#
# Usage:
#   ./run_all.sh <dev|test|prod>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVIRONMENT="${1:-}"
if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev|test|prod>"
  exit 1
fi
case "${ENVIRONMENT}" in
  dev|test|prod) ;;
  *) echo "Error: environment must be one of dev, test, prod — got '${ENVIRONMENT}'."; exit 1 ;;
esac

shopt -s nullglob
TEST_FILES=("${SCRIPT_DIR}"/test_*.sh)
shopt -u nullglob

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "No test files found matching tests/e2e/test_*.sh — nothing to run."
  exit 0
fi

echo "Found ${#TEST_FILES[@]} e2e test file(s) for environment '${ENVIRONMENT}':"
for f in "${TEST_FILES[@]}"; do
  echo "  - $(basename "${f}")"
done
echo

PASSED=()
FAILED=()

for test_file in "${TEST_FILES[@]}"; do
  test_name="$(basename "${test_file}")"
  echo "=============================================="
  echo "Running ${test_name}..."
  echo "=============================================="

  chmod +x "${test_file}"
  if "${test_file}" "${ENVIRONMENT}"; then
    PASSED+=("${test_name}")
  else
    FAILED+=("${test_name}")
  fi
  echo
done

echo "=============================================="
echo "Summary — environment: ${ENVIRONMENT}"
echo "=============================================="
echo "Passed: ${#PASSED[@]}"
for t in "${PASSED[@]:-}"; do
  [[ -n "${t}" ]] && echo "  ✓ ${t}"
done

echo "Failed: ${#FAILED[@]}"
for t in "${FAILED[@]:-}"; do
  [[ -n "${t}" ]] && echo "  ✗ ${t}"
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  exit 1
fi

exit 0