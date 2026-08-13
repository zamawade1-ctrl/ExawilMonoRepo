import { useCallback, useEffect, useState } from 'react';
import { adminApi } from './api';
import { ApiError } from '../../lib/api';
import type { AdminUser } from '../../lib/schemas';

interface UsersState {
  users: AdminUser[];
  /** Wall-clock time we fetched, so plan countdowns stay drift-accurate. */
  fetchedAt: number;
  loading: boolean;
  error: string | null;
  reload: () => Promise<void>;
}

/** Loads the admin user feed once and exposes a `reload` for after mutations. */
export function useUsers(): UsersState {
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [fetchedAt, setFetchedAt] = useState(() => Date.now());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const list = await adminApi.listUsers();
      setUsers(list);
      setFetchedAt(Date.now());
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Failed to load users.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { users, fetchedAt, loading, error, reload };
}
