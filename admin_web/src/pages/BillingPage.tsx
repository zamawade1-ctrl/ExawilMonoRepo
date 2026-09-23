import { useEffect, useMemo, useState } from 'react';
import { useUsers } from '../features/admin/useUsers';
import { planPrice } from '../lib/plan';
import type { AdminUser } from '../lib/schemas';
import { PageHeader } from '../components/PageHeader';

/** How the billing is grouped/filtered: by calendar month or by individual day. */
type Granularity = 'month' | 'day';

const PAGE_SIZE = 10;

/** One customer's payment, derived from their current paid plan. */
interface Payment {
  user: AdminUser;
  /** USD billed. null = legacy/unpriced code (shown as "—", counted as 0 in revenue). */
  price: number | null;
  paidAt: string;
  /** ms timestamp of paidAt (NaN-safe: invalid dates sort to the bottom). */
  paidAtMs: number;
}

/** One grouped period (a month or a day) with its payment count + revenue. */
interface PeriodGroup {
  key: string;
  label: string;
  count: number;
  revenue: number;
}

/**
 * Admin billing view. Shows revenue broken down PER MONTH (or per day) and the
 * PER-USER payments behind it. The admin can switch the grouping between months
 * and days and narrow to a single month/day; the payments table is paginated.
 */
