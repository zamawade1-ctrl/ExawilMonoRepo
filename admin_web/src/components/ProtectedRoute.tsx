import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';

/**
 * Route guard: only an authenticated **Admin** may reach the console. Anyone else
 * is redirected to /sign-in. This is a UX gate, not the security boundary — the
 * backend role-gates every /api/admin call, so the token, not this component, is
 * what actually protects the data.
 */
export function ProtectedRoute() {
  const user = useAuthStore((s) => s.user);
  const location = useLocation();

  if (!user || user.role.toLowerCase() !== 'admin') {
    return <Navigate to="/sign-in" replace state={{ from: location.pathname }} />;
  }

  return <Outlet />;
}
