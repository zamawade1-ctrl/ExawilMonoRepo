import { useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import { useThemeStore } from '../store/theme';
import { Logo } from './Logo';
import { ToastProvider } from './Toast';

const NAV = [
  { to: '/dashboard', label: 'Dashboard', icon: DashboardIcon },
  { to: '/users', label: 'Users', icon: UsersIcon },
  { to: '/billing', label: 'Billing', icon: BillingIcon },
  { to: '/codes', label: 'Activation codes', icon: KeyIcon },
];

/**
 * The signed-in admin frame. Desktop: a fixed brand sidebar + scrolling content.
 * Mobile / installed-PWA: a compact top bar with the account menu + a native-feeling
 * bottom navigation bar. Both surfaces share the same account menu markup — CSS
 * shows only the one that fits the current breakpoint.
 */
export function AdminLayout() {
  const user = useAuthStore((s) => s.user);
  const signOut = useAuthStore((s) => s.signOut);
  const theme = useThemeStore((s) => s.theme);
  const toggleTheme = useThemeStore((s) => s.toggle);
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);

  const initials = (user?.fullName || 'A')
    .split(' ')
    .map((p) => p[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

  const accountMenu = menuOpen && (
    <>
      <div className="menu-scrim" onClick={() => setMenuOpen(false)} />
      <div className="menu menu-up" role="menu">
        <button
          role="menuitem"
          onClick={() => {
            toggleTheme();
          }}
        >
          {theme === 'dark' ? '☀️  Light mode' : '🌙  Dark mode'}
        </button>
        <button
          role="menuitem"
          onClick={() => {
            setMenuOpen(false);
            navigate('/dashboard');
          }}
        >
          Settings
        </button>
        <div className="menu-divider" />
        <button
          role="menuitem"
          className="menu-danger"
          onClick={() => {
            signOut();
            navigate('/sign-in', { replace: true });
          }}
        >
          <LogoutIcon /> Sign out
        </button>
      </div>
    </>
  );

  return (
    <ToastProvider>
      <div className="admin-shell">
        {/* ---- Desktop sidebar ------------------------------------------- */}
        <aside className="sidebar">
          <div className="sidebar-brand">
            <Logo size={42} />
            <div className="sidebar-brand-text">
              <span className="brand-name">e-Xawil</span>
              <span className="brand-sub">Admin console</span>
            </div>
          </div>

          <nav className="sidebar-nav">
            {NAV.map(({ to, label, icon: Icon }) => (
              <NavLink
                key={to}
                to={to}
                className={({ isActive }) =>
                  `nav-item${isActive ? ' nav-item-active' : ''}`
                }
              >
                <Icon />
                <span>{label}</span>
              </NavLink>
            ))}
          </nav>

          <div className="sidebar-footer">
            <div className="menu-anchor">
              <button
                type="button"
                className="sidebar-user sidebar-user-btn"
                onClick={() => setMenuOpen((o) => !o)}
                aria-haspopup="menu"
                aria-expanded={menuOpen}
              >
                <div className="avatar">{initials}</div>
                <div className="sidebar-user-text">
                  <span className="sidebar-user-name">{user?.fullName}</span>
                  <span className="sidebar-user-role">Administrator</span>
                </div>
                <span className="sidebar-user-caret">⋯</span>
              </button>
              {accountMenu}
            </div>
          </div>
        </aside>

        {/* ---- Mobile top bar -------------------------------------------- */}
        <header className="mobile-topbar">
          <div className="mobile-topbar-brand">
            <Logo size={30} />
            <span className="brand-name">e-Xawil</span>
          </div>
          <div className="menu-anchor">
            <button
              type="button"
              className="mobile-account-btn"
              onClick={() => setMenuOpen((o) => !o)}
              aria-haspopup="menu"
              aria-expanded={menuOpen}
              aria-label="Account menu"
            >
              <div className="avatar">{initials}</div>
            </button>
            {accountMenu}
          </div>
        </header>

        {/* ---- Routed content -------------------------------------------- */}
        <main className="content">
          <Outlet />
        </main>

        {/* ---- Mobile bottom navigation ---------------------------------- */}
        <nav className="bottom-nav" aria-label="Primary">
          {NAV.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `bottom-nav-item${isActive ? ' bottom-nav-item-active' : ''}`
              }
            >
              <Icon />
              <span>{label === 'Activation codes' ? 'Codes' : label}</span>
            </NavLink>
          ))}
        </nav>
      </div>
    </ToastProvider>
  );
}

// --- Minimal inline icons (no icon dependency) ------------------------------

function DashboardIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon" aria-hidden>
      <path
        fill="currentColor"
        d="M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z"
      />
    </svg>
  );
}
function UsersIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon" aria-hidden>
      <path
        fill="currentColor"
        d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3Zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3Zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5C15 14.17 10.33 13 8 13Zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5Z"
      />
    </svg>
  );
}
function BillingIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon" aria-hidden>
      <path
        fill="currentColor"
        d="M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2Zm0 14H4v-6h16v6Zm0-10H4V6h16v2Z"
      />
    </svg>
  );
}
function KeyIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon" aria-hidden>
      <path
        fill="currentColor"
        d="M12.65 10A5.99 5.99 0 0 0 7 6a6 6 0 1 0 5.65 8H17v4h4v-4h2v-4H12.65ZM7 14a2 2 0 1 1 0-4 2 2 0 0 1 0 4Z"
      />
    </svg>
  );
}
function LogoutIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon" aria-hidden>
      <path
        fill="currentColor"
        d="M17 7l-1.41 1.41L17.17 10H9v2h8.17l-1.58 1.58L17 15l4-4-4-4ZM5 5h7V3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h7v-2H5V5Z"
      />
    </svg>
  );
}
