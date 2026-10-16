import { create } from 'zustand';
import { z } from 'zod';
import { API_BASE_URL } from '../lib/config';
import {
  authResponseSchema,
  type AuthResponse,
  type SignInInput,
} from '../lib/schemas';
import {
  clearSession,
  loadSession,
  saveSession,
} from '../lib/session';

/** Human-facing error raised by the auth flow. */
export class AuthError extends Error {}

interface AuthState {
  user: AuthResponse | null;
  token: string | null;
  loading: boolean;
  /** True once we've hydrated from storage — the router waits for this. */
  ready: boolean;

  hydrate: () => void;
  signIn: (input: SignInInput) => Promise<void>;
  signOut: () => void;
  isAdmin: () => boolean;
}

// The ServiceResponse<T> envelope every endpoint returns: { data, message, status }.
const envelope = z.object({
  data: z.unknown().nullish(),
  message: z.string().nullish(),
});

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  token: null,
  loading: false,
  ready: false,

  hydrate: () => {
    const session = loadSession();
    set({
      user: session?.user ?? null,
      token: session?.token ?? null,
      ready: true,
    });
  },

  signIn: async ({ phoneNumber, password }) => {
    set({ loading: true });
    try {
      let res: Response;
      try {
        res = await fetch(`${API_BASE_URL}/api/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phoneNumber, password }),
        });
      } catch {
        throw new AuthError(
          'Could not reach the server. Check your connection and try again.',
        );
      }

      const body = envelope.parse(await res.json().catch(() => ({})));

      if (!res.ok) {
        throw new AuthError(
          body.message ??
            (res.status === 401
              ? 'Incorrect phone number or password.'
              : 'Sign-in failed. Please try again.'),
        );
      }

      const parsed = authResponseSchema.safeParse(body.data);
      if (!parsed.success) {
        throw new AuthError('Unexpected response from the server.');
      }
      const user = parsed.data;

      // Hard gate: this console is Admin-only. A valid non-admin login is refused
      // client-side, and every /api/admin call is refused server-side (role-gated)
      // regardless — so a tampered client still gets 403s.
      if (user.role.toLowerCase() !== 'admin') {
        throw new AuthError('This account is not an administrator.');
      }

      saveSession(user);
      set({ user, token: user.accessToken });

      // Warm the user feed while the router is still navigating to the dashboard, so the first
      // page paints with data already in hand instead of blocking on its own fetch. Lazy import
      // avoids an auth ↔ users module cycle; the store de-dupes this against the page's own load.
      void import('./users').then((m) => m.useUsersStore.getState().ensure(true));
    } finally {
      set({ loading: false });
    }
  },

  signOut: () => {
    clearSession();
    set({ user: null, token: null });
    // Drop the cached feeds so the next admin to sign in never sees the previous admin's rows.
    void import('./users').then((m) => m.useUsersStore.getState().clear());
    void import('./billing').then((m) => m.useBillingStore.getState().clear());
  },

  isAdmin: () => get().user?.role.toLowerCase() === 'admin',
}));
