import { useEffect, useMemo, useState } from "react";
import { api, ApiError } from "../api/client";

// NOTE: query param names (`from`, `to`, `has_bet`) are assumed pending
// confirmation against the actual `matches` Lambda's ranking handler —
// CLAUDE.md references "API spec §7" for the full contract, which isn't
// in context here. Adjust `fetchRanking` below once that's confirmed.
function currentMonthRange() {
  const now = new Date();
  const from = new Date(now.getFullYear(), now.getMonth(), 1);
  const to = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  const iso = (d) => d.toISOString().slice(0, 10);
  return { from: iso(from), to: iso(to) };
}

const SORTS = [
  { key: "points", label: "Points" },
  { key: "win_pct", label: "Win %" },
];

export default function Ranking() {
  const [sortKey, setSortKey] = useState("points");
  const [betOnly, setBetOnly] = useState(false);
  const [rows, setRows] = useState(null);
  const [error, setError] = useState(null);
  const [range, setRange] = useState(currentMonthRange());

  useEffect(() => {
    let cancelled = false;
    setError(null);
    api;
    api
      .getRanking({
        start: range.from,
        end: range.to,
        bet: betOnly ? true : undefined,
      })
      .then((data) => {
        if (!cancelled) setRows(data);
      })
      .catch((err) => {
        if (!cancelled)
          setError(
            err instanceof ApiError
              ? err.message
              : "Couldn't load the ranking.",
          );
      });
    return () => {
      cancelled = true;
    };
  }, [range.from, range.to, betOnly]);

  const sorted = useMemo(() => {
    if (!rows) return null;
    return [...rows].sort((a, b) => b[sortKey] - a[sortKey]);
  }, [rows, sortKey]);

  const rangeLabel = `${range.from.split("-").reverse().join("/")} - ${range.to.split("-").reverse().join("/")}`;

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <div className="flex flex-wrap items-end justify-between gap-4 court-line pb-4 mb-6">
        <div>
          <p className="font-mono-nums text-xs uppercase tracking-widest text-net">
            {rangeLabel}
          </p>
          <h1 className="font-display text-5xl text-ink">Ranking</h1>
        </div>

        <div className="flex items-center gap-4">
          <div className="flex rounded border border-ink overflow-hidden">
            {SORTS.map((s) => (
              <button
                key={s.key}
                onClick={() => setSortKey(s.key)}
                className={`font-display text-sm tracking-wide px-3 py-1.5 ${
                  sortKey === s.key
                    ? "bg-ink text-chalk"
                    : "text-ink hover:bg-ink/10"
                }`}
              >
                {s.label}
              </button>
            ))}
          </div>

          <label className="flex items-center gap-2 font-display text-sm tracking-wide text-ink">
            <input
              type="checkbox"
              checked={betOnly}
              onChange={(e) => setBetOnly(e.target.checked)}
              className="h-4 w-4 accent-matchpoint"
            />
            Bet matches only
          </label>

          <input
            type="date"
            value={range.from}
            onChange={(e) => setRange((r) => ({ ...r, from: e.target.value }))}
          />
          <input
            type="date"
            value={range.to}
            onChange={(e) => setRange((r) => ({ ...r, to: e.target.value }))}
          />
        </div>
      </div>

      {error && (
        <p className="rounded border border-matchpoint bg-matchpoint/10 px-4 py-3 text-matchpoint">
          {error}
        </p>
      )}

      {!error && !sorted && (
        <p className="font-mono-nums text-wetsand">Loading ranking&hellip;</p>
      )}

      {!error && sorted && sorted.length === 0 && (
        <p className="rounded border border-dashed border-wetsand px-4 py-8 text-center text-net">
          No matches recorded for {rangeLabel} yet
          {betOnly ? " with bets on the line" : ""}. Once matches are logged,
          standings show up here.
        </p>
      )}

      {!error && sorted && sorted.length > 0 && (
        <ol className="flex flex-col gap-2">
          {sorted.map((player, i) => (
            <li
              key={player.player_id}
              className="flex items-center gap-4 rounded bg-chalk border border-ink/15 px-4 py-3"
            >
              <span
                className={`font-display text-3xl w-12 text-center rounded ${
                  i === 0
                    ? "text-chalk bg-matchpoint"
                    : "text-ink bg-sand border border-ink/20"
                }`}
              >
                {i + 1}
              </span>

              <span className="flex-1 min-w-0">
                <span className="block font-display text-xl text-ink truncate">
                  {player.player_name}
                </span>
                <span className="font-mono-nums text-xs text-wetsand">
                  {player.wins}W&ndash;{player.losses}L &middot;{" "}
                  {(player.win_pct * 100).toFixed(0)}% win
                  {player.bet_matches
                    ? ` · ${player.bet_wins}/${player.bet_matches} bets`
                    : ""}
                </span>
              </span>

              <span className="text-right">
                <span className="block font-mono-nums text-2xl text-net">
                  {player.points}
                </span>
                <span className="block font-mono-nums text-[10px] uppercase tracking-widest text-wetsand">
                  pts &middot; {player.points_ratio.toFixed(2)} ratio
                </span>
              </span>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
