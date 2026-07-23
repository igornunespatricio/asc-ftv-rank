const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  QueryCommand,
} = require("@aws-sdk/lib-dynamodb");
const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);
const ssm = new SSMClient({});

const USERS_TABLE_NAME = process.env.USERS_TABLE_NAME;
const JWT_SECRET_PARAM = process.env.JWT_SECRET_PARAM;
const TOKEN_TTL = "8h";

// Cached across warm invocations so we're not hitting SSM on every request.
let cachedSecret;

async function getJwtSecret() {
  if (cachedSecret) return cachedSecret;

  const result = await ssm.send(
    new GetParameterCommand({
      Name: JWT_SECRET_PARAM,
      WithDecryption: true,
    }),
  );

  cachedSecret = result.Parameter.Value;
  return cachedSecret;
}

function response(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  let email, password;
  try {
    const parsed = JSON.parse(event.body || "{}");
    email = parsed.email;
    password = parsed.password;
  } catch {
    return response(400, { error: "Invalid request body" });
  }

  if (!email || !password) {
    return response(400, { error: "email and password are required" });
  }

  let queryResult;
  try {
    queryResult = await ddb.send(
      new QueryCommand({
        TableName: USERS_TABLE_NAME,
        IndexName: "EmailIndex",
        KeyConditionExpression: "email = :email",
        ExpressionAttributeValues: { ":email": email },
      }),
    );
  } catch (err) {
    console.error("DynamoDB query failed:", err);
    return response(500, { error: "Internal server error" });
  }

  const user = queryResult.Items && queryResult.Items[0];

  // Same generic error whether the email doesn't exist or the password is
  // wrong — don't leak which one it was.
  if (!user || !user.password_hash) {
    return response(401, { error: "Invalid email or password" });
  }

  if (!user.is_admin) {
    // Only admins log in — viewers use the app with no auth at all.
    return response(401, { error: "Invalid email or password" });
  }

  const passwordMatches = await bcrypt.compare(password, user.password_hash);
  if (!passwordMatches) {
    return response(401, { error: "Invalid email or password" });
  }

  let secret;
  try {
    secret = await getJwtSecret();
  } catch (err) {
    console.error("Failed to fetch JWT secret:", err);
    return response(500, { error: "Internal server error" });
  }

  const token = jwt.sign(
    {
      sub: user.id,
      email: user.email,
      is_admin: true,
    },
    secret,
    { expiresIn: TOKEN_TTL },
  );

  return response(200, {
    token,
    user: {
      id: user.id,
      name: user.name,
      email: user.email,
    },
  });
};
