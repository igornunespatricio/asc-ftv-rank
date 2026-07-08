# Footvolley Ranking Website — Project Specification

## 1. Overview

A website to record footvolley (foot-volley) match results and automatically calculate player rankings and statistics. Two roles: **Viewer** (read-only, no login required) and **Admin** (login required, full CRUD).

---

## 2. Roles & Authentication

- **Viewer**
  - No login required.
  - Can view matches table and ranking/statistics.
  - Cannot see edit/delete controls on matches.
  - Cannot access the user/player management page.
- **Admin**
  - Must log in.
  - Full CRUD on **users/players** and **matches**.
  - Sees edit/delete buttons next to each match on the home page.
  - Has access to a dedicated "Manage Users/Players" page.
  - "Admin" is itself a boolean flag on the user/player record (`is_admin`), so an admin is just a user row with `is_admin = true`.

---

## 3. Data Model

### 3.1 Users / Players table
Acts as both the login/user table and the players table (a player is any user, admin or not).

| Column      | Type      | Notes                                      |
|-------------|-----------|---------------------------------------------|
| id          | UUID/int  | Primary key                                 |
| name        | string    | Display name, shown in dropdowns             |
| status      | boolean   | Active / inactive — only active users appear in match dropdowns |
| is_admin    | boolean   | Determines if login/admin rules apply       |
| email       | string    | Needed for login (admins only)              |
| password_hash | string  | Only relevant for admin accounts            |

### 3.2 Matches table

| Column        | Type     | Notes                                   |
|---------------|----------|-------------------------------------------|
| id            | UUID/int | Primary key                               |
| player1_team1 | FK → users.id | |
| player2_team1 | FK → users.id | |
| player1_team2 | FK → users.id | |
| player2_team2 | FK → users.id | |
| score_team1   | int      | Points scored by team 1                   |
| score_team2   | int      | Points scored by team 2                   |
| match_date    | date     | Date the match occurred                   |
| has_bet       | boolean  | Whether players bet on this match         |

Winner is inferred: no ties allowed, higher score wins.

---

## 4. Business Rules — Scoring & Ranking

