import { apiRequest } from '../../lib/api';
import {
  adminUsersSchema,
  billingRecordsSchema,
  generatedCodesSchema,
  type AdminUser,
  type BillingRecord,
  type GeneratedCode,
} from '../../lib/schemas';

/**
 * The /api/admin surface — the same operations as the mobile admin console
 * (moneyexchange_app/lib/features/admin). Every call is Admin-role gated on the
 * backend; a non-admin token gets 403 regardless of anything the client does.
 */
export const adminApi = {
  /** All accounts with their live plan snapshot (the dashboard feed). */
  listUsers: (): Promise<AdminUser[]> =>
    apiRequest('/api/admin/users', { schema: adminUsersSchema }),

  /** The historical billing ledger — one row per activation code minted, newest first. */
  listBilling: (): Promise<BillingRecord[]> =>
    apiRequest('/api/admin/billing', { schema: billingRecordsSchema }),

  /**
   * Mints `count` activation code(s) bound to `phone`, granting `durationMinutes`
   * (or a forever plan when `forever`), expiring in `expiresInMinutes` (0 = never).
   * Returns all generated codes.
   */
  generateCodes: (params: {
    phone: string;
    durationMinutes: number;
    expiresInMinutes: number;
    forever?: boolean;
    count: number;
    priceUsd?: number;
  }): Promise<GeneratedCode[]> =>
    apiRequest<GeneratedCode[]>('/api/admin/activation-codes', {
      method: 'POST',
      body: params,
      schema: generatedCodesSchema,
    }),

  /** Forces a user's plan to lapse `inSeconds` from now (0 = immediately). */
  expirePlan: (phone: string, inSeconds = 0): Promise<void> =>
    apiRequest('/api/admin/expire-plan', {
      method: 'POST',
      body: { phone, inSeconds },
    }),

  /** Clears a user's device binding so they can sign in on a new phone. */
  resetDevice: (phone: string): Promise<void> =>
    apiRequest('/api/admin/reset-device', {
      method: 'POST',
      body: { phone },
    }),

  /** Sets a new password for a user who forgot theirs. */
  resetPassword: (phone: string, newPassword: string): Promise<void> =>
    apiRequest('/api/admin/reset-password', {
      method: 'POST',
      body: { phone, newPassword },
    }),

  /** Corrects a user's mistyped phone number. */
  updatePhone: (phone: string, newPhone: string): Promise<void> =>
    apiRequest('/api/admin/update-phone', {
      method: 'POST',
      body: { phone, newPhone },
    }),
};
