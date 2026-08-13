import { authResponseSchema, type AuthResponse } from './schemas';

/**
 * Where the admin session (JWT + identity) lives in the browser.
 *
 * Security choice: we use **sessionStorage**, not localStorage. sessionStorage is
 * scoped to the tab and wiped when the tab closes, so a shared/kiosk machine
 * doesn't leak a long-lived admin token, and there's no cross-tab persistence for
 * an attacker to lean on. It is still readable by JS on this origin, so the real
 * XSS defences are: no third-party scripts, a strict CSP-style header set (see
 * vercel.json), and short-lived tokens (the backend sets ExpiresAtUtc). If the
 * backend later moves to an httpOnly refresh cookie, this module is the only place
 * that changes.
 */
const KEY = 'xawil.admin.session.v1';

export interface StoredSession {
  token: string;
  expiresAtUtc: string;
  user: AuthResponse;
}

const storedSchema = authResponseSchema; // the auth response *is* the identity we keep

export function loadSession(): StoredSession | null {
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = storedSchema.safeParse(JSON.parse(raw));
    if (!parsed.success) return null;
    const user = parsed.data;
    // Drop an expired token on load so we never present a dead session.
    if (new Date(user.expiresAtUtc).getTime() <= Date.now()) {
      clearSession();
      return null;
    }
    return { token: user.accessToken, expiresAtUtc: user.expiresAtUtc, user };
  } catch {
    return null;
  }
}

export function saveSession(user: AuthResponse): StoredSession {
  const session: StoredSession = {
    token: user.accessToken,
    expiresAtUtc: user.expiresAtUtc,
    user,
  };
  sessionStorage.setItem(KEY, JSON.stringify(user));
  return session;
}

export function clearSession(): void {
  sessionStorage.removeItem(KEY);
}