- **Win = 3 points, Loss = 0 points** (no ties exist in this sport as modeled here).
- Ranking is calculated **per player**, across all matches in a **date range** (default: current calendar month, start/end dates adjustable).
- Per player, calculate:
  - Number of wins
  - Number of losses
  - Win percentage (`wins / total matches`)
  - Total points scored (sum of own team's score across matches)
  - Total points against (sum of opposing team's score across matches)
  - Points ratio = `points scored / points against`
  - Number of matches with a bet (`has_bet = true`)
  - Number of wins in bet matches
  - Win percentage in bet matches

### Ranking sort options (toggle button)
1. **By points** (3 per win) — **default**
2. **By win percentage**

### Bet filter (toggle/filter button)
- When enabled, recalculates **both** the matches table and the ranking/statistics using **only** matches where `has_bet = true`.

### Date range filter
- Default: first day → last day of current month.
- Adjustable via start date / end date pickers; ranking and matches table recalculate on change.

---

## 5. Pages

### 5.1 Home / Landing Page
- Accessible to everyone (viewers included), no login required to view.
- Login button/link for admins.
- Date range picker (defaults to current month).
- Bet-only filter toggle.
- **Matches table**: list of matches in the selected date range (respecting bet filter).
  - If logged in as admin: edit + delete buttons per row.
  - If viewer: no edit/delete controls.
- **Ranking table**: computed from the same filtered matches.
  - Toggle button: rank by points vs rank by win %.
  - Columns: player name, wins, losses, win %, points scored, points against, points ratio, total matches.

### 5.2 Login Page (Admin only)
- Simple email/password form.
- On success, redirect to Home with admin controls enabled.

### 5.3 Manage Users/Players Page (Admin only)
- Table listing all users, one row per user: id, name, status (active/inactive), is_admin.
- Edit button per row → edit form (name, status, is_admin, email/password if applicable).
- Create new user/player.

### 5.4 Match Create/Edit Form (Admin only)
Fields:
- Player 1 - Team 1 (dropdown, active players only)
- Player 2 - Team 1 (dropdown, active players only)
- Player 1 - Team 2 (dropdown, active players only)
- Player 2 - Team 2 (dropdown, active players only)
- Score - Team 1
- Score - Team 2
- Date of match
- Has bet? (checkbox)

---

## 6. Suggested Tech Stack (Serverless, AWS)

- **Frontend hosting:** Static React build hosted on **S3** (static website hosting or as an origin), served through **CloudFront** for CDN/HTTPS/caching. Pay only for storage + requests/data transfer.
- **API:** **API Gateway (HTTP API)** in front of **AWS Lambda** functions (Node.js/Express-style handlers, e.g. via a lightweight router like `serverless-http` wrapping Express, or plain Lambda handlers). Pay per request/invocation — no always-on compute.
- **Database:** **DynamoDB** for both `users/players` and `matches` (on-demand capacity mode for pure pay-as-you-go pricing). No relational joins — match records would store player IDs (and optionally denormalized player names) as attributes, and ranking aggregation happens in Lambda application code rather than SQL aggregate queries.
- **Auth:** JWT-based admin auth issued by a Lambda function (custom login endpoint), verified via a Lambda authorizer on API Gateway for admin-only routes. *(Alternative worth considering: **Amazon Cognito** for managed, pay-as-you-go user auth instead of hand-rolled JWT — would replace the custom login Lambda and password_hash storage.)*
- **Infra:** **Terraform** + **GitHub Actions** for dev/test/prod deploys — provisioning S3, CloudFront, API Gateway, Lambda, and DynamoDB. No EC2, no RDS, nothing always-on to manage.

---

## 7. API Endpoints (draft)

| Method | Endpoint             | Access        | Description                          |
|--------|----------------------|---------------|---------------------------------------|
| POST   | /auth/login          | Public        | Admin login                          |
| GET    | /matches?start=&end=&betsOnly= | Public | List matches in range              |
| POST   | /matches             | Admin only    | Create match                         |
| PUT    | /matches/:id         | Admin only    | Edit match                           |
| DELETE | /matches/:id         | Admin only    | Delete match                         |
| GET    | /ranking?start=&end=&betsOnly=&sortBy= | Public | Computed ranking/stats          |
| GET    | /users               | Admin only    | List users/players                   |
| POST   | /users               | Admin only    | Create user/player                   |
| PUT    | /users/:id           | Admin only    | Edit user/player                     |
| DELETE | /users/:id           | Admin only    | Delete user/player                   |
| GET    | /players/active      | Public        | List active players for dropdowns    |

---

## 8. Open Questions / Decisions for Later

- Should viewers be fully public (no auth at all), or should there be a lightweight "read-only session" concept? (Currently spec says no login needed for viewers.)
- Password reset flow for admins?
- Should inactive players still show historically in past matches/rankings, or be excluded entirely? (Recommend: still show in historical matches, but excluded from *new match* dropdowns.)
- Pagination for matches table once volume grows?
- Should there be an audit log for admin edits/deletes on matches?

---

## 9. Next Steps

1. Scaffold repo structure: `frontend/` (React app), `backend/` (Lambda function handlers, organized by resource — e.g. `matches/`, `users/`, `ranking/`, `auth/`), `infra/` (Terraform for S3, CloudFront, API Gateway, Lambda, DynamoDB).
2. Define **DynamoDB table design using two tables — a `Users` table and a `Matches` table** (not a single-table design). For each table, decide on the primary key (partition/sort key) structure and any Global Secondary Indexes (GSIs) needed to support required query patterns:
   - `Users` table — primary key on `id`; likely needs a GSI on `email` (to support admin login lookups) and possibly on `status` (to support fetching active players for dropdowns).
   - `Matches` table — primary key on `id`; needs a GSI on `match_date` (or a computed date-bucket attribute) to support querying matches within a date range, and since there are no relational joins, matches will store the four player IDs directly as attributes (optionally denormalizing player names onto the match record to avoid extra lookups against the `Users` table).
3. Build **ranking calculation logic as Lambda application code** (no SQL aggregates available) — a function that reads matches for the selected date range/bet filter from the `Matches` table, cross-references player info from the `Users` table as needed, and computes wins, losses, win %, points scored/against, points ratio, and bet-match stats in-memory. Include unit tests for the point/percentage/ratio math.
4. Build the API using **API Gateway + Lambda** for the endpoints defined in Section 7 (one Lambda per endpoint, or grouped by resource), including a Lambda authorizer for admin-only routes.
5. Build React pages: Home (matches + ranking + filters), Login, Manage Users.
6. Set up **local development** for the serverless stack — e.g. AWS SAM Local, LocalStack, or `serverless-offline` to emulate API Gateway, Lambda, and the two DynamoDB tables locally without needing Docker Compose/Postgres.
7. Set up **Terraform + GitHub Actions** for dev/test/prod deploy on AWS — provisioning S3 (static hosting) + CloudFront for the frontend, API Gateway + Lambda for the API, and the two DynamoDB tables (`Users`, `Matches`) for storage, with CI/CD building the React app to S3 and deploying Lambda code on each push.