import { createContext, useContext, useEffect, useMemo, useState } from "react";
import { api } from "../api/client";

const AuthContext = createContext(null);
const STORAGE_KEY = "asc-ftv-rank:token";

// Client-side JWT decode for UI purposes only (e.g. showing the admin nav
// link, pre-empting an obviously-expired token). This is NOT a security
// boundary — the Lambda authorizer is the actual enforcement point for
// every admin route, exactly as it should be.
function decodeToken(token) {
  try {
    const payload = token.split(".")[1];
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json);
  } catch {
    return null;
  }
}

export function AuthProvider({ children }) {
  const [token, setToken] = useState(() => localStorage.getItem(STORAGE_KEY));

  const claims = useMemo(() => (token ? decodeToken(token) : null), [token]);

  const isExpired = claims?.exp ? claims.exp * 1000 < Date.now() : false;
  const isAuthenticated = Boolean(token && claims && !isExpired);
  const isAdmin = isAuthenticated && Boolean(claims.is_admin);

  useEffect(() => {
    if (token && (!claims || isExpired)) {
      // Stale/corrupt/expired token left over in storage — clear it so the
      // UI doesn't think it's logged in.
      localStorage.removeItem(STORAGE_KEY);
      setToken(null);
    }
  }, [token, claims, isExpired]);

  async function login(email, password) {
    const { token: newToken } = await api.login(email, password);
    localStorage.setItem(STORAGE_KEY, newToken);
    setToken(newToken);
  }

  function logout() {
    localStorage.removeItem(STORAGE_KEY);
    setToken(null);
  }

  const value = { token, claims, isAuthenticated, isAdmin, login, logout };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within an AuthProvider");
  return ctx;
}
