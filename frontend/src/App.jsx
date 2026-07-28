import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "./context/AuthContext";
import ProtectedRoute from "./components/ProtectedRoute";
import Nav from "./components/Nav";
import Ranking from "./pages/Ranking";
import Matches from "./pages/Matches";
import Login from "./pages/Login";
import AdminUsers from "./pages/admin/AdminUsers";
import AdminMatches from "./pages/admin/AdminMatches";

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Nav />
        <Routes>
          <Route path="/" element={<Ranking />} />
          <Route path="/matches" element={<Matches />} />
          <Route path="/login" element={<Login />} />
          <Route
            path="/admin/users"
            element={
              <ProtectedRoute>
                <AdminUsers />
              </ProtectedRoute>
            }
          />
          <Route
            path="/admin/matches"
            element={
              <ProtectedRoute>
                <AdminMatches />
              </ProtectedRoute>
            }
          />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
