import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { adminApi } from '../features/admin/api';
import { ApiError } from '../lib/api';
import { generateCodeSchema, type GeneratedCode } from '../lib/schemas';
import { PageHeader } from '../components/PageHeader';
import { useToast } from '../components/Toast';

interface Dhm {
  days: number;
  hours: number;
  minutes: number;
}

const toMinutes = (d: Dhm) => d.days * 1440 + d.hours * 60 + d.minutes;

/** Plan kinds the admin can grant — mapped to a duration (Forever is a backend sentinel). */
type PlanKind = 'month' | 'sixMonths' | 'year' | 'forever' | 'custom';
const PLAN_KINDS: { key: PlanKind; label: string; minutes: number }[] = [
  { key: 'month', label: '1 month', minutes: 30 * 1440 },
  { key: 'sixMonths', label: '6 months', minutes: 182 * 1440 },
  { key: 'year', label: '1 year', minutes: 365 * 1440 },
  { key: 'forever', label: 'Forever', minutes: 0 },
  { key: 'custom', label: 'Custom', minutes: 0 },
];

/**
 * Mint activation code(s) for a customer. The admin picks a plan kind (1 month /
 * 6 months / 1 year / Forever / custom), a count, and an expiry. Codes are
 * phone-bound (only that number can redeem) and each can be shared straight to
 * WhatsApp or any channel via the Share button.
 */
