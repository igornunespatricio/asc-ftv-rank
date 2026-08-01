import { useEffect, useState } from "react";
import { api, ApiError } from "../api/client";

// Same start/end/bet param contract as Ranking.jsx and AdminMatches.jsx,
// confirmed against the matches Lambda.
function currentMonthRange() {
  const now = new Date();
  const from = new Date(now.getFullYear(), now.getMonth(), 1);
  const to = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  const iso = (d) => d.toISOString().slice(0, 10);
  return { start: iso(from), end: iso(to) };
}

export default function Matches() {
  const [range, setRange] = useState(currentMonthRange());
  const [betOnly, setBetOnly] = useState(false);
  const [matches, setMatches] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setError(null);
    api
      .getMatches({
        start: range.start,
        end: range.end,
        bet: betOnly ? true : undefined,
      })
      .then((data) => {
        if (!cancelled) setMatches(data.matches ?? data);
      })
      .catch((err) => {
        if (!cancelled)
          setError(
            err instanceof ApiError ? err.message : "Couldn't load matches.",
          );
      });
    return () => {
      cancelled = true;
    };
  }, [range.start, range.end, betOnly]);

  const rangeLabel = `${range.start.split("-").reverse().join("/")} \u2013 ${range.end
    .split("-")
    .reverse()
    .join("/")}`;

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <div className="flex flex-wrap items-end justify-between gap-4 court-line pb-4 mb-6">
        <div>
          <p className="font-mono-nums text-xs uppercase tracking-widest text-net">
            {rangeLabel}
          </p>
          <h1 className="font-display text-5xl text-ink">Matches</h1>
        </div>

        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1">
            <span className="font-display text-sm tracking-wide text-net">
              From
            </span>
            <input
              type="date"
              value={range.start}
              onChange={(e) =>
                setRange((r) => ({ ...r, start: e.target.value }))
              }
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="font-display text-sm tracking-wide text-net">
              To
            </span>
            <input
              type="date"
              value={range.end}
              onChange={(e) => setRange((r) => ({ ...r, end: e.target.value }))}
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>
          <label className="flex items-center gap-2 font-display text-sm tracking-wide text-ink pb-2">
            <input
              type="checkbox"
              checked={betOnly}
              onChange={(e) => setBetOnly(e.target.checked)}
              className="h-4 w-4 accent-matchpoint"
            />
            Bet matches only
          </label>
        </div>
      </div>

      {error && (
        <p className="rounded border border-matchpoint bg-matchpoint/10 px-4 py-3 text-matchpoint">
          {error}
        </p>
      )}

      {!error && !matches && (
        <p className="font-mono-nums text-wetsand">Loading matches&hellip;</p>
      )}

      {!error && matches && matches.length === 0 && (
        <p className="rounded border border-dashed border-wetsand px-4 py-8 text-center text-net">
          No matches recorded for {rangeLabel} yet
          {betOnly ? " with bets on the line" : ""}.
        </p>
      )}

      {!error && matches && matches.length > 0 && (
        <ul className="flex flex-col gap-2">
          {matches.map((match) => (
            <li
              key={match.id}
              className="flex flex-wrap items-center gap-4 rounded bg-chalk border border-ink/15 px-4 py-3"
            >
              <span className="font-mono-nums text-xs text-wetsand w-24 shrink-0">
                {match.match_date.split("-").reverse().join("/")}
              </span>

              <span className="flex-1 min-w-0 font-display text-lg text-ink truncate">
                {match.player1_team1_name} &amp; {match.player2_team1_name}
                <span className="text-wetsand"> vs </span>
                {match.player1_team2_name} &amp; {match.player2_team2_name}
              </span>

              <span className="font-mono-nums text-xl text-net shrink-0">
                {match.score_team1}&ndash;{match.score_team2}
              </span>

              {match.has_bet && (
                <span className="font-display text-xs tracking-wide px-2 py-1 rounded bg-matchpoint/10 text-matchpoint shrink-0">
                  Bet
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
