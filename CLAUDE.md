# Footvolley Ranking Website — Project Context

This file gives persistent context for AI-assisted development. Read this before generating code so decisions stay consistent across sessions.

## Stack (locked decisions — do not suggest alternatives without asking)

- **Frontend:** React, hosted as a static build on **S3**, served via **CloudFront**.
- **API:** **API Gateway (HTTP API)** + **AWS Lambda** (Node.js). No always-on server.
- **Database:** **DynamoDB**, on-demand capacity mode. **Two separate tables**: `Users` and `Matches`. No single-table design.
- **Auth:** JWT issued by a login Lambda, verified via a Lambda authorizer on admin-only routes.
- **IaC / CI:** Terraform + GitHub Actions. **Environments (`dev`, `test`, `prod`) are managed via Terraform workspaces**, not separate variables or directories. Resource names are derived from `terraform.workspace` (e.g. `footvolley-dev-users`, `footvolley-prod-matches`). Each workspace has isolated state, so `terraform apply` while on `dev` cannot touch `prod` resources. Always confirm the active workspace (`terraform workspace show`) before applying.
- **Explicitly excluded:** EC2, RDS, ECS, Docker Compose for prod, anything relational/SQL.

## DynamoDB schema

### `Users` table

| Attribute       | Type        | Notes                                                     |
| --------------- | ----------- | --------------------------------------------------------- |
| `id`            | string (PK) | UUID                                                      |
| `name`          | string      | Display name                                              |
| `status`        | boolean     | active/inactive — only active users go in match dropdowns |
| `is_admin`      | boolean     |                                                           |
| `email`         | string      | GSI: `EmailIndex` (PK: `email`) — for login lookup        |
| `password_hash` | string      | Admins only                                               |

GSIs:

- `EmailIndex` — PK `email` — used by login Lambda.
- Consider a `StatusIndex` (PK `status`) if scanning for active players gets expensive — otherwise a filtered Scan is fine at expected data volumes.

### `Matches` table

| Attribute                                                          | Type              | Notes                                            |
| ------------------------------------------------------------------ | ----------------- | ------------------------------------------------ |
| `id`                                                               | string (PK)       | UUID                                             |
| `match_date`                                                       | string (ISO date) | Sort key candidate / GSI key                     |
| `player1_team1`, `player2_team1`, `player1_team2`, `player2_team2` | string            | User IDs — no FK enforcement, validate in Lambda |
| `score_team1`, `score_team2`                                       | number            |                                                  |
| `has_bet`                                                          | boolean           |                                                  |

GSIs:

- `MatchDateIndex` — PK `match_month` (computed "YYYY-MM" bucket, written by the Lambda handler at write time — not user-supplied), SK `match_date` (ISO date string). Supports "matches in date range" queries without a full table scan. **Decided**: month-bucket, not a constant partition key — see resolved decision below.

No joins exist. If a query needs player names alongside a match, either:

1. Denormalize player names onto the match record at write time, or
2. Batch-get from `Users` after fetching matches.
   Default to (2) unless it becomes a measured bottleneck — denormalizing means player renames require a backfill.

## Business rules (ranking math)

- Win = 3 points, Loss = 0. No ties (higher score wins, always).
- Ranking computed **per player**, over matches in a date range (default: current calendar month).
- Per player: wins, losses, win % (`wins / total matches`), points scored, points against, points ratio (`scored / against`), bet matches count, bet wins, bet win %.
- Ranking sort: by points (default) or by win % — toggle, no persistence needed server-side.
- Bet filter: when on, recompute **both** the matches list and ranking using only `has_bet = true` matches.
- All ranking math is computed **in Lambda application code** — no SQL aggregates available. Keep this logic in a shared module (e.g. `backend/ranking/calculate.js`) so it's unit-testable independent of the Lambda handler.

## Access rules

- Viewer: no auth, read-only. Never sees edit/delete controls or the Manage Users page.
- Admin: `is_admin = true` on their `Users` row. Full CRUD on `Users` and `Matches`.
- Inactive players (`status = false`): excluded from _new match_ dropdowns, but still shown in historical matches/rankings if they appear in past data.

## API endpoints (see spec §7 for full table)

Public: `POST /auth/login`, `GET /matches`, `GET /ranking`, `GET /players/active`
Admin-only (Lambda authorizer required): `POST/PUT/DELETE /matches/:id`, `GET/POST/PUT/DELETE /users`, `/users/:id`

## Conventions

- - Lambdas grouped by resource: `matches/`, `users/`, `auth/`, plus a separate `authorizer/` Lambda for JWT verification. Don't mix per-endpoint and grouped patterns.
- Ranking calculation logic lives in a shared, framework-agnostic module — not inlined in the Lambda handler — so it has direct unit tests.
- Local dev emulates the serverless stack (SAM Local / LocalStack / `serverless-offline`) — no Docker Compose + Postgres.
- Terraform provisions: S3 bucket + CloudFront distribution, API Gateway, Lambda functions, `Users` table, `Matches` table.
- **Terraform workspaces** (`dev`, `test`, `prod`) drive environment naming via `local.environment = terraform.workspace`. A `check` block in `infra/locals.tf` fails plan/apply if the active workspace isn't one of the three. Never add an `environment` variable back in — workspace is the single source of truth.
- `required_providers` / `required_version` live only in `versions.tf`; `providers.tf` holds backend config and provider configuration blocks only — don't duplicate or split provider requirements across both files.
- End-to-end smoke tests live in `tests/e2e/` (separate from `scripts/`, which is bootstrap/setup only), named `test_<name>.sh`. `tests/e2e/run_all.sh` discovers and runs all of them by glob — no changes needed there or in the CI workflow when a new test file is added. Run in the GitHub Actions workflow as a step immediately after `Terraform Apply` (CD smoke test, not CI).

## Resolved decisions (for reference)

- **`MatchDateIndex` partition strategy**: month-bucket (`match_month` as GSI hash key), not a constant partition key. Trade-off accepted: match-writing Lambda must compute `match_month` from `match_date` at write time.
- **Environment management**: Terraform workspaces, not a variable or separate state directories per environment.

## Open decisions (flag if touched, don't silently assume)

- Exact `MatchDateIndex` partition strategy (constant key vs. month-bucket).
- Pagination for matches table at scale.
- Audit log for admin edits/deletes.
