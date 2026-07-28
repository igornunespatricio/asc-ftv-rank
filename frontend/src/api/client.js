// Thin fetch wrapper around the deployed API Gateway HTTP API.
//
// VITE_API_BASE_URL should be the full invoke URL including the stage,
// e.g. https://abc123.execute-api.us-east-1.amazonaws.com/dev
// (matches aws_apigatewayv2_stage.main's invoke_url output in api_gateway.tf).
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL;

if (!API_BASE_URL) {
  // Fail loudly at dev-server start rather than silently hitting "undefined/matches".
  console.error(
    "VITE_API_BASE_URL is not set. Copy .env.example to .env and set it to your API Gateway invoke URL."
  );
}

class ApiError extends Error {
  constructor(message, status, body) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.body = body;
  }
}

async function request(path, { method = "GET", body, token, signal } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal,
  });

  // Admin routes with no/expired/invalid token come back 401/403 from the
  // Lambda authorizer before ever reaching a Lambda handler — same shape.
  let data = null;
  const text = await res.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const message =
      (data && typeof data === "object" && data.message) ||
      `Request failed with status ${res.status}`;
    throw new ApiError(message, res.status, data);
  }

  return data;
}

export const api = {
  // Public
  login: (email, password) =>
    request("/auth/login", { method: "POST", body: { email, password } }),
  getMatches: (params = {}) =>
    request(`/matches${toQuery(params)}`),
  getRanking: (params = {}) =>
    request(`/ranking${toQuery(params)}`),
  getActivePlayers: () => request("/players/active"),

  // Admin (require token)
  createMatch: (token, match) =>
    request("/matches", { method: "POST", body: match, token }),
  updateMatch: (token, id, match) =>
    request(`/matches/${id}`, { method: "PUT", body: match, token }),
  deleteMatch: (token, id) =>
    request(`/matches/${id}`, { method: "DELETE", token }),
  getUsers: (token) => request("/users", { token }),
  createUser: (token, user) =>
    request("/users", { method: "POST", body: user, token }),
  updateUser: (token, id, user) =>
    request(`/users/${id}`, { method: "PUT", body: user, token }),
  deleteUser: (token, id) =>
    request(`/users/${id}`, { method: "DELETE", token }),
};

function toQuery(params) {
  const entries = Object.entries(params).filter(([, v]) => v !== undefined && v !== "");
  if (entries.length === 0) return "";
  return `?${new URLSearchParams(entries).toString()}`;
}

export { ApiError };
