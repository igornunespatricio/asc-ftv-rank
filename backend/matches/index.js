const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
  UpdateCommand,
  DeleteCommand,
  QueryCommand,
  BatchGetCommand,
} = require("@aws-sdk/lib-dynamodb");
const { v4: uuidv4 } = require("uuid");
const { normalizePath } = require("shared");
const { calculateRanking, sortRanking } = require("./calculate");

const ddbClient = new DynamoDBClient({});
const ddb = DynamoDBDocumentClient.from(ddbClient);

const MATCHES_TABLE_NAME = process.env.MATCHES_TABLE_NAME;
const USERS_TABLE_NAME = process.env.USERS_TABLE_NAME;

function response(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

// Infinity isn't valid JSON — represent an unbeaten points ratio as a
// sentinel string instead of null (which is what JSON.stringify(Infinity)
// would silently produce).
function jsonSafeRanking(ranking) {
  return ranking.map((r) => ({
    ...r,
    points_ratio: r.points_ratio === Infinity ? "undefeated" : r.points_ratio,
  }));
}

// match_month is computed here, not user-supplied, per CLAUDE.md.
function computeMatchMonth(matchDate) {
  return matchDate.slice(0, 7); // "YYYY-MM-DD" -> "YYYY-MM"
}

function defaultDateRange() {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, "0");
  const start = `${year}-${month}-01`;
  const end = new Date(Date.UTC(year, now.getUTCMonth() + 1, 0))
    .toISOString()
    .slice(0, 10);
  return { start, end };
}

// Queries MatchDateIndex across every month bucket the [start, end] range
// touches. Usually just the current month, but spans correctly if a caller
// passes a wider explicit range.
async function queryMatchesInRange(start, end) {
  const months = new Set();
  let cursor = new Date(`${start}T00:00:00Z`);
  const endDate = new Date(`${end}T00:00:00Z`);
  while (cursor <= endDate) {
    months.add(cursor.toISOString().slice(0, 7));
    cursor.setUTCMonth(cursor.getUTCMonth() + 1);
  }

  const results = [];
  for (const month of months) {
    const result = await ddb.send(
      new QueryCommand({
        TableName: MATCHES_TABLE_NAME,
        IndexName: "MatchDateIndex",
        KeyConditionExpression:
          "match_month = :month AND match_date BETWEEN :start AND :end",
        ExpressionAttributeValues: {
          ":month": month,
          ":start": start,
          ":end": end,
        },
      }),
    );
    results.push(...(result.Items || []));
  }
  return results;
}

async function getPlayerNamesById(playerIds) {
  const uniqueIds = [...new Set(playerIds.filter(Boolean))];
  if (uniqueIds.length === 0) return {};

  // BatchGetCommand caps at 100 keys per request; fine at this project's
  // scale, but chunk defensively in case the player pool grows.
  const namesById = {};
  for (let i = 0; i < uniqueIds.length; i += 100) {
    const chunk = uniqueIds.slice(i, i + 100);
    const result = await ddb.send(
      new BatchGetCommand({
        RequestItems: {
          [USERS_TABLE_NAME]: {
            Keys: chunk.map((id) => ({ id })),
          },
        },
      }),
    );
    for (const user of result.Responses?.[USERS_TABLE_NAME] || []) {
      namesById[user.id] = user.name;
    }
  }
  return namesById;
}

// -----------------------------------------------------------------------------
// GET /matches — public. Optional ?start=YYYY-MM-DD&end=YYYY-MM-DD&bet=true
// -----------------------------------------------------------------------------
async function listMatches(queryParams) {
  const { start, end } =
    queryParams.start && queryParams.end
      ? { start: queryParams.start, end: queryParams.end }
      : defaultDateRange();

  let matches = await queryMatchesInRange(start, end);

  if (queryParams.bet === "true") {
    matches = matches.filter((m) => m.has_bet);
  }

  const playerIds = matches.flatMap((m) => [
    m.player1_team1,
    m.player2_team1,
    m.player1_team2,
    m.player2_team2,
  ]);
  const namesById = await getPlayerNamesById(playerIds);

  const enriched = matches.map((m) => ({
    ...m,
    player1_team1_name: namesById[m.player1_team1] || null,
    player2_team1_name: namesById[m.player2_team1] || null,
    player1_team2_name: namesById[m.player1_team2] || null,
    player2_team2_name: namesById[m.player2_team2] || null,
  }));

  return response(200, { matches: enriched, range: { start, end } });
}

