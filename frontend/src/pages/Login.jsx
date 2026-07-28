import { useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { ApiError } from "../api/client";

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [submitting, setSubmitting] = useState(false);

  const redirectTo = location.state?.from?.pathname || "/";

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await login(email, password);
      navigate(redirectTo, { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Couldn't log in.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-sm px-4 py-16">
      <h1 className="font-display text-4xl text-ink mb-6">Admin Log In</h1>
      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <label className="flex flex-col gap-1">
          <span className="font-display text-sm tracking-wide text-net">Email</span>
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="rounded border border-ink/30 bg-chalk px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
          />
        </label>
        <label className="flex flex-col gap-1">
          <span className="font-display text-sm tracking-wide text-net">Password</span>
          <input
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="rounded border border-ink/30 bg-chalk px-3 py-2 text-ink focus:outline-none focus:ring-2 focus:ring-net"
          />
        </label>

        {error && (
          <p className="rounded border border-matchpoint bg-matchpoint/10 px-3 py-2 text-sm text-matchpoint">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="font-display text-lg tracking-wide rounded bg-ink text-chalk py-2 hover:bg-net disabled:opacity-50"
        >
          {submitting ? "Logging in…" : "Log In"}
        </button>
      </form>
    </div>
  );
}
