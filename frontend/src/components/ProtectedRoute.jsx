import { Navigate, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";

// Client-side gate only — hides admin UI from viewers and bounces expired
// sessions to /login. Every admin API call is still independently checked
// by the Lambda authorizer server-side.
export default function ProtectedRoute({ children }) {
  const { isAdmin } = useAuth();
  const location = useLocation();

  if (!isAdmin) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return children;
}