// -----------------------------------------------------------------------------
// GET /ranking — public. Optional ?start=&end=&bet=true&sort=points|win_pct
// -----------------------------------------------------------------------------
async function getRanking(queryParams) {
  const { start, end } =
    queryParams.start && queryParams.end
      ? { start: queryParams.start, end: queryParams.end }
      : defaultDateRange();

  let matches = await queryMatchesInRange(start, end);

  if (queryParams.bet === "true") {
    matches = matches.filter((m) => m.has_bet);
  }

  const ranking = sortRanking(calculateRanking(matches), queryParams.sort);

  const playerIds = ranking.map((r) => r.player_id);
  const namesById = await getPlayerNamesById(playerIds);

  const enriched = ranking.map((r) => ({
    ...r,
    player_name: namesById[r.player_id] || null,
  }));

  return response(200, {
    ranking: jsonSafeRanking(enriched),
    range: { start, end },
  });
}

// -----------------------------------------------------------------------------
// POST /matches — admin-only.
// -----------------------------------------------------------------------------
async function createMatch(body) {
  const {
    match_date,
    player1_team1,
    player2_team1,
    player1_team2,
    player2_team2,
    score_team1,
    score_team2,
    has_bet,
  } = body;

  if (!match_date || !/^\d{4}-\d{2}-\d{2}$/.test(match_date)) {
    return response(400, {
      error: "match_date is required in YYYY-MM-DD format",
    });
  }
  if (!player1_team1 || !player2_team1 || !player1_team2 || !player2_team2) {
    return response(400, { error: "all four player IDs are required" });
  }
  if (typeof score_team1 !== "number" || typeof score_team2 !== "number") {
    return response(400, {
      error: "score_team1 and score_team2 must be numbers",
    });
  }
  if (score_team1 === score_team2) {
    return response(400, {
      error: "ties are not allowed — scores must differ",
    });
  }

  const match = {
    id: uuidv4(),
    match_date,
    match_month: computeMatchMonth(match_date),
    player1_team1,
    player2_team1,
    player1_team2,
    player2_team2,
    score_team1,
    score_team2,
    has_bet: Boolean(has_bet),
  };

  await ddb.send(
    new PutCommand({
      TableName: MATCHES_TABLE_NAME,
      Item: match,
      ConditionExpression: "attribute_not_exists(id)",
    }),
  );

  return response(201, { match });
}

// -----------------------------------------------------------------------------
// PUT /matches/:id — admin-only. Partial update.
// If match_date changes, match_month is recomputed to keep the GSI correct.
// -----------------------------------------------------------------------------
async function updateMatch(id, body) {
  const existing = await ddb.send(
    new GetCommand({ TableName: MATCHES_TABLE_NAME, Key: { id } }),
  );
  if (!existing.Item) {
    return response(404, { error: "Match not found" });
  }

  const merged = { ...existing.Item, ...body };

  if (
    typeof merged.score_team1 === "number" &&
    typeof merged.score_team2 === "number" &&
    merged.score_team1 === merged.score_team2
  ) {
    return response(400, {
      error: "ties are not allowed — scores must differ",
    });
  }

  const updateFields = {
    match_date: merged.match_date,
    match_month: computeMatchMonth(merged.match_date),
    player1_team1: merged.player1_team1,
    player2_team1: merged.player2_team1,
    player1_team2: merged.player1_team2,
    player2_team2: merged.player2_team2,
    score_team1: merged.score_team1,
    score_team2: merged.score_team2,
    has_bet: Boolean(merged.has_bet),
  };

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
      TableName: MATCHES_TABLE_NAME,
      Key: { id },
      UpdateExpression: `SET ${setClauses.join(", ")}`,
      ExpressionAttributeNames: names,
      ExpressionAttributeValues: values,
      ReturnValues: "ALL_NEW",
    }),
  );

  return response(200, { match: result.Attributes });
}

// -----------------------------------------------------------------------------
// DELETE /matches/:id — admin-only.
// -----------------------------------------------------------------------------
async function deleteMatch(id) {
  const existing = await ddb.send(
    new GetCommand({ TableName: MATCHES_TABLE_NAME, Key: { id } }),
  );
  if (!existing.Item) {
    return response(404, { error: "Match not found" });
  }

  await ddb.send(
    new DeleteCommand({ TableName: MATCHES_TABLE_NAME, Key: { id } }),
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
  const queryParams = event.queryStringParameters || {};

  let body = {};
  if (event.body) {
    try {
      body = JSON.parse(event.body);
    } catch {
      return response(400, { error: "Invalid request body" });
    }
  }

  try {
    if (method === "GET" && path === "/matches") {
      return await listMatches(queryParams);
    }
    if (method === "GET" && path === "/ranking") {
      return await getRanking(queryParams);
    }
    if (method === "POST" && path === "/matches") {
      return await createMatch(body);
    }
    if (method === "PUT" && id) {
      return await updateMatch(id, body);
    }
    if (method === "DELETE" && id) {
      return await deleteMatch(id);
    }

    return response(404, { error: "Route not found" });
  } catch (err) {
    console.error("Unhandled error:", err);
    return response(500, { error: "Internal server error" });
  }
};
