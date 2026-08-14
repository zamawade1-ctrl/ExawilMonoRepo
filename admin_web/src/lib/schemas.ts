import { z } from 'zod';

/**
 * Zod schemas — the single source of truth for both form validation and the
 * shapes coming back from MoneyExchange.Api. Parsing every response through
 * these means a backend contract drift surfaces here, not deep in a component.
 */

// ---- Sign-in form ----------------------------------------------------------

export const signInSchema = z.object({
  phoneNumber: z
    .string()
    .trim()
    .min(1, 'Enter your phone number.')
    .max(20, 'Phone number is too long.'),
  password: z
    .string()
    .min(1, 'Enter your password.')
    .max(128, 'Password is too long.'),
});

export type SignInInput = z.infer<typeof signInSchema>;

// ---- App update / release (mirrors AppUpdateDto) ---------------------------
// Powers the PUBLIC download/update page. No auth — anyone with the URL can read it.

export const appUpdateSchema = z.object({
  platform: z.string().default('android'),
  versionName: z.string().default(''),
  versionCode: z.number().default(0),
  apkUrl: z.string().default(''),
  releaseNotes: z.string().nullish(),
  mandatory: z.boolean().default(true),
  releasedAtUtc: z.string().nullish(),
});

export type AppUpdate = z.infer<typeof appUpdateSchema>;

// ---- Plan snapshot (mirrors PlanStatusDto) ---------------------------------

export const planStatusSchema = z.object({
  status: z.string().default('Trial'),
  trialEndsAtUtc: z.string(),
  planPaidUntilUtc: z.string().nullish(),
  serverNowUtc: z.string(),
  planDays: z.number().default(30),
  currentPeriodStartUtc: z.string().nullish(),
  currentPeriodEndUtc: z.string().nullish(),
});

export type PlanStatus = z.infer<typeof planStatusSchema>;

// ---- Auth response (mirrors UserAuthResponseDto) ---------------------------

export const authResponseSchema = z.object({
  accessToken: z.string().min(1),
  expiresAtUtc: z.string(),
  userId: z.number(),
  phoneNumber: z.string().nullish(),
  email: z.string().nullish(),
  username: z.string().nullish(),
  fullName: z.string().default(''),
  role: z.string().default('User'),
  plan: planStatusSchema,
});

export type AuthResponse = z.infer<typeof authResponseSchema>;

// ---- Admin users list (mirrors AdminUserDto) -------------------------------

export const adminUserSchema = z.object({
  userId: z.number(),
  fullName: z.string().default(''),
  phone: z.string().nullish(),
  role: z.string().default('User'),
  deviceLabel: z.string().nullish(),
  hasDevice: z.boolean().default(false),
  createdAtUtc: z.string(),
  lastLoginAtUtc: z.string(),
  lastModifiedAtUtc: z.string().nullish(),
  planKind: z.string().nullish(),
  planStartedAtUtc: z.string().nullish(),
  plan: planStatusSchema,
  // Latest activation code issued to this account: when it was generated, whether it's been used,
  // and when. Lets the table show "issued but not used yet" vs "used at <time>".
  latestCodeGeneratedAtUtc: z.string().nullish(),
  latestCodeRedeemed: z.boolean().default(false),
  latestCodeRedeemedAtUtc: z.string().nullish(),
});

export type AdminUser = z.infer<typeof adminUserSchema>;

export const adminUsersSchema = z.array(adminUserSchema);

// ---- Generated activation code (mirrors ActivationCodeDto) -----------------

export const generatedCodeSchema = z.object({
  code: z.string(),
  durationDays: z.number().default(0),
  durationMinutes: z.number().default(0),
  planKind: z.string().nullish(),
  assignedToPhone: z.string().nullish(),
  expiresAtUtc: z.string().nullish(),
});

export type GeneratedCode = z.infer<typeof generatedCodeSchema>;

export const generatedCodesSchema = z.array(generatedCodeSchema);

// ---- Generate-code form ----------------------------------------------------

export const generateCodeSchema = z.object({
  phone: z
    .string()
    .trim()
    .min(1, "Enter the customer's phone number.")
    .max(20, 'Phone number is too long.'),
  durationMinutes: z
    .number()
    .int()
    .positive('Duration must be greater than zero.'),
  expiresInMinutes: z.number().int().min(0),
  forever: z.boolean().default(false),
  count: z
    .number()
    .int()
    .min(1, 'Mint at least one code.')
    .max(100, 'At most 100 codes.'),
});

export type GenerateCodeInput = z.infer<typeof generateCodeSchema>;

// ---- Reset-password form ---------------------------------------------------

export const resetPasswordSchema = z.object({
  newPassword: z.string().min(6, 'At least 6 characters.').max(128),
});

// ---- Edit-phone form -------------------------------------------------------

export const editPhoneSchema = z.object({
  newPhone: z
    .string()
    .trim()
    .min(6, 'Enter a valid phone number.')
    .max(20, 'Phone number is too long.'),
});
