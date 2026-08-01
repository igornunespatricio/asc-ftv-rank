import { useEffect, useRef, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import { api, ApiError } from "../../api/client";

// NOTE: field names (`name`, `email`, `status`, `is_admin`, `password`) and
// the `{ users: [...] }` response wrapper are ASSUMED, following the same
// wrapper convention as /matches and /ranking — pending confirmation
// against the actual `users` Lambda handler (not in context here, unlike
// the matches Lambda). Adjust `refreshUsers`/`handleSubmit` below once
// confirmed, same as the ranking param-name fix earlier.

const EMPTY_FORM = {
  id: null,
  name: "",
  email: "",
  status: true,
  is_admin: false,
  password: "",
};

export default function AdminUsers() {
  const { token } = useAuth();
  const [users, setUsers] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [formError, setFormError] = useState(null);
  const [saving, setSaving] = useState(false);
  const formRef = useRef(null);

  const isEditing = form.id !== null;

  async function refreshUsers() {
    try {
      const data = await api.getUsers(token);
      setUsers(data.users ?? data);
      setLoadError(null);
    } catch (err) {
      setLoadError(
        err instanceof ApiError ? err.message : "Couldn't load users.",
      );
    }
  }

  useEffect(() => {
    refreshUsers();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  function startEdit(user) {
    setForm({
      id: user.id,
      name: user.name,
      email: user.email,
      status: user.status,
      is_admin: user.is_admin,
      password: "",
    });
    setFormError(null);
    formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function cancelEdit() {
    setForm(EMPTY_FORM);
    setFormError(null);
  }

  async function handleDelete(user) {
    if (!confirm(`Delete ${user.name}? This can't be undone.`)) return;
    try {
      await api.deleteUser(token, user.id);
      if (form.id === user.id) cancelEdit();
      await refreshUsers();
    } catch (err) {
      setLoadError(
        err instanceof ApiError ? err.message : "Couldn't delete user.",
      );
    }
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setFormError(null);

    if (!form.name.trim()) {
      setFormError("Name is required.");
      return;
    }
    if (form.is_admin && !form.email.trim()) {
      setFormError("Email is required for admin users.");
      return;
    }
    if (form.is_admin && !isEditing && !form.password) {
      setFormError("A password is required for admin users.");
      return;
    }

    const payload = {
      name: form.name.trim(),
      status: form.status,
      is_admin: form.is_admin,
      // Only admins have an email (per the users Lambda — createUser/updateUser
      // never set email or password_hash on non-admin records), same reasoning
      // as the conditional password field below.
      ...(form.is_admin ? { email: form.email.trim() } : {}),
      // Blank password on edit means "leave unchanged" — omit it rather
      // than sending an empty string the backend would hash as-is.
      ...(form.password ? { password: form.password } : {}),
    };

    setSaving(true);
    try {
      if (isEditing) {
        await api.updateUser(token, form.id, payload);
      } else {
        await api.createUser(token, payload);
      }
      cancelEdit();
      await refreshUsers();
    } catch (err) {
      setFormError(
        err instanceof ApiError ? err.message : "Couldn't save user.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <h1 className="font-display text-4xl sm:text-5xl text-ink mb-6">
        Manage Users
      </h1>

      <form
        ref={formRef}
        onSubmit={handleSubmit}
        className="mb-8 rounded border border-ink/15 bg-chalk p-4 flex flex-col gap-3"
      >
        <p className="font-display text-lg tracking-wide text-net">
          {isEditing ? `Editing ${form.name}` : "Add a player"}
        </p>

        <div className="flex flex-wrap gap-3">
          <label className="flex flex-col gap-1 flex-1 min-w-[160px]">
            <span className="font-display text-sm tracking-wide text-net">
              Name
            </span>
            <input
              type="text"
              value={form.name}
              onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>

          {form.is_admin && (
            <label className="flex flex-col gap-1 flex-1 min-w-[160px]">
              <span className="font-display text-sm tracking-wide text-net">
                Email
              </span>
              <input
                type="email"
                value={form.email}
                onChange={(e) =>
                  setForm((f) => ({ ...f, email: e.target.value }))
                }
                className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
              />
            </label>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-6">
          <label className="flex items-center gap-2 font-display text-sm tracking-wide text-ink">
            <input
              type="checkbox"
              checked={form.status}
              onChange={(e) =>
                setForm((f) => ({ ...f, status: e.target.checked }))
              }
              className="h-4 w-4 accent-net"
            />
            Active (shows in match dropdowns)
          </label>

          <label className="flex items-center gap-2 font-display text-sm tracking-wide text-ink">
            <input
              type="checkbox"
              checked={form.is_admin}
              onChange={(e) =>
                setForm((f) => ({ ...f, is_admin: e.target.checked }))
              }
              className="h-4 w-4 accent-matchpoint"
            />
            Admin
          </label>
        </div>

        {form.is_admin && (
          <label className="flex flex-col gap-1 max-w-xs">
            <span className="font-display text-sm tracking-wide text-net">
              Password {isEditing && "(leave blank to keep current)"}
            </span>
            <input
              type="password"
              value={form.password}
              onChange={(e) =>
                setForm((f) => ({ ...f, password: e.target.value }))
              }
              className="rounded border border-ink/30 bg-white px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
            />
          </label>
        )}

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
            {saving ? "Saving…" : isEditing ? "Save changes" : "Add player"}
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

      {loadError && (
        <p className="rounded border border-matchpoint bg-matchpoint/10 px-4 py-3 text-matchpoint">
          {loadError}
        </p>
      )}

      {!loadError && !users && (
        <p className="font-mono-nums text-wetsand">Loading users&hellip;</p>
      )}

      {!loadError && users && users.length === 0 && (
        <p className="rounded border border-dashed border-wetsand px-4 py-8 text-center text-net">
          No players yet. Add one above to get started.
        </p>
      )}

      {!loadError && users && users.length > 0 && (
        <ul className="flex flex-col gap-2">
          {users.map((user) => (
            <li
              key={user.id}
              className="flex flex-wrap items-center gap-3 rounded bg-chalk border border-ink/15 px-4 py-3"
            >
              <div className="flex-1 min-w-0">
                <p className="font-display text-xl text-ink truncate">
                  {user.name}
                </p>
                <p className="font-mono-nums text-xs text-wetsand">
                  {user.email}
                </p>
              </div>

              <span
                className={`font-display text-xs tracking-wide px-2 py-1 rounded ${
                  user.status
                    ? "bg-net/10 text-net"
                    : "bg-wetsand/20 text-wetsand"
                }`}
              >
                {user.status ? "Active" : "Inactive"}
              </span>

              {user.is_admin && (
                <span className="font-display text-xs tracking-wide px-2 py-1 rounded bg-matchpoint/10 text-matchpoint">
                  Admin
                </span>
              )}

              <div className="flex gap-2">
                <button
                  onClick={() => startEdit(user)}
                  className="font-display text-sm tracking-wide rounded border border-ink/30 text-ink px-3 py-2 sm:py-1 hover:bg-ink/5"
                >
                  Edit
                </button>
                <button
                  onClick={() => handleDelete(user)}
                  className="font-display text-sm tracking-wide rounded border border-matchpoint text-matchpoint px-3 py-2 sm:py-1 hover:bg-matchpoint/10"
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
