import { useEffect } from 'react';
import { useUsersStore } from '../../store/users';
import type { AdminUser } from '../../lib/schemas';

interface UsersState {
  users: AdminUser[];
  /** Wall-clock time we fetched, so plan countdowns stay drift-accurate. */
  fetchedAt: number;
  /** Full-page spinner state: true only on a cold cache with no rows yet. */
  loading: boolean;
  /** Background revalidation in progress (rows already visible). */
  refreshing: boolean;
  error: string | null;
  reload: () => Promise<void>;
}

/**
 * Reads the shared, cached admin user feed (see {@link useUsersStore}). Mounting a
 * page calls `ensure()`, which is instant when the cache is fresh and silently
 * revalidates when stale — so moving between Dashboard / Users / Billing no longer
 * blocks on a network round-trip. `reload` forces a fresh pull after a mutation.
 */
export function useUsers(): UsersState {
  const users = useUsersStore((s) => s.users);
  const fetchedAt = useUsersStore((s) => s.fetchedAt);
  const loading = useUsersStore((s) => s.loading);
  const refreshing = useUsersStore((s) => s.refreshing);
  const error = useUsersStore((s) => s.error);
  const ensure = useUsersStore((s) => s.ensure);
  const reload = useUsersStore((s) => s.reload);

  useEffect(() => {
    void ensure();
  }, [ensure]);

  return { users, fetchedAt, loading, refreshing, error, reload };
}
