import { z } from 'zod';
import { API_BASE_URL } from './config';
import { useAuthStore } from '../store/auth';

/** An API failure carrying the backend's user-facing message. */
export class ApiError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}

// The ServiceResponse<T> envelope: { data, message, status }.
const envelope = z.object({
  data: z.unknown().nullish(),
  message: z.string().nullish(),
});

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE';
  body?: unknown;
  /** Zod schema to validate & type the `data` payload. Omit for empty responses. */
  schema?: z.ZodType;
}

/**
 * The one place that talks to MoneyExchange.Api. Attaches the admin JWT, unwraps
 * the ServiceResponse envelope, validates the payload with zod, and turns any
 * failure into an ApiError with a readable message. A 401 means the token is dead
 * or missing → sign out so the router bounces to the sign-in screen.
 */
export async function apiRequest<T = void>(
  path: string,
  { method = 'GET', body, schema }: RequestOptions = {},
): Promise<T> {
  const token = useAuthStore.getState().token;

  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers: {
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new ApiError(
      'Could not reach the server. Check your connection and try again.',
    );
  }

  if (res.status === 401) {
    useAuthStore.getState().signOut();
    throw new ApiError('Your session has expired. Please sign in again.', 401);
  }

  const parsedEnvelope = envelope.safeParse(await res.json().catch(() => ({})));
  const message = parsedEnvelope.success
    ? (parsedEnvelope.data.message ?? undefined)
    : undefined;

  if (!res.ok) {
    throw new ApiError(
      message ??
        (res.status === 403
          ? 'Admin access required.'
          : 'Something went wrong. Please try again.'),
      res.status,
    );
  }

  if (!schema) return undefined as T;

  const data = parsedEnvelope.success ? parsedEnvelope.data.data : undefined;
  const validated = schema.safeParse(data);
  if (!validated.success) {
    throw new ApiError('Unexpected response from the server.', res.status);
  }
  return validated.data as T;
}
