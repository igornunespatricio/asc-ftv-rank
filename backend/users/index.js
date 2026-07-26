const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
  UpdateCommand,
  DeleteCommand,
  ScanCommand,
  QueryCommand,
} = require("@aws-sdk/lib-dynamodb");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
const { normalizePath } = require("shared");

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);

const USERS_TABLE_NAME = process.env.USERS_TABLE_NAME;
const BCRYPT_ROUNDS = 10;

function response(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

// Never let password_hash leak into any response body.
function sanitizeUser(user) {
  if (!user) return user;
  const { password_hash, ...safe } = user;
  return safe;
}

async function emailExists(email, excludeId) {
  const result = await ddb.send(
    new QueryCommand({
      TableName: USERS_TABLE_NAME,
      IndexName: "EmailIndex",
      KeyConditionExpression: "email = :email",
      ExpressionAttributeValues: { ":email": email },
    }),
  );
  const match = (result.Items || []).find((u) => u.id !== excludeId);
  return Boolean(match);
}

// -----------------------------------------------------------------------------
// GET /players/active — public. Only status = true, name + id only, no
// admin-only fields exposed (this route has no authorizer per api_gateway.tf).
// -----------------------------------------------------------------------------
async function listActivePlayers() {
  const result = await ddb.send(
    new ScanCommand({
      TableName: USERS_TABLE_NAME,
      FilterExpression: "#status = :active",
      ExpressionAttributeNames: { "#status": "status" },
      ExpressionAttributeValues: { ":active": true },
    }),
  );

  const players = (result.Items || []).map((u) => ({
    id: u.id,
    name: u.name,
  }));

  return response(200, { players });
}

// -----------------------------------------------------------------------------
// GET /users — admin-only. Full list, password_hash stripped.
// -----------------------------------------------------------------------------
async function listUsers() {
  const result = await ddb.send(
    new ScanCommand({ TableName: USERS_TABLE_NAME }),
  );
  const users = (result.Items || []).map(sanitizeUser);
  return response(200, { users });
}

// -----------------------------------------------------------------------------
// POST /users — admin-only. Creates a viewer or admin user.
// Admin users require email + password (hashed here); viewers don't need
// either, since only admins log in (per CLAUDE.md access rules).
// -----------------------------------------------------------------------------
async function createUser(body) {
  const { name, is_admin, email, password, status } = body;

  if (!name || typeof name !== "string") {
    return response(400, { error: "name is required" });
  }

  const isAdmin = Boolean(is_admin);

  if (isAdmin) {
    if (!email || !password) {
      return response(400, {
        error: "email and password are required for admin users",
      });
    }
    if (await emailExists(email)) {
      return response(409, { error: "A user with this email already exists" });
    }
  }

  const user = {
    id: uuidv4(),
    name,
    status: status === undefined ? true : Boolean(status),
    is_admin: isAdmin,
  };

  if (isAdmin) {
    user.email = email;
    user.password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
  }

  await ddb.send(
    new PutCommand({
      TableName: USERS_TABLE_NAME,
      Item: user,
      ConditionExpression: "attribute_not_exists(id)",
    }),
  );

  return response(201, { user: sanitizeUser(user) });
}

// -----------------------------------------------------------------------------
// PUT /users/:id — admin-only. Partial update. Password only changes if a
// new one is supplied; email uniqueness re-checked if email is changing.
// -----------------------------------------------------------------------------
async function updateUser(id, body) {
  const existing = await ddb.send(
    new GetCommand({ TableName: USERS_TABLE_NAME, Key: { id } }),
  );

  if (!existing.Item) {
    return response(404, { error: "User not found" });
  }

  const { name, is_admin, email, password, status } = body;
  const isAdmin =
    is_admin === undefined ? existing.Item.is_admin : Boolean(is_admin);

  if (isAdmin && email && email !== existing.Item.email) {
    if (await emailExists(email, id)) {
      return response(409, { error: "A user with this email already exists" });
    }
  }

  if (isAdmin && (email || password) && !(email || existing.Item.email)) {
    return response(400, { error: "email is required for admin users" });
  }

  const updateFields = {
    name: name !== undefined ? name : existing.Item.name,
    status: status !== undefined ? Boolean(status) : existing.Item.status,
    is_admin: isAdmin,
  };

  if (isAdmin) {
    updateFields.email = email !== undefined ? email : existing.Item.email;
    updateFields.password_hash =
      password !== undefined
        ? await bcrypt.hash(password, BCRYPT_ROUNDS)
        : existing.Item.password_hash;
  }

  const names = {};
  const values = {};
  const setClauses = [];
  for (const [key, value] of Object.entries(updateFields)) {
    if (value === undefined) continue;
    const nameKey = `#${key}`;
    const valueKey = `:${key}`;
    names[nameKey] = key;
    values[valueKey] = value;
    setClauses.push(`${nameKey} = ${valueKey}`);
  }

  const result = await ddb.send(
    new UpdateCommand({
      TableName: USERS_TABLE_NAME,
      Key: { id },
      UpdateExpression: `SET ${setClauses.join(", ")}`,
      ExpressionAttributeNames: names,
      ExpressionAttributeValues: values,
      ReturnValues: "ALL_NEW",
    }),
  );

  return response(200, { user: sanitizeUser(result.Attributes) });
}

// -----------------------------------------------------------------------------
// DELETE /users/:id — admin-only.
// -----------------------------------------------------------------------------
async function deleteUser(id) {
  const existing = await ddb.send(
    new GetCommand({ TableName: USERS_TABLE_NAME, Key: { id } }),
  );

  if (!existing.Item) {
    return response(404, { error: "User not found" });
  }

  await ddb.send(
    new DeleteCommand({ TableName: USERS_TABLE_NAME, Key: { id } }),
  );
  return response(204, {});
}

// -----------------------------------------------------------------------------
// Router
// -----------------------------------------------------------------------------
exports.handler = async (event) => {
  const method = event.requestContext.http.method;
  const path = normalizePath(event);
  const id = event.pathParameters?.id;

  let body = {};
  if (event.body) {
    try {
      body = JSON.parse(event.body);
    } catch {
      return response(400, { error: "Invalid request body" });
    }
  }

  try {
    if (method === "GET" && path === "/players/active") {
      return await listActivePlayers();
    }
    if (method === "GET" && path === "/users") {
      return await listUsers();
    }
    if (method === "POST" && path === "/users") {
      return await createUser(body);
    }
    if (method === "PUT" && id) {
      return await updateUser(id, body);
    }
    if (method === "DELETE" && id) {
      return await deleteUser(id);
    }

    return response(404, { error: "Route not found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return response(500, { error: "Internal server error" });
  }
};
