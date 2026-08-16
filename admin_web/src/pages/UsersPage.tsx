import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useUsers } from '../features/admin/useUsers';
import {
  planBadge,
  planRemainingMs,
  planState,
  planView,
  type PlanState,
} from '../lib/plan';
import type { AdminUser } from '../lib/schemas';
import { UserDetailPanel } from '../components/UserDetailPanel';
import { PageHeader } from '../components/PageHeader';

type Filter = 'all' | PlanState;
type SortKey =
  | 'name'
  | 'phone'
  | 'device'
  | 'plan'
  | 'kind'
  | 'activation'
  | 'joined'
  | 'lastModified';
type SortDir = 'asc' | 'desc';

const FILTERS: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'pro', label: 'Pro' },
  { key: 'trial', label: 'Trial' },
  { key: 'expired', label: 'Expired' },
];

const PAGE_SIZE = 8;

const COLUMNS: { key: SortKey; label: string; className?: string }[] = [
  { key: 'name', label: 'Name' },
  { key: 'phone', label: 'Phone' },
  { key: 'device', label: 'Device' },
  { key: 'plan', label: 'Plan' },
  { key: 'kind', label: 'Plan kind' },
  { key: 'activation', label: 'Activation code' },
  { key: 'lastModified', label: 'Last edited' },
];

/**
 * User-management page: a sortable, paginated datatable of customers with search
 * (name / phone / device label) and plan filtering, plus a master-detail panel on
 * the right for the selected account (details + admin actions).
 */
