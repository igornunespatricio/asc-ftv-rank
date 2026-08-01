import { useState } from "react";
import { NavLink } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

const linkClass = ({ isActive }) =>
  `font-display text-lg tracking-wide px-3 py-1.5 rounded transition-colors ${
    isActive ? "bg-ink text-chalk" : "text-ink hover:bg-ink/10"
  }`;

const mobileLinkClass = ({ isActive }) =>
  `font-display text-lg tracking-wide px-3 py-2 rounded transition-colors block ${
    isActive ? "bg-ink text-chalk" : "text-ink hover:bg-ink/10"
  }`;

const ENV_LABELS = {
  dev: { label: "DEV", className: "bg-amber-400 text-ink" },
  test: { label: "TEST", className: "bg-sky-400 text-ink" },
};

export default function Nav() {
  const { isAdmin, logout } = useAuth();
  const env = import.meta.env.VITE_APP_ENV;
  const badge = ENV_LABELS[env];
  const [open, setOpen] = useState(false);

  return (
    <header className="border-b-2 border-ink bg-chalk">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
        <NavLink
          to="/"
          className="flex items-center gap-2"
          onClick={() => setOpen(false)}
        >
          <span className="font-display text-2xl text-ink">
            ASC FTV<span className="text-matchpoint">.</span>
          </span>
          {badge && (
            <span
              className={`text-xs font-bold px-1.5 py-0.5 rounded ${badge.className}`}
            >
              {badge.label}
            </span>
          )}
        </NavLink>

        {/* Desktop nav — hidden below sm: */}
        <nav className="hidden sm:flex items-center gap-1">
          <NavLink to="/" end className={linkClass}>
            Ranking
          </NavLink>
          <NavLink to="/matches" className={linkClass}>
            Matches
          </NavLink>
          {isAdmin ? (
            <>
              <NavLink to="/admin/matches" className={linkClass}>
                Manage Matches
              </NavLink>
              <NavLink to="/admin/users" className={linkClass}>
                Manage Users
              </NavLink>
              <button
                onClick={logout}
                className="font-display text-lg tracking-wide px-3 py-1.5 rounded text-matchpoint hover:bg-matchpoint/10"
              >
                Log Out
              </button>
            </>
          ) : (
            <NavLink to="/login" className={linkClass}>
              Admin Log In
            </NavLink>
          )}
        </nav>

        {/* Mobile toggle — hidden at sm: and above */}
        <button
          onClick={() => setOpen((v) => !v)}
          aria-label="Toggle menu"
          aria-expanded={open}
          className="sm:hidden flex flex-col justify-center gap-1.5 w-9 h-9 items-center"
        >
          <span
            className={`block h-0.5 w-6 bg-ink transition-transform ${
              open ? "translate-y-2 rotate-45" : ""
            }`}
          />
          <span
            className={`block h-0.5 w-6 bg-ink transition-opacity ${
              open ? "opacity-0" : ""
            }`}
          />
          <span
            className={`block h-0.5 w-6 bg-ink transition-transform ${
              open ? "-translate-y-2 -rotate-45" : ""
            }`}
          />
        </button>
      </div>

      {/* Mobile menu — collapses below sm: */}
      {open && (
        <nav className="sm:hidden flex flex-col gap-1 px-4 pb-4 court-line pt-2">
          <NavLink
            to="/"
            end
            className={mobileLinkClass}
            onClick={() => setOpen(false)}
          >
            Ranking
          </NavLink>
          <NavLink
            to="/matches"
            className={mobileLinkClass}
            onClick={() => setOpen(false)}
          >
            Matches
          </NavLink>
          {isAdmin ? (
            <>
              <NavLink
                to="/admin/matches"
                className={mobileLinkClass}
                onClick={() => setOpen(false)}
              >
                Manage Matches
              </NavLink>
              <NavLink
                to="/admin/users"
                className={mobileLinkClass}
                onClick={() => setOpen(false)}
              >
                Manage Users
              </NavLink>
              <button
                onClick={() => {
                  setOpen(false);
                  logout();
                }}
                className="font-display text-lg tracking-wide px-3 py-2 rounded text-matchpoint hover:bg-matchpoint/10 text-left"
              >
                Log Out
              </button>
            </>
          ) : (
            <NavLink
              to="/login"
              className={mobileLinkClass}
              onClick={() => setOpen(false)}
            >
              Admin Log In
            </NavLink>
          )}
        </nav>
      )}
    </header>
  );
}
