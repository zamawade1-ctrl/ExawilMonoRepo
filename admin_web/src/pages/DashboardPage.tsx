import { useMemo } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useUsers } from '../features/admin/useUsers';
import { planRemainingMs, planState } from '../lib/plan';
import type { AdminUser } from '../lib/schemas';
import { PageHeader } from '../components/PageHeader';

const DAY_MS = 24 * 60 * 60 * 1000;
/** Plans ending within this window show up on the "Expiring soon" watchlist. */
const EXPIRING_WINDOW_MS = 7 * DAY_MS;

/**
 * Admin dashboard: at-a-glance totals + plan distribution + recent sign-ups on
 * the left, and a right rail (quick actions + an "Expiring soon" watchlist) that
 * puts the wide-screen right-hand space to work. Admin accounts are excluded from
 * the customer figures, matching the mobile console.
 */
export function DashboardPage() {
  const { users, fetchedAt, loading, refreshing, error, reload } = useUsers();
  const navigate = useNavigate();

  const stats = useMemo(() => {
    const customers = users.filter((u) => u.role.toLowerCase() !== 'admin');
    let pro = 0;
    let trial = 0;
    let expired = 0;
    let withDevice = 0;
    for (const u of customers) {
      const s = planState(u.plan, fetchedAt);
      if (s === 'pro') pro++;
      else if (s === 'trial') trial++;
      else expired++;
      if (u.hasDevice) withDevice++;
    }
    return { total: customers.length, active: pro + trial, pro, trial, expired, withDevice, customers };
  }, [users, fetchedAt]);

  const recent = useMemo(
    () =>
      [...stats.customers]
        .sort(
          (a, b) =>
            new Date(b.createdAtUtc).getTime() - new Date(a.createdAtUtc).getTime(),
        )
        .slice(0, 6),
    [stats.customers],
  );

  // Active plans (pro/trial) ending within the window, soonest first.
  const expiringSoon = useMemo(
    () =>
      stats.customers
        .map((u) => ({ user: u, left: planRemainingMs(u.plan, fetchedAt) }))
        .filter(({ user, left }) => {
          const s = planState(user.plan, fetchedAt);
          return s !== 'expired' && left > 0 && left <= EXPIRING_WINDOW_MS;
        })
        .sort((a, b) => a.left - b.left)
        .slice(0, 6),
    [stats.customers, fetchedAt],
  );

  return (
    <>
      <PageHeader
        title="Dashboard"
        subtitle="Overview of accounts and plan health."
        action={
          <button
            className="btn btn-ghost"
            onClick={() => reload()}
            disabled={refreshing}
          >
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </button>
        }
      />

      {error ? (
        <div className="alert alert-error">{error}</div>
      ) : loading && users.length === 0 ? (
        <div className="page-loading">
          <span className="spinner" />
        </div>
      ) : (
        <div className="dashboard-layout">
          <div className="dashboard-main">
            <div className="stat-grid">
              <StatCard label="Total customers" value={stats.total} tone="neutral" />
              <StatCard label="Active plans" value={stats.active} tone="pro" />
              <StatCard label="On Pro" value={stats.pro} tone="pro" />
              <StatCard label="On trial" value={stats.trial} tone="trial" />
              <StatCard label="Expired" value={stats.expired} tone="expired" />
              <StatCard label="Devices bound" value={stats.withDevice} tone="neutral" />
            </div>

            <div className="panel">
              <div className="panel-head">
                <h3>Plan distribution</h3>
              </div>
              <DistributionBar pro={stats.pro} trial={stats.trial} expired={stats.expired} />
            </div>

            <div className="panel">
              <div className="panel-head">
                <h3>Recent sign-ups</h3>
                <Link to="/users" className="link">
                  View all users →
                </Link>
              </div>
              {recent.length === 0 ? (
                <p className="empty">No customers yet.</p>
              ) : (
                <table className="table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Phone</th>
                      <th>Joined</th>
                    </tr>
                  </thead>
                  <tbody>
                    {recent.map((u) => (
                      <tr key={u.userId}>
                        <td>{u.fullName || '—'}</td>
                        <td className="muted">{u.phone ?? '—'}</td>
                        <td className="muted">{fmtDate(u.createdAtUtc)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>

          {/* Right rail — quick actions + expiring-soon watchlist */}
          <aside className="dashboard-rail">
            <div className="rail-card">
              <h3 className="rail-title">Quick actions</h3>
              <button
                className="btn btn-primary btn-block"
                onClick={() => navigate('/codes')}
              >
                Generate activation code
              </button>
              <button
                className="btn btn-ghost btn-block"
                onClick={() => navigate('/users')}
              >
                Manage users
              </button>
            </div>

            <div className="rail-card">
              <h3 className="rail-title">Expiring soon</h3>
              <p className="rail-sub">Active plans ending within 7 days.</p>
              {expiringSoon.length === 0 ? (
                <p className="rail-empty">All active plans are healthy. ✓</p>
              ) : (
                <ul className="expiry-list">
                  {expiringSoon.map(({ user, left }) => (
                    <ExpiryRow
                      key={user.userId}
                      user={user}
                      left={left}
                      onClick={() =>
                        navigate(`/users?phone=${encodeURIComponent(user.phone ?? '')}`)
                      }
                    />
                  ))}
                </ul>
              )}
            </div>
          </aside>
        </div>
      )}
    </>
  );
}

function ExpiryRow({
  user,
  left,
  onClick,
}: {
  user: AdminUser;
  left: number;
  onClick: () => void;
}) {
  return (
    <li>
      <button className="expiry-row" onClick={onClick}>
        <span className="expiry-name">
          <span className="expiry-name-text">{user.fullName || '—'}</span>
          <span className="expiry-phone">{user.phone ?? '—'}</span>
        </span>
        <span className="expiry-left">{shortLeft(left)}</span>
      </button>
    </li>
  );
}

function StatCard({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: 'neutral' | 'pro' | 'trial' | 'expired';
}) {
  return (
    <div className={`stat-card stat-${tone}`}>
      <span className="stat-value">{value}</span>
      <span className="stat-label">{label}</span>
    </div>
  );
}

function DistributionBar({
  pro,
  trial,
  expired,
}: {
  pro: number;
  trial: number;
  expired: number;
}) {
  const total = Math.max(1, pro + trial + expired);
  const seg = (n: number) => `${(n / total) * 100}%`;
  return (
    <>
      <div className="dist-bar">
        {pro > 0 && <span className="dist-seg badge-pro" style={{ width: seg(pro) }} />}
        {trial > 0 && (
          <span className="dist-seg badge-trial" style={{ width: seg(trial) }} />
        )}
        {expired > 0 && (
          <span className="dist-seg badge-expired" style={{ width: seg(expired) }} />
        )}
      </div>
      <div className="dist-legend">
        <LegendDot className="badge-pro" label="Pro" value={pro} />
        <LegendDot className="badge-trial" label="Trial" value={trial} />
        <LegendDot className="badge-expired" label="Expired" value={expired} />
      </div>
    </>
  );
}

function LegendDot({
  className,
  label,
  value,
}: {
  className: string;
  label: string;
  value: number;
}) {
  return (
    <span className="legend-item">
      <span className={`legend-dot ${className}`} />
      {label} <strong>{value}</strong>
    </span>
  );
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function shortLeft(ms: number): string {
  const totalMin = Math.floor(ms / 60000);
  const days = Math.floor(totalMin / 1440);
  const hours = Math.floor((totalMin % 1440) / 60);
  if (days >= 1) return `${days}d ${hours}h`;
  const mins = totalMin % 60;
  return hours >= 1 ? `${hours}h ${mins}m` : `${mins}m`;
}