export function BillingPage() {
  const { users, loading, error, reload } = useUsers();

  const [granularity, setGranularity] = useState<Granularity>('month');
  // The selected period: 'YYYY-MM' in month mode, 'YYYY-MM-DD' in day mode. Empty = all.
  const [period, setPeriod] = useState('');
  const [page, setPage] = useState(1);

  // Every paying customer → one payment. (Free plans, priced at 0, are included so
  // the counts match "who has a plan"; they simply add nothing to revenue.)
  const payments = useMemo<Payment[]>(() => {
    return users
      .filter((u) => u.role.toLowerCase() !== 'admin' && u.planKind)
      .map((u) => {
        const paidAt = u.planStartedAtUtc ?? u.lastModifiedAtUtc ?? u.createdAtUtc;
        return {
          user: u,
          // Prefer the exact price stored at redemption (0 = free plan); fall back to the
          // label-derived price only for legacy/unpriced codes that predate PlanPriceUsd.
          price: u.planPriceUsd ?? planPrice(u.planKind),
          paidAt,
          paidAtMs: new Date(paidAt).getTime(),
        };
      });
  }, [users]);

  // Filter to the selected month/day (if any), matched on the LOCAL calendar so it
  // agrees with the dates shown in the table.
  const filtered = useMemo(() => {
    if (!period) return payments;
    return payments.filter((p) => {
      if (Number.isNaN(p.paidAtMs)) return false;
      const key = granularity === 'month' ? monthKey(p.paidAtMs) : dayKey(p.paidAtMs);
      return key === period;
    });
  }, [payments, period, granularity]);

  // Group the filtered payments per period (month or day), most recent first — this
  // is the "billing per month / per day" breakdown.
  const breakdown = useMemo<PeriodGroup[]>(() => {
    const byKey = new Map<string, PeriodGroup>();
    for (const p of filtered) {
      if (Number.isNaN(p.paidAtMs)) continue;
      const key = granularity === 'month' ? monthKey(p.paidAtMs) : dayKey(p.paidAtMs);
      const label = granularity === 'month' ? monthLabel(p.paidAtMs) : dayLabel(p.paidAtMs);
      const g = byKey.get(key) ?? { key, label, count: 0, revenue: 0 };
      g.count += 1;
      g.revenue += p.price ?? 0;
      byKey.set(key, g);
    }
    return [...byKey.values()].sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
  }, [filtered, granularity]);

  // Payments table rows, most recent payment first.
  const rows = useMemo(
    () => [...filtered].sort((a, b) => b.paidAtMs - a.paidAtMs),
    [filtered],
  );

  // Distinct periods present in the data, for the quick-pick dropdown.
  const periodOptions = useMemo(() => {
    const seen = new Map<string, string>();
    for (const p of payments) {
      if (Number.isNaN(p.paidAtMs)) continue;
      const key = granularity === 'month' ? monthKey(p.paidAtMs) : dayKey(p.paidAtMs);
      const label = granularity === 'month' ? monthLabel(p.paidAtMs) : dayLabel(p.paidAtMs);
      if (!seen.has(key)) seen.set(key, label);
    }
    return [...seen.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0))
      .map(([key, label]) => ({ key, label }));
  }, [payments, granularity]);

  // Reset paging + the chosen period whenever the grouping or result set changes shape.
  useEffect(() => setPage(1), [period, granularity, rows.length]);

  const total = rows.reduce((sum, r) => sum + (r.price ?? 0), 0);
  const totalPages = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  const clampedPage = Math.min(page, totalPages);
  const pageRows = rows.slice((clampedPage - 1) * PAGE_SIZE, clampedPage * PAGE_SIZE);

  function switchGranularity(next: Granularity) {
    if (next === granularity) return;
    setGranularity(next);
    // A 'YYYY-MM' value isn't valid for a date input (and vice-versa), so clear it.
    setPeriod('');
  }

  return (
    <>
      <PageHeader
        title="Billing"
        subtitle="Revenue per month, and the payments behind it."
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
          <div className="toolbar billing-toolbar">
            <div className="billing-filter">
              <span className="billing-filter-label">Group by</span>
              <div className="segmented">
                <button
                  className={`segment${granularity === 'month' ? ' segment-active' : ''}`}
                  onClick={() => switchGranularity('month')}
                >
                  Month
                </button>
                <button
                  className={`segment${granularity === 'day' ? ' segment-active' : ''}`}
                  onClick={() => switchGranularity('day')}
                >
                  Day
                </button>
              </div>
            </div>

            <div className="billing-filter">
              <span className="billing-filter-label">
                {granularity === 'month' ? 'Month' : 'Day'}
              </span>
              <input
                className="period-input"
                type={granularity === 'month' ? 'month' : 'date'}
                value={period}
                onChange={(e) => setPeriod(e.target.value)}
                aria-label={granularity === 'month' ? 'Filter by month' : 'Filter by day'}
              />
              {periodOptions.length > 0 && (
                <select
                  className="period-input period-quick"
                  value={period}
                  onChange={(e) => setPeriod(e.target.value)}
                  aria-label="Quick pick a period"
                >
                  <option value="">All {granularity === 'month' ? 'months' : 'days'}</option>
                  {periodOptions.map((o) => (
                    <option key={o.key} value={o.key}>
                      {o.label}
                    </option>
                  ))}
                </select>
              )}
              {period && (
                <button className="btn btn-ghost btn-sm" onClick={() => setPeriod('')}>
                  Clear
                </button>
              )}
            </div>
          </div>

          <div className="stat-grid">
            <div className="stat-card stat-pro">
              <span className="stat-value">{rows.length}</span>
              <span className="stat-label">
                Payments{period ? ' in period' : ''}
              </span>
            </div>
            <div className="stat-card stat-neutral">
              <span className="stat-value">${total}</span>
              <span className="stat-label">
                Revenue{period ? ' in period' : ''}
              </span>
            </div>
            <div className="stat-card stat-neutral">
              <span className="stat-value">{breakdown.length}</span>
              <span className="stat-label">
                {granularity === 'month' ? 'Months' : 'Days'} with revenue
              </span>
            </div>
          </div>

          {/* Per-period breakdown — "billing per month" (or per day). */}
          <h3 className="billing-section-title">
            Revenue by {granularity === 'month' ? 'month' : 'day'}
          </h3>
          <div className="table-card">
            <table className="datatable">
              <thead>
                <tr>
                  <th>
                    <span className="th-sort">{granularity === 'month' ? 'Month' : 'Day'}</span>
                  </th>
                  <th>
                    <span className="th-sort">Payments</span>
                  </th>
                  <th>
                    <span className="th-sort">Revenue</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {breakdown.length === 0 ? (
                  <tr>
                    <td colSpan={3} className="table-empty">
                      No payments in this range.
                    </td>
                  </tr>
                ) : (
                  breakdown.map((g) => (
                    <tr key={g.key}>
                      <td className="cell-name">{g.label}</td>
                      <td className="muted">{g.count}</td>
                      <td>${g.revenue}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          {/* Per-user payments. */}
          <h3 className="billing-section-title">Payments</h3>
          <div className="table-card">
            <div className="table-scroll">
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
                  {pageRows.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="table-empty">
                        No payments recorded yet.
                      </td>
                    </tr>
                  ) : (
                    pageRows.map(({ user, price, paidAt }) => (
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

            <div className="pagination">
              <span className="pagination-info">
                {rows.length === 0
                  ? '0 payments'
                  : `${(clampedPage - 1) * PAGE_SIZE + 1}–${Math.min(
                      clampedPage * PAGE_SIZE,
                      rows.length,
                    )} of ${rows.length}`}
              </span>
              <div className="pagination-controls">
                <button
                  className="btn btn-ghost btn-sm"
                  disabled={clampedPage <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                >
                  Prev
                </button>
                <span className="pagination-page">
                  Page {clampedPage} / {totalPages}
                </span>
                <button
                  className="btn btn-ghost btn-sm"
                  disabled={clampedPage >= totalPages}
                  onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                >
                  Next
                </button>
              </div>
            </div>
          </div>
        </>
      )}
    </>
  );
}

// ---- Period keys + labels (local calendar, to match the displayed dates) ------

function pad2(n: number): string {
  return n.toString().padStart(2, '0');
}

/** 'YYYY-MM' for the local month of a timestamp. */
function monthKey(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
}

/** 'YYYY-MM-DD' for the local day of a timestamp. */
function dayKey(ms: number): string {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function monthLabel(ms: number): string {
  return new Date(ms).toLocaleDateString(undefined, { year: 'numeric', month: 'long' });
}

function dayLabel(ms: number): string {
  return new Date(ms).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
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
