import { useEffect } from 'react';
import {
  createBrowserRouter,
  Navigate,
  RouterProvider,
} from 'react-router-dom';
import { useAuthStore } from './store/auth';
import { useThemeStore } from './store/theme';
import { ProtectedRoute } from './components/ProtectedRoute';
import { AdminLayout } from './components/AdminLayout';
import { SignInPage } from './pages/SignInPage';
import { DashboardPage } from './pages/DashboardPage';
import { UsersPage } from './pages/UsersPage';
import { BillingPage } from './pages/BillingPage';
import { GenerateCodePage } from './pages/GenerateCodePage';

const router = createBrowserRouter([
  { path: '/sign-in', element: <SignInPage /> },
  {
    element: <ProtectedRoute />,
    children: [
      {
        element: <AdminLayout />,
        children: [
          { path: '/', element: <Navigate to="/dashboard" replace /> },
          { path: '/dashboard', element: <DashboardPage /> },
          { path: '/users', element: <UsersPage /> },
          { path: '/billing', element: <BillingPage /> },
          { path: '/codes', element: <GenerateCodePage /> },
        ],
      },
    ],
  },
  { path: '*', element: <Navigate to="/dashboard" replace /> },
]);

export function App() {
  const hydrate = useAuthStore((s) => s.hydrate);
  const ready = useAuthStore((s) => s.ready);
  const initTheme = useThemeStore((s) => s.init);

  // Rehydrate the session from sessionStorage once, before the router renders,
  // so a page refresh doesn't bounce an authenticated admin to /sign-in.
  useEffect(() => {
    hydrate();
    initTheme();
  }, [hydrate, initTheme]);

  if (!ready) {
    return (
      <div className="app-loading">
        <div className="spinner" />
      </div>
    );
  }

  return <RouterProvider router={router} />;
}