export function UsersPage() {
  const { users, fetchedAt, loading, refreshing, error, reload } = useUsers();
  const navigate = useNavigate();

  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  // Default to the server's "most-recently-edited first" order.
  const [sort, setSort] = useState<{ key: SortKey; dir: SortDir }>({
    key: 'lastModified',
    dir: 'desc',
  });
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const customers = useMemo(
    () => users.filter((u) => u.role.toLowerCase() !== 'admin'),
    [users],
  );

  // Filter + search (search also matches the bound device label).
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return customers.filter((u) => {
      if (filter !== 'all' && planState(u.plan, fetchedAt) !== filter) return false;
      if (!q) return true;
      return (
        u.fullName.toLowerCase().includes(q) ||
        (u.phone ?? '').toLowerCase().includes(q) ||
        (u.deviceLabel ?? '').toLowerCase().includes(q)
      );
    });
  }, [customers, query, filter, fetchedAt]);

  // Sort.
  const sorted = useMemo(() => {
    const dir = sort.dir === 'asc' ? 1 : -1;
    const val = (u: AdminUser): string | number => {
      switch (sort.key) {
        case 'name':
          return u.fullName.toLowerCase();
        case 'phone':
          return u.phone ?? '';
        case 'device':
          return (u.deviceLabel ?? '').toLowerCase();
        case 'plan':
          return planRemainingMs(u.plan, fetchedAt);
        case 'kind':
          return (u.planKind ?? '').toLowerCase();
        case 'activation':
          // Sort by when a code was last issued (never-issued sinks to the bottom).
          return u.latestCodeGeneratedAtUtc
            ? new Date(u.latestCodeGeneratedAtUtc).getTime()
            : 0;
        case 'joined':
          return new Date(u.createdAtUtc).getTime();
        case 'lastModified':
          return new Date(u.lastModifiedAtUtc ?? u.createdAtUtc).getTime();
      }
    };
    return [...filtered].sort((a, b) => {
      const av = val(a);
      const bv = val(b);
      if (av < bv) return -1 * dir;
      if (av > bv) return 1 * dir;
      return 0;
    });
  }, [filtered, sort, fetchedAt]);

  // Reset to page 1 whenever the result set changes shape.
  useEffect(() => setPage(1), [query, filter, sort]);

  const totalPages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE));
  const clampedPage = Math.min(page, totalPages);
  const pageRows = sorted.slice(
    (clampedPage - 1) * PAGE_SIZE,
    clampedPage * PAGE_SIZE,
  );

  const selected = customers.find((u) => u.userId === selectedId) ?? null;

  const TEXT_COLS: SortKey[] = ['name', 'phone', 'device', 'kind'];

  function toggleSort(key: SortKey) {
    setSort((s) =>
      s.key === key
        ? { key, dir: s.dir === 'asc' ? 'desc' : 'asc' }
        : { key, dir: TEXT_COLS.includes(key) ? 'asc' : 'desc' },
    );
  }

  // Mobile sort <select>: switch the key, defaulting to that column's natural
  // direction (text A→Z, everything else newest/most-first). No-op if unchanged.
  function setSortKey(key: SortKey) {
    setSort((s) =>
      s.key === key ? s : { key, dir: TEXT_COLS.includes(key) ? 'asc' : 'desc' },
    );
  }

  return (
    <>
      <PageHeader
        title="Users"
        subtitle={`${customers.length} customer${customers.length === 1 ? '' : 's'}`}
        action={
          <div className="page-header-buttons">
            <button
              className="btn btn-ghost"
              onClick={() => reload()}
              disabled={refreshing}
            >
              {refreshing ? 'Refreshing…' : 'Refresh'}
            </button>
            <button className="btn btn-primary" onClick={() => navigate('/codes')}>
              Generate code
            </button>
          </div>
        }
      />

      <div className="toolbar">
        <div className="search">
          <SearchIcon />
          <input
            className="search-input"
            placeholder="Search by name, phone or device"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="segmented">
          {FILTERS.map((f) => (
            <button
              key={f.key}
              className={`segment${filter === f.key ? ' segment-active' : ''}`}
              onClick={() => setFilter(f.key)}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* Mobile-only sort control — stands in for the datatable's sortable column
          headers, which the card view doesn't have. Hidden ≥861px via CSS. */}
      <div className="mobile-sort">
        <label className="mobile-sort-label" htmlFor="mobile-sort-select">
          Sort
        </label>
        <select
          id="mobile-sort-select"
          className="mobile-sort-select"
          value={sort.key}
          onChange={(e) => setSortKey(e.target.value as SortKey)}
        >
          {COLUMNS.map((c) => (
            <option key={c.key} value={c.key}>
              {c.label}
            </option>
          ))}
        </select>
        <button
          type="button"
          className="mobile-sort-dir"
          onClick={() =>
            setSort((s) => ({ ...s, dir: s.dir === 'asc' ? 'desc' : 'asc' }))
          }
          aria-label={`Sorted ${sort.dir === 'asc' ? 'ascending' : 'descending'}; tap to reverse`}
        >
          {sort.dir === 'asc' ? '▲ Asc' : '▼ Desc'}
        </button>
      </div>

      <div className="users-layout">
        <div className="users-main">
          {error ? (
            <div className="alert alert-error">{error}</div>
          ) : loading && users.length === 0 ? (
            <div className="page-loading">
              <span className="spinner" />
            </div>
          ) : (
            <div className="table-card users-table-view">
              <div className="table-scroll">
              <table className="datatable">
                <thead>
                  <tr>
                    {COLUMNS.map((c) => (
                      <th key={c.key}>
                        <button
                          className="th-sort"
                          onClick={() => toggleSort(c.key)}
                        >
                          {c.label}
                          <SortCaret
                            active={sort.key === c.key}
                            dir={sort.dir}
                          />
                        </button>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {pageRows.length === 0 ? (
                    <tr>
                      <td colSpan={COLUMNS.length} className="table-empty">
                        No matching customers.
                      </td>
                    </tr>
                  ) : (
                    pageRows.map((u) => {
                      const view = planView(u.plan, fetchedAt);
                      const badge = planBadge(view.state);
                      return (
                        <tr
                          key={u.userId}
                          className={
                            u.userId === selectedId ? 'row-selected' : undefined
                          }
                          onClick={() => setSelectedId(u.userId)}
                        >
                          <td className="cell-name">{u.fullName || '—'}</td>
                          <td className="muted">{u.phone ?? '—'}</td>
                          <td className="muted cell-device">
                            {u.hasDevice ? (u.deviceLabel ?? 'Registered') : '—'}
                          </td>
                          <td className="cell-plan">
                            <div className="cell-plan-head">
                              <span className={`badge ${badge.className}`}>
                                {badge.label}
                              </span>
                              {view.state !== 'expired' && (
                                <span className="cell-remaining">
                                  {view.remainingLabel} left
                                </span>
                              )}
                            </div>
                            {view.state !== 'expired' && (
                              <div
                                className={`plan-bar ${badge.className} cell-plan-bar`}
                                role="progressbar"
                                aria-valuemin={0}
                                aria-valuemax={100}
                                aria-valuenow={Math.round(
                                  view.progressRemaining * 100,
                                )}
                                title={`${Math.round(
                                  view.progressRemaining * 100,
                                )}% of the ${badge.label.toLowerCase()} period remaining`}
                              >
                                <div
                                  className="plan-bar-fill"
                                  style={{
                                    width: `${view.progressRemaining * 100}%`,
                                  }}
                                />
                              </div>
                            )}
                          </td>
                          <td className="muted">{u.planKind ?? '—'}</td>
                          <td>
                            <ActivationCell user={u} />
                          </td>
                          <td className="muted">
                            {fmtDate(u.lastModifiedAtUtc ?? u.createdAtUtc)}
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
              </div>

              {/* Mobile card list — same paged rows, reflowed as cards. Revealed
                  ≤860px (and the table hidden) via CSS. */}
              <div className="user-cards">
                {pageRows.length === 0 ? (
                  <p className="table-empty">No matching customers.</p>
                ) : (
                  pageRows.map((u) => (
                    <UserCard
                      key={u.userId}
                      user={u}
                      fetchedAt={fetchedAt}
                      selected={u.userId === selectedId}
                      onSelect={() => setSelectedId(u.userId)}
                    />
                  ))
                )}
              </div>

              <div className="pagination">
                <span className="pagination-info">
                  {sorted.length === 0
                    ? '0 results'
                    : `${(clampedPage - 1) * PAGE_SIZE + 1}–${Math.min(
                        clampedPage * PAGE_SIZE,
                        sorted.length,
                      )} of ${sorted.length}`}
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
          )}
        </div>

        <UserDetailPanel
          user={selected}
          fetchedAt={fetchedAt}
          onChanged={reload}
        />
      </div>
    </>
  );
}

/**
 * Mobile card for one customer — the reflowed equivalent of a datatable row.
 * Carries the same fields (name, phone, plan badge + progress, device, kind,
 * activation, last edited) and the same select-on-tap behaviour.
 */
function UserCard({
  user: u,
  fetchedAt,
  selected,
  onSelect,
}: {
  user: AdminUser;
  fetchedAt: number;
  selected: boolean;
  onSelect: () => void;
}) {
  const view = planView(u.plan, fetchedAt);
  const badge = planBadge(view.state);
  return (
    <button
      type="button"
      className={`ucard${selected ? ' ucard-selected' : ''}`}
      onClick={onSelect}
    >
      <div className="ucard-top">
        <div className="ucard-id">
          <div className="ucard-name">{u.fullName || '—'}</div>
          <div className="ucard-phone">{u.phone ?? '—'}</div>
        </div>
        <span className={`badge ${badge.className}`}>{badge.label}</span>
      </div>

      {view.state !== 'expired' && (
        <div>
          <div
            className={`plan-bar ${badge.className}`}
            role="progressbar"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={Math.round(view.progressRemaining * 100)}
          >
            <div
              className="plan-bar-fill"
              style={{ width: `${view.progressRemaining * 100}%` }}
            />
          </div>
          <span className="ucard-remaining">{view.remainingLabel} left</span>
        </div>
      )}

      <div className="ucard-meta">
        <div className="ucard-meta-item">
          <span className="ucard-meta-k">Device</span>
          <span className="ucard-meta-v">
            {u.hasDevice ? (u.deviceLabel ?? 'Registered') : '—'}
          </span>
        </div>
        <div className="ucard-meta-item">
          <span className="ucard-meta-k">Plan kind</span>
          <span className="ucard-meta-v">{u.planKind ?? '—'}</span>
        </div>
        <div className="ucard-meta-item">
          <span className="ucard-meta-k">Last edited</span>
          <span className="ucard-meta-v">
            {fmtDate(u.lastModifiedAtUtc ?? u.createdAtUtc)}
          </span>
        </div>
        <div className="ucard-meta-item ucard-meta-activation">
          <span className="ucard-meta-k">Activation code</span>
          <ActivationCell user={u} />
        </div>
      </div>
    </button>
  );
}

/**
 * Activation-code status for one customer: whether the last code we issued has been used, and when
 * it was generated. "Not used yet" signals the plan hasn't started counting (redemption is what
 * starts it); "Used" shows the redemption time. No code ever issued → a plain dash.
 */
function ActivationCell({ user }: { user: AdminUser }) {
  if (!user.latestCodeGeneratedAtUtc) {
    return <span className="muted">—</span>;
  }
  const used = user.latestCodeRedeemed;
  return (
    <div className="activation-cell">
      <span className={`badge ${used ? 'badge-pro' : 'badge-trial'}`}>
        {used ? 'Used' : 'Not used'}
      </span>
      <span className="activation-sub muted">
        Generated {fmtDateTime(user.latestCodeGeneratedAtUtc)}
      </span>
      {used && user.latestCodeRedeemedAtUtc && (
        <span className="activation-sub muted">
          Used {fmtDateTime(user.latestCodeRedeemedAtUtc)}
        </span>
      )}
    </div>
  );
}

function SortCaret({ active, dir }: { active: boolean; dir: SortDir }) {
  return (
    <span className={`sort-caret${active ? ' sort-active' : ''}`}>
      {active ? (dir === 'asc' ? '▲' : '▼') : '↕'}
    </span>
  );
}

function SearchIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon-sm" aria-hidden>
      <path
        fill="currentColor"
        d="M15.5 14h-.79l-.28-.27a6.5 6.5 0 1 0-.7.7l.27.28v.79l5 4.99L20.49 19l-4.99-5Zm-6 0A4.5 4.5 0 1 1 14 9.5 4.49 4.49 0 0 1 9.5 14Z"
      />
    </svg>
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

/** Date + time (the moment a code was generated / used), e.g. "14 Aug 2026, 17:07". */
function fmtDateTime(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
}
