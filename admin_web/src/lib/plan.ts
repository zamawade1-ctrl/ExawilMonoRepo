import type { PlanStatus } from './schemas';

export type PlanState = 'pro' | 'trial' | 'expired';

/**
 * Derives the live plan state from a snapshot, mirroring the Flutter
 * PlanSnapshot getters (status / remaining / progressRemaining). We correct for
 * client clock drift with the server's `serverNowUtc`, so the countdown is
 * accurate even if the admin's laptop clock is off.
 */
function ms(v?: string | null): number | null {
  if (!v) return null;
  const t = new Date(v).getTime();
  return Number.isNaN(t) ? null : t;
}

/** "Effective now": the server's now, advanced by real time since we fetched. */
function effectiveNow(plan: PlanStatus, fetchedAtLocal: number): number {
  const serverNow = ms(plan.serverNowUtc) ?? Date.now();
  return serverNow + (Date.now() - fetchedAtLocal);
}

export function planState(plan: PlanStatus, fetchedAtLocal: number): PlanState {
  const now = effectiveNow(plan, fetchedAtLocal);
  const paidUntil = ms(plan.planPaidUntilUtc);
  const trialEnds = ms(plan.trialEndsAtUtc);
  if (paidUntil !== null && now < paidUntil) return 'pro';
  if (trialEnds !== null && now < trialEnds) return 'trial';
  return 'expired';
}

/** Instant access is valid through, for the current state (null when expired). */
function activeUntil(plan: PlanStatus, state: PlanState): number | null {
  if (state === 'pro') return ms(plan.planPaidUntilUtc);
  if (state === 'trial') return ms(plan.trialEndsAtUtc);
  return null;
}

export interface PlanView {
  state: PlanState;
  /** Fraction 0..1 of the current window remaining (for the progress bar). */
  progressRemaining: number;
  /** Human string of time left, e.g. "12d 3h", "2:05". Empty when expired. */
  remainingLabel: string;
}

export function planView(plan: PlanStatus, fetchedAtLocal: number): PlanView {
  const state = planState(plan, fetchedAtLocal);
  const now = effectiveNow(plan, fetchedAtLocal);
  const end = activeUntil(plan, state);

  if (state === 'expired' || end === null) {
    return { state, progressRemaining: 0, remainingLabel: '' };
  }

  const start = ms(plan.currentPeriodStartUtc);
  let progress: number;
  if (start !== null && end > start) {
    progress = (end - now) / (end - start);
  } else {
    const total = plan.planDays * 24 * 60 * 60 * 1000;
    progress = total <= 0 ? 0 : (end - now) / total;
  }
  progress = Math.max(0, Math.min(1, progress));

  return { state, progressRemaining: progress, remainingLabel: formatLeft(end - now) };
}

function formatLeft(msLeft: number): string {
  const left = Math.max(0, msLeft);
  const totalMin = Math.floor(left / 60000);
  const days = Math.floor(totalMin / 1440);
  const hours = Math.floor((totalMin % 1440) / 60);
  const mins = totalMin % 60;
  if (days >= 1) return `${days}d ${hours}h`;
  if (hours >= 1) return `${hours}h ${mins}m`;
  const secs = Math.floor((left % 60000) / 1000);
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

/** Milliseconds of access left in the current window (0 when expired) — for sorting. */
export function planRemainingMs(plan: PlanStatus, fetchedAtLocal: number): number {
  const state = planState(plan, fetchedAtLocal);
  const now = effectiveNow(plan, fetchedAtLocal);
  const end = activeUntil(plan, state);
  if (end === null) return 0;
  return Math.max(0, end - now);
}

/** USD price for a plan kind label, or null if it doesn't map to a priced tier. */
export function planPrice(planKind?: string | null): number | null {
  switch ((planKind ?? '').toLowerCase()) {
    case '1 month':
      return 10;
    case '1 year':
      return 60;
    case 'forever':
      return 200;
    default:
      return null;
  }
}

export function planBadge(state: PlanState): { label: string; className: string } {
  switch (state) {
    case 'pro':
      return { label: 'PRO', className: 'badge-pro' };
    case 'trial':
      return { label: 'TRIAL', className: 'badge-trial' };
    case 'expired':
      return { label: 'EXPIRED', className: 'badge-expired' };
  }
}
