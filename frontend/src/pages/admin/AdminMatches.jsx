import { useEffect, useMemo, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import { api, ApiError } from "../../api/client";

// Same param-name contract as the public /matches and /ranking endpoints:
// start / end / bet (query string), confirmed against the matches Lambda.
function currentMonthRange() {
  const now = new Date();
  const from = new Date(now.getFullYear(), now.getMonth(), 1);
  const to = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  const iso = (d) => d.toISOString().slice(0, 10);
  return { start: iso(from), end: iso(to) };
}

const EMPTY_FORM = {
  id: null,
  match_date: "",
  player1_team1: "",
  player2_team1: "",
  player1_team2: "",
  player2_team2: "",
  score_team1: "",
  score_team2: "",
  has_bet: false,
};

const TEAM_SLOTS = [
  { key: "player1_team1", label: "Team 1 — Player 1" },
  { key: "player2_team1", label: "Team 1 — Player 2" },
  { key: "player1_team2", label: "Team 2 — Player 1" },
  { key: "player2_team2", label: "Team 2 — Player 2" },
];

export default function AdminMatches() {
  const { token } = useAuth();
  const [range, setRange] = useState(currentMonthRange());
  const [matches, setMatches] = useState(null);
  const [players, setPlayers] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [formError, setFormError] = useState(null);
  const [saving, setSaving] = useState(false);

  const isEditing = form.id !== null;

  async function refreshMatches() {
    try {
      const data = await api.getMatches({ start: range.start, end: range.end });
      setMatches(data.matches ?? data);
      setLoadError(null);
    } catch (err) {
      setLoadError(
        err instanceof ApiError ? err.message : "Couldn't load matches.",
      );
    }
  }

  useEffect(() => {
    refreshMatches();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [range.start, range.end]);

  useEffect(() => {
    api
      .getActivePlayers()
      .then((data) => setPlayers(data.players ?? data))
      .catch(() => setPlayers([])); // dropdowns just show empty rather than blocking the page
  }, []);

  // Dropdown options: active players, PLUS whoever's currently selected in
  // the form even if they've since gone inactive — otherwise editing an old
  // match with an inactive player would show a blank/broken select.
  const playerOptions = useMemo(() => {
    const base = players ? [...players] : [];
    const known = new Set(base.map((p) => p.id));
    for (const slot of TEAM_SLOTS) {
      const id = form[slot.key];
      if (id && !known.has(id)) {
        base.push({
          id,
          name: `${form[`${slot.key}_name`] || "Inactive player"} (inactive)`,
        });
        known.add(id);
      }
    }
    return base;
  }, [players, form]);

  function startEdit(match) {
    setForm({
      id: match.id,
      match_date: match.match_date,
      player1_team1: match.player1_team1,
      player1_team1_name: match.player1_team1_name,
      player2_team1: match.player2_team1,
      player2_team1_name: match.player2_team1_name,
      player1_team2: match.player1_team2,
      player1_team2_name: match.player1_team2_name,
      player2_team2: match.player2_team2,
      player2_team2_name: match.player2_team2_name,
      score_team1: String(match.score_team1),
      score_team2: String(match.score_team2),
      has_bet: Boolean(match.has_bet),
    });
    setFormError(null);
  }

  function cancelEdit() {
    setForm(EMPTY_FORM);
    setFormError(null);
  }

  async function handleDelete(match) {
    if (!confirm(`Delete the ${match.match_date} match? This can't be undone.`))
      return;
    try {
      await api.deleteMatch(token, match.id);
      if (form.id === match.id) cancelEdit();
      await refreshMatches();
    } catch (err) {
      setLoadError(
        err instanceof ApiError ? err.message : "Couldn't delete match.",
      );
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setFormError(null);

    if (!form.match_date) {
      setFormError("Match date is required.");
      return;
    }

    const teamIds = TEAM_SLOTS.map((s) => form[s.key]);
    if (teamIds.some((id) => !id)) {
      setFormError("All four players are required.");
      return;
    }
    if (new Set(teamIds).size !== 4) {
      setFormError("Each player can only appear once in a match.");
      return;
    }

    const score_team1 = Number(form.score_team1);
    const score_team2 = Number(form.score_team2);
    if (
      form.score_team1 === "" ||
      form.score_team2 === "" ||
      Number.isNaN(score_team1) ||
      Number.isNaN(score_team2)
    ) {
      setFormError("Both scores are required numbers.");
      return;
    }
    if (score_team1 === score_team2) {
      setFormError("Ties are not allowed — scores must differ.");
      return;
    }

    const payload = {
      match_date: form.match_date,
      player1_team1: form.player1_team1,
      player2_team1: form.player2_team1,
      player1_team2: form.player1_team2,
      player2_team2: form.player2_team2,
      score_team1,
      score_team2,
      has_bet: form.has_bet,
    };

    setSaving(true);
    try {
      if (isEditing) {
        await api.updateMatch(token, form.id, payload);
      } else {
        await api.createMatch(token, payload);
      }
      cancelEdit();
      await refreshMatches();
    } catch (err) {
      setFormError(
        err instanceof ApiError ? err.message : "Couldn't save match.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <h1 className="font-display text-5xl text-ink mb-6">Manage Matches</h1>

      <form
        onSubmit={handleSubmit}
        className="mb-8 rounded border border-ink/15 bg-chalk p-4 flex flex-col gap-3"
      >
        <p className="font-display text-lg tracking-wide text-net">
          {isEditing ? `Editing match — ${form.match_date}` : "Log a match"}
        </p>

        <label className="flex flex-col gap-1 max-w-[180px]">
          <span className="font-display text-sm tracking-wide text-net">
            Date
          </span>
          <input
            type="date"
            value={form.match_date}
            onChange={(e) =>
              setForm((f) => ({ ...f, match_date: e.target.value }))
            }
            className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
          />
        </label>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {TEAM_SLOTS.map((slot) => (
            <label key={slot.key} className="flex flex-col gap-1">
              <span className="font-display text-sm tracking-wide text-net">
                {slot.label}
              </span>
              <select
                value={form[slot.key]}
                onChange={(e) =>
                  setForm((f) => ({ ...f, [slot.key]: e.target.value }))
                }
                className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
              >
                <option value="">Select a player&hellip;</option>
                {playerOptions.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>

        <div className="flex flex-wrap items-end gap-3">
          <label className="flex flex-col gap-1 w-24">
            <span className="font-display text-sm tracking-wide text-net">
              Team 1 score
            </span>
            <input
              type="number"
              value={form.score_team1}
              onChange={(e) =>
                setForm((f) => ({ ...f, score_team1: e.target.value }))
              }
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink font-mono-nums focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>

          <label className="flex flex-col gap-1 w-24">
            <span className="font-display text-sm tracking-wide text-net">
              Team 2 score
            </span>
            <input
              type="number"
              value={form.score_team2}
              onChange={(e) =>
                setForm((f) => ({ ...f, score_team2: e.target.value }))
              }
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink font-mono-nums focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>

          <label className="flex items-center gap-2 font-display text-sm tracking-wide text-ink pb-2">
            <input
              type="checkbox"
              checked={form.has_bet}
              onChange={(e) =>
                setForm((f) => ({ ...f, has_bet: e.target.checked }))
              }
              className="h-4 w-4 accent-matchpoint"
            />
            Bet match
          </label>
        </div>

        {formError && (
          <p className="rounded border border-matchpoint bg-matchpoint/10 px-3 py-2 text-sm text-matchpoint">
            {formError}
          </p>
        )}

        <div className="flex gap-3">
          <button
            type="submit"
            disabled={saving}
            className="font-display text-lg tracking-wide rounded bg-ink text-chalk px-4 py-2 hover:bg-net disabled:opacity-50"
          >
            {saving ? "Saving…" : isEditing ? "Save changes" : "Add match"}
          </button>
          {isEditing && (
            <button
              type="button"
              onClick={cancelEdit}
              className="font-display text-lg tracking-wide rounded border border-ink/30 text-ink px-4 py-2 hover:bg-ink/5"
            >
              Cancel
            </button>
          )}
        </div>
      </form>

      <div className="flex flex-wrap items-end gap-3 court-line pb-4 mb-4">
        <label className="flex flex-col gap-1">
          <span className="font-display text-sm tracking-wide text-net">
            From
          </span>
          <input
            type="date"
            value={range.start}
            onChange={(e) => setRange((r) => ({ ...r, start: e.target.value }))}
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
      </div>

      {loadError && (
        <p className="rounded border border-matchpoint bg-matchpoint/10 px-4 py-3 text-matchpoint">
          {loadError}
        </p>
      )}

      {!loadError && !matches && (
        <p className="font-mono-nums text-wetsand">Loading matches&hellip;</p>
      )}

      {!loadError && matches && matches.length === 0 && (
        <p className="rounded border border-dashed border-wetsand px-4 py-8 text-center text-net">
          No matches in this range yet.
        </p>
      )}

      {!loadError && matches && matches.length > 0 && (
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

              <div className="flex gap-2 shrink-0">
                <button
                  onClick={() => startEdit(match)}
                  className="font-display text-sm tracking-wide rounded border border-ink/30 text-ink px-3 py-1 hover:bg-ink/5"
                >
                  Edit
                </button>
                <button
                  onClick={() => handleDelete(match)}
                  className="font-display text-sm tracking-wide rounded border border-matchpoint text-matchpoint px-3 py-1 hover:bg-matchpoint/10"
                >
                  Delete
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