export function GenerateCodePage() {
  const [params] = useSearchParams();
  const toast = useToast();

  const [phone, setPhone] = useState(params.get('phone') ?? '');
  const [kind, setKind] = useState<PlanKind>('month');
  const [custom, setCustom] = useState<Dhm>({ days: 30, hours: 0, minutes: 0 });
  const [count, setCount] = useState(1);
  const [expiry, setExpiry] = useState<Dhm>({ days: 14, hours: 0, minutes: 0 });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<GeneratedCode[]>([]);

  async function generate() {
    setError(null);
    setResults([]);
    const forever = kind === 'forever';
    const preset = PLAN_KINDS.find((k) => k.key === kind);
    const durationMinutes = forever
      ? 1 // placeholder; backend overrides with the forever sentinel
      : kind === 'custom'
        ? toMinutes(custom)
        : (preset?.minutes ?? 0);

    const parsed = generateCodeSchema.safeParse({
      phone: phone.trim(),
      durationMinutes,
      expiresInMinutes: toMinutes(expiry),
      forever,
      count,
    });
    if (!parsed.success) {
      const errs = parsed.error.flatten().fieldErrors;
      setError(
        errs.phone?.[0] ??
          errs.durationMinutes?.[0] ??
          errs.count?.[0] ??
          'Invalid input.',
      );
      return;
    }

    setBusy(true);
    try {
      const codes = await adminApi.generateCodes(parsed.data);
      setResults(codes);
      toast.success(
        codes.length === 1 ? 'Activation code generated.' : `${codes.length} codes generated.`,
      );
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not generate the code.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader
        title="Generate activation code"
        subtitle="Mint phone-bound code(s) granting Pro access."
      />

      <div className="form-narrow">
        <div className="field">
          <span className="field-label">Customer phone number</span>
          <input
            className="input"
            type="tel"
            inputMode="tel"
            placeholder="+2526XXXXXXX"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </div>

        <div className="section-label">Plan</div>
        <div className="preset-row">
          {PLAN_KINDS.map((k) => (
            <button
              key={k.key}
              type="button"
              className={`chip${kind === k.key ? ' chip-active' : ''}`}
              onClick={() => setKind(k.key)}
            >
              {k.label}
            </button>
          ))}
        </div>
        {kind === 'custom' && <DhmRow value={custom} onChange={setCustom} />}

        <div className="two-col">
          <div className="field">
            <span className="field-label">How many codes</span>
            <input
              className="input"
              type="number"
              min={1}
              max={100}
              value={count}
              onChange={(e) =>
                setCount(Math.max(1, Math.min(100, Number(e.target.value) || 1)))
              }
            />
          </div>
        </div>

        <div className="section-label">Code expires in (if unredeemed)</div>
        <DhmRow value={expiry} onChange={setExpiry} allowZero />

        {error && <div className="alert alert-error">{error}</div>}

        <button
          className="btn btn-primary btn-block btn-lg"
          onClick={generate}
          disabled={busy}
        >
          {busy ? <span className="spinner spinner-sm" /> : 'Generate code'}
        </button>

        {results.map((r) => (
          <ResultCard key={r.code} result={r} />
        ))}
      </div>
    </>
  );
}

function ResultCard({ result }: { result: GeneratedCode }) {
  const toast = useToast();

  const shareText =
    `Your Xawil Pro activation code: ${result.code}` +
    (result.planKind ? ` (${result.planKind})` : '') +
    `. Open the Xawil app → Activate, and enter this code.`;

  async function share() {
    // Native share sheet (WhatsApp, etc.) where supported; fall back to a WhatsApp deep link.
    if (navigator.share) {
      try {
        await navigator.share({ title: 'Xawil activation code', text: shareText });
        return;
      } catch {
        return; // user dismissed the sheet
      }
    }
    window.open(`https://wa.me/?text=${encodeURIComponent(shareText)}`, '_blank');
  }

  return (
    <div className="result-card">
      <span className="result-label">
        Activation code{result.planKind ? ` · ${result.planKind}` : ''}
      </span>
      <div className="result-code-row">
        <code className="result-code">{result.code}</code>
        <div className="result-actions">
          <button
            className="btn btn-ghost btn-sm"
            onClick={async () => {
              await navigator.clipboard.writeText(result.code);
              toast.success('Code copied');
            }}
          >
            Copy
          </button>
          <button className="btn btn-primary btn-sm" onClick={share}>
            <ShareIcon /> Share
          </button>
        </div>
      </div>
      <p className="result-meta">
        Grants {dhmLabel(result.durationMinutes, result.planKind)}
        {result.assignedToPhone ? ` · bound to ${result.assignedToPhone}` : ''}
      </p>
      <p className="result-note">
        Share this with the customer over WhatsApp. Only their number can redeem it.
      </p>
    </div>
  );
}

function DhmRow({
  value,
  onChange,
  allowZero = false,
}: {
  value: Dhm;
  onChange: (d: Dhm) => void;
  allowZero?: boolean;
}) {
  return (
    <div className="dhm-row">
      <Stepper label="Days" value={value.days} max={3650} min={0} onChange={(days) => onChange({ ...value, days })} />
      <Stepper label="Hours" value={value.hours} max={23} min={0} onChange={(hours) => onChange({ ...value, hours })} />
      <Stepper
        label="Minutes"
        value={value.minutes}
        max={59}
        min={allowZero ? 0 : 0}
        onChange={(minutes) => onChange({ ...value, minutes })}
      />
    </div>
  );
}

function Stepper({
  label,
  value,
  max,
  min,
  onChange,
}: {
  label: string;
  value: number;
  max: number;
  min: number;
  onChange: (v: number) => void;
}) {
  return (
    <div className="stepper">
      <span className="stepper-label">{label}</span>
      <div className="stepper-box">
        <button
          type="button"
          className="stepper-btn"
          disabled={value >= max}
          onClick={() => onChange(value + 1)}
          aria-label={`Increase ${label}`}
        >
          ▲
        </button>
        <span className="stepper-value">{value}</span>
        <button
          type="button"
          className="stepper-btn"
          disabled={value <= min}
          onClick={() => onChange(value - 1)}
          aria-label={`Decrease ${label}`}
        >
          ▼
        </button>
      </div>
    </div>
  );
}

function dhmLabel(minutes: number, planKind?: string | null): string {
  if (planKind) return planKind;
  const d = Math.floor(minutes / 1440);
  const h = Math.floor((minutes % 1440) / 60);
  const m = minutes % 60;
  const parts: string[] = [];
  if (d > 0) parts.push(`${d}d`);
  if (h > 0) parts.push(`${h}h`);
  if (m > 0) parts.push(`${m}m`);
  return parts.length ? parts.join(' ') : '0m';
}

function ShareIcon() {
  return (
    <svg viewBox="0 0 24 24" className="icon-sm" aria-hidden>
      <path
        fill="currentColor"
        d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81a3 3 0 1 0-3-3c0 .24.04.47.09.7L8.04 9.81A3 3 0 1 0 6 15c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65a2.92 2.92 0 1 0 2.92-2.92Z"
      />
    </svg>
  );
}
