import { create } from 'zustand';
import { adminApi } from '../features/admin/api';
import { ApiError } from '../lib/api';
import type { AdminUser } from '../lib/schemas';

/**
 * A single shared cache of the admin user feed, so navigating between pages
 * (Dashboard / Users / Billing all read it) is **instant** instead of re-fetching
 * `/api/admin/users` on every mount. Behaviour is stale-while-revalidate:
 *
 *  - First load with no cache → `loading` true, fetch, then render.
 *  - Navigating back within {@link STALE_MS} → served straight from cache, no network.
 *  - Navigating back when stale → cached rows render immediately while a silent
 *    background refresh runs (`refreshing`, never the full-page spinner).
 *  - `reload()` (after a mutation, or the Refresh button) always forces a fresh pull.
 *
 * Concurrent callers are de-duped onto one in-flight request.
 */

/** Within this window a cached feed is "fresh": navigation skips the network entirely. */
const STALE_MS = 30_000;

interface UsersStore {
  users: AdminUser[];
  /** Wall-clock of the last successful load, so plan countdowns stay drift-accurate. */
  fetchedAt: number;
  /** True only while fetching with NO cached data yet — this drives the full-page spinner. */
  loading: boolean;
  /** True during a background revalidation (stale data is already on screen). */
  refreshing: boolean;
  error: string | null;
  /** ms timestamp of the last successful load (0 = never loaded). */
  loadedAt: number;
  /** The current in-flight request, for de-duping concurrent callers. */
  inFlight: Promise<void> | null;

  /** Load if needed: instant on a fresh cache, silent revalidate when stale. `force` always fetches. */
  ensure: (force?: boolean) => Promise<void>;
  /** Force a fresh pull (after a mutation or an explicit Refresh). */
  reload: () => Promise<void>;
  /** Drop the cache (on sign-out) so the next admin never sees the previous one's rows. */
  clear: () => void;
}

export const useUsersStore = create<UsersStore>((set, get) => ({
  users: [],
  fetchedAt: Date.now(),
  loading: false,
  refreshing: false,
  error: null,
  loadedAt: 0,
  inFlight: null,

  ensure: async (force = false) => {
    const s = get();
    if (!force) {
      // De-dupe concurrent callers, and serve a fresh cache without touching the network.
      if (s.inFlight) return s.inFlight;
      if (s.loadedAt > 0 && Date.now() - s.loadedAt < STALE_MS) return;
    }

    const hasData = s.users.length > 0;
    // Keep stale rows on screen while revalidating; only show the spinner on a cold cache.
    set(hasData ? { refreshing: true, error: null } : { loading: true, error: null });

    const p = (async () => {
      try {
        const list = await adminApi.listUsers();
        set({
          users: list,
          fetchedAt: Date.now(),
          loadedAt: Date.now(),
          error: null,
        });
      } catch (e) {
        set({ error: e instanceof ApiError ? e.message : 'Failed to load users.' });
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
    set({
      users: [],
      loadedAt: 0,
      error: null,
      refreshing: false,
      loading: false,
      fetchedAt: Date.now(),
    }),
}));
