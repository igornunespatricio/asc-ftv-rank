const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const jwt = require("jsonwebtoken");

const ssm = new SSMClient({});
const JWT_SECRET_PARAM = process.env.JWT_SECRET_PARAM;

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

function deny() {
  // Simple response format (authorizer_payload_format_version = "2.0",
  // enable_simple_responses = true in api_gateway.tf) — API Gateway turns
  // this into a 403 for the downstream route.
  return { isAuthorized: false };
}

exports.handler = async (event) => {
  const authHeader =
    event.headers?.authorization || event.headers?.Authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return deny();
  }

  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    return deny();
  }

  let secret;
  try {
    secret = await getJwtSecret();
  } catch (err) {
    console.error("Failed to fetch JWT secret:", err);
    return deny();
  }

  let decoded;
  try {
    decoded = jwt.verify(token, secret);
  } catch (err) {
    // Covers expired tokens, bad signature, malformed token — all treated
    // the same way: deny, no distinction leaked to the caller.
    console.warn("JWT verification failed:", err.message);
    return deny();
  }

  if (!decoded.is_admin) {
    return deny();
  }

  return {
    isAuthorized: true,
    context: {
      userId: decoded.sub,
      email: decoded.email,
    },
  };
};
