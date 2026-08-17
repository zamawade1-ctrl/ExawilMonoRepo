import { useMemo } from 'react';
import { useUsers } from '../features/admin/useUsers';
import { planPrice } from '../lib/plan';
import { PageHeader } from '../components/PageHeader';

/**
 * Admin billing view: every customer who has paid (has a plan kind), most recent
 * payment first, with the amount their plan kind maps to and total revenue.
 */
export function BillingPage() {
  const { users, loading, error, reload } = useUsers();

  const rows = useMemo(() => {
    return users
      .filter((u) => u.role.toLowerCase() !== 'admin' && u.planKind)
      .map((u) => ({
        user: u,
        // Prefer the exact price stored at redemption (0 = free plan, e.g. free-unlimited); fall back
        // to the label-derived price only for legacy/unpriced codes that predate PlanPriceUsd.
        price: u.planPriceUsd ?? planPrice(u.planKind),
        paidAt: u.planStartedAtUtc ?? u.lastModifiedAtUtc ?? u.createdAtUtc,
      }))
      .sort((a, b) => new Date(b.paidAt).getTime() - new Date(a.paidAt).getTime());
  }, [users]);

  const total = rows.reduce((sum, r) => sum + (r.price ?? 0), 0);

  return (
    <>
      <PageHeader
        title="Billing"
        subtitle="Customers who have paid, most recent first."
        action={
          <button className="btn btn-ghost" onClick={() => reload()}>
            Refresh
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
        <>
          <div className="stat-grid">
            <div className="stat-card stat-pro">
              <span className="stat-value">{rows.length}</span>
              <span className="stat-label">Paying customers</span>
            </div>
            <div className="stat-card stat-neutral">
              <span className="stat-value">${total}</span>
              <span className="stat-label">Total collected</span>
            </div>
          </div>

          <div className="table-card">
            <table className="datatable">
              <thead>
                <tr>
                  <th>
                    <span className="th-sort">Customer</span>
                  </th>
                  <th>
                    <span className="th-sort">Phone</span>
                  </th>
                  <th>
                    <span className="th-sort">Plan</span>
                  </th>
                  <th>
                    <span className="th-sort">Amount</span>
                  </th>
                  <th>
                    <span className="th-sort">Paid</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 ? (
                  <tr>
                    <td colSpan={5} className="table-empty">
                      No payments recorded yet.
                    </td>
                  </tr>
                ) : (
                  rows.map(({ user, price, paidAt }) => (
                    <tr key={user.userId}>
                      <td className="cell-name">{user.fullName || '—'}</td>
                      <td className="muted">{user.phone ?? '—'}</td>
                      <td>
                        <span className="badge badge-pro">{user.planKind}</span>
                      </td>
                      <td>{price !== null ? `$${price}` : '—'}</td>
                      <td className="muted">{fmtDate(paidAt)}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </>
      )}
    </>
  );
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
}
