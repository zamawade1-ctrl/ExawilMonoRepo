import { useEffect } from 'react';
import { useBillingStore } from '../../store/billing';
import type { BillingRecord } from '../../lib/schemas';

interface BillingState {
  records: BillingRecord[];
  /** Full-page spinner state: true only on a cold cache with no rows yet. */
  loading: boolean;
  /** Background revalidation in progress (rows already visible). */
  refreshing: boolean;
  error: string | null;
  reload: () => Promise<void>;
}

/**
 * Reads the shared, cached billing ledger (see {@link useBillingStore}). Mounting the Billing page
 * calls `ensure()` — instant on a fresh cache, silent revalidate when stale. `reload` forces a
 * fresh pull (used by the Refresh button and after a code is minted).
 */
export function useBilling(): BillingState {
  const records = useBillingStore((s) => s.records);
  const loading = useBillingStore((s) => s.loading);
  const refreshing = useBillingStore((s) => s.refreshing);
  const error = useBillingStore((s) => s.error);
  const ensure = useBillingStore((s) => s.ensure);
  const reload = useBillingStore((s) => s.reload);

  useEffect(() => {
    void ensure();
  }, [ensure]);

  return { records, loading, refreshing, error, reload };
}
