import { create } from 'zustand';
import { adminApi } from '../features/admin/api';
import { ApiError } from '../lib/api';
import type { BillingRecord } from '../lib/schemas';

/**
 * A shared, stale-while-revalidate cache of the admin billing ledger (`/api/admin/billing`),
 * mirroring {@link useUsersStore}. The ledger is HISTORICAL — one row per activation code minted —
 * so the Billing page can show revenue across every month, not just each user's current plan.
 *
 * Behaviour: instant from cache when fresh, silent background refresh when stale, full pull on
 * `reload()` (after minting a code or the Refresh button). Concurrent callers de-dupe.
 */

/** Within this window the cached ledger is "fresh": navigation skips the network entirely. */
const STALE_MS = 30_000;

interface BillingStore {
  records: BillingRecord[];
  /** True only while fetching with NO cached data yet — drives the full-page spinner. */
  loading: boolean;
  /** True during a background revalidation (stale data is already on screen). */
  refreshing: boolean;
  error: string | null;
  /** ms timestamp of the last successful load (0 = never loaded). */
  loadedAt: number;
  /** The current in-flight request, for de-duping concurrent callers. */
  inFlight: Promise<void> | null;

  ensure: (force?: boolean) => Promise<void>;
  reload: () => Promise<void>;
  clear: () => void;
}

export const useBillingStore = create<BillingStore>((set, get) => ({
  records: [],
  loading: false,
  refreshing: false,
  error: null,
  loadedAt: 0,
  inFlight: null,

  ensure: async (force = false) => {
    const s = get();
    if (!force) {
      if (s.inFlight) return s.inFlight;
      if (s.loadedAt > 0 && Date.now() - s.loadedAt < STALE_MS) return;
    }

    const hasData = s.records.length > 0;
    set(hasData ? { refreshing: true, error: null } : { loading: true, error: null });

    const p = (async () => {
      try {
        const list = await adminApi.listBilling();
        set({ records: list, loadedAt: Date.now(), error: null });
      } catch (e) {
        set({ error: e instanceof ApiError ? e.message : 'Failed to load billing.' });
      } finally {
        set({ loading: false, refreshing: false, inFlight: null });
      }
    })();
    set({ inFlight: p });
    return p;
  },

  reload: async () => {
    await get().ensure(true);
  },

  clear: () =>
    set({ records: [], loadedAt: 0, error: null, refreshing: false, loading: false }),
}));
