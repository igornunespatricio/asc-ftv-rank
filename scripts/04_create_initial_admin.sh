#!/usr/bin/env bash
set -euo pipefail

# Seeds the initial admin user directly into the Users DynamoDB table,
# bypassing the API entirely — POST /users is admin-only, so there is no
# path through the app itself to create the very first admin.
#
# Hashes the password with bcryptjs (the same library backend/auth uses),
# so the resulting password_hash verifies correctly against the auth
# Lambda's bcrypt.compare(password, user.password_hash) at login.
#
# The Users table name is read from Terraform output (users_table_name in
# infra/outputs.tf) rather than guessed or hardcoded — it depends on both
# var.project_name and the active workspace, and Terraform's output is the
# only source that can't drift from what's actually deployed.
#
# Requires infra/ to already be `terraform init`-ed against the right
# backend, and TF_WORKSPACE set to the target environment.
#
# Usage:
#   TF_WORKSPACE=dev ./scripts/04_create_initial_admin.sh

command -v aws >/dev/null || { echo "aws CLI not found."; exit 1; }
command -v terraform >/dev/null || { echo "terraform not found."; exit 1; }
command -v node >/dev/null || { echo "node not found."; exit 1; }
command -v npm >/dev/null || { echo "npm not found."; exit 1; }

if [ -z "${TF_WORKSPACE:-}" ]; then
  echo "Error: TF_WORKSPACE env var is not set."
  echo "Set it to the target environment, e.g.:"
  echo "  TF_WORKSPACE=dev ./scripts/04_create_initial_admin.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"

if [ ! -d "${INFRA_DIR}" ]; then
  echo "Error: infra/ directory not found at ${INFRA_DIR}."
  exit 1
fi

echo "Reading users_table_name from Terraform output (workspace: ${TF_WORKSPACE})..."
USERS_TABLE_NAME="$(cd "${INFRA_DIR}" && terraform output -raw users_table_name)"

if [ -z "${USERS_TABLE_NAME}" ]; then
  echo "Error: users_table_name Terraform output came back empty."
  echo "Confirm 'output \"users_table_name\"' exists in infra/outputs.tf and"
  echo "that infra/ has been applied for workspace '${TF_WORKSPACE}'."
  exit 1
fi
echo "Resolved Users table: ${USERS_TABLE_NAME}"

read -rp "Admin name: " ADMIN_NAME
read -rp "Admin email: " ADMIN_EMAIL
read -rsp "Admin password: " ADMIN_PASSWORD
echo

if [ -z "$ADMIN_NAME" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
  echo "Error: name, email, and password are all required."
  exit 1
fi

# Scratch directory for a throwaway npm install — keeps this script's
# dependencies isolated from backend/auth's own node_modules rather than
# assuming they're already installed locally.
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/package.json" << 'JSON'
{
  "name": "seed-admin",
  "private": true,
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "@aws-sdk/client-dynamodb": "^3.700.0",
    "@aws-sdk/lib-dynamodb": "^3.700.0",
    "uuid": "^9.0.1"
  }
}
JSON

echo "Installing dependencies (bcryptjs, AWS SDK) in a scratch directory..."
npm --prefix "$WORKDIR" install --silent

cat > "$WORKDIR/seed.js" << 'NODE'
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");

const [tableName, name, email, password] = process.argv.slice(2);

async function main() {
  // Cost factor 10 here is independent of what auth's bcrypt.compare needs —
  // bcrypt.compare reads the cost factor embedded in the hash itself, so
  // any valid bcrypt hash verifies correctly regardless of what generated it.
  const password_hash = await bcrypt.hash(password, 10);

  const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

  await ddb.send(
    new PutCommand({
      TableName: tableName,
      Item: {
        id: uuidv4(),
        name,
        email,
        status: true,
        is_admin: true,
        password_hash,
      },
      // Guards only against an (essentially impossible) UUID collision —
      // NOT against a duplicate email, since EmailIndex is a GSI, not a
      // uniqueness constraint. Check the table yourself first if unsure
      // whether this email already has a record.
      ConditionExpression: "attribute_not_exists(id)",
    })
  );

  console.log(`Created admin user "${name}" <${email}> in ${tableName}.`);
}

main().catch((err) => {
  console.error("Failed to create admin user:", err);
  process.exit(1);
});
NODE

node "$WORKDIR/seed.js" "$USERS_TABLE_NAME" "$ADMIN_NAME" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"