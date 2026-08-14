import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import type { AdminUser } from '../lib/schemas';
import { editPhoneSchema, resetPasswordSchema } from '../lib/schemas';
import { planBadge, planView } from '../lib/plan';
import { adminApi } from '../features/admin/api';
import { ApiError } from '../lib/api';
import { Modal } from './Modal';
import { useToast } from './Toast';

/**
 * The Users page's right-hand master-detail panel: full details for the selected
 * account plus the admin actions (generate code, expire plan, reset password,
 * reset device) — the same operations as the mobile admin console, moved off the
 * row and into the detail view so the table stays scannable. When no row is
 * selected it shows a hint (fills what would otherwise be empty right-side space).
 */
export function UserDetailPanel({
  user,
  fetchedAt,
  onChanged,
}: {
  user: AdminUser | null;
  fetchedAt: number;
  onChanged: () => void;
}) {
  if (!user) {
    return (
      <aside className="detail-panel detail-empty">
        <div className="detail-empty-inner">
          <SelectIcon />
          <p className="detail-empty-title">No customer selected</p>
          <p className="detail-empty-copy">
            Pick a row from the table to see full details and manage the account.
          </p>
        </div>
      </aside>
    );
  }
  // Re-mount on selection change so modal/busy state never leaks between users.
  return (
    <UserDetail
      key={user.userId}
      user={user}
      fetchedAt={fetchedAt}
      onChanged={onChanged}
    />
  );
}

function UserDetail({
  user,
  fetchedAt,
  onChanged,
}: {
  user: AdminUser;
  fetchedAt: number;
  onChanged: () => void;
}) {
  const view = planView(user.plan, fetchedAt);
  const badge = planBadge(view.state);
  const phone = user.phone ?? '';
  const toast = useToast();
  const navigate = useNavigate();

  const [confirm, setConfirm] = useState<null | {
    title: string;
    body: string;
    action: () => Promise<void>;
    okMsg: string;
  }>(null);
  const [resetPw, setResetPw] = useState(false);
  const [editPhone, setEditPhone] = useState(false);
  const [busy, setBusy] = useState(false);

  async function run(action: () => Promise<void>, okMsg: string) {
    setBusy(true);
    try {
      await action();
      toast.success(okMsg);
      onChanged();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : 'Action failed.');
    } finally {
      setBusy(false);
      setConfirm(null);
    }
  }

  return (
    <aside className="detail-panel">
      <div className="detail-head">
        <div className="detail-avatar">{initials(user.fullName)}</div>
        <div className="detail-head-text">
          <h3 className="detail-name">{user.fullName || '—'}</h3>
          <span className="detail-phone">{user.phone ?? '—'}</span>
        </div>
        <span className={`badge ${badge.className}`}>{badge.label}</span>
      </div>

      {view.state !== 'expired' && (
        <div className="detail-plan">
          <div className={`plan-bar ${badge.className}`}>
            <div
              className="plan-bar-fill"
              style={{ width: `${Math.round(view.progressRemaining * 100)}%` }}
            />
          </div>
          <span className={`plan-remaining ${badge.className}`}>
            {view.remainingLabel} left
          </span>
        </div>
      )}

      <dl className="detail-meta">
        <Meta label="Role" value={user.role} />
        <Meta label="Plan" value={user.planKind ?? '—'} />
        <Meta label="Device" value={user.hasDevice ? (user.deviceLabel ?? 'Registered') : 'None'} />
        <Meta label="Joined" value={fmtDate(user.createdAtUtc)} />
        <Meta label="Last login" value={fmtDate(user.lastLoginAtUtc)} />
        <Meta
          label="Code issued"
          value={
            user.latestCodeGeneratedAtUtc
              ? fmtDateTime(user.latestCodeGeneratedAtUtc)
              : 'Never'
          }
        />
        <Meta label="Code status" value={codeStatus(user)} />
      </dl>

      <div className="detail-actions">
        <button
          className="btn btn-primary btn-block"
          onClick={() => navigate(`/codes?phone=${encodeURIComponent(phone)}`)}
        >
          Generate code
        </button>
        <button
          className="btn btn-ghost btn-block"
          disabled={busy}
          onClick={() => setEditPhone(true)}
        >
          Edit phone number
        </button>
        <button
          className="btn btn-ghost btn-block"
          disabled={busy}
          onClick={() => setResetPw(true)}
        >
          Reset password
        </button>
        <button
          className="btn btn-ghost btn-block"
          disabled={busy}
          onClick={() =>
            setConfirm({
              title: 'Reset device?',
              body: `Clear ${user.fullName}'s device binding so they can sign in on a new phone?`,
              okMsg: 'Device binding cleared.',
              action: () => adminApi.resetDevice(phone),
            })
          }
        >
          Reset device
        </button>
        <button
          className="btn btn-danger btn-block"
          disabled={busy}
          onClick={() =>
            setConfirm({
              title: 'Expire plan?',
              body: `Force ${user.fullName}'s plan to expire now?`,
              okMsg: 'Plan expired.',
              action: () => adminApi.expirePlan(phone),
            })
          }
        >
          Expire plan now
        </button>
      </div>

      {confirm && (
        <Modal title={confirm.title} onClose={() => !busy && setConfirm(null)}>
          <p className="modal-body">{confirm.body}</p>
          <div className="modal-actions">
            <button className="btn btn-ghost" onClick={() => setConfirm(null)} disabled={busy}>
              Cancel
            </button>
            <button
              className="btn btn-primary"
              onClick={() => run(confirm.action, confirm.okMsg)}
              disabled={busy}
            >
              {busy ? <span className="spinner spinner-sm" /> : 'Confirm'}
            </button>
          </div>
        </Modal>
      )}

      {resetPw && (
        <ResetPasswordModal
          name={user.fullName}
          busy={busy}
          onClose={() => !busy && setResetPw(false)}
          onSubmit={(pw) =>
            run(async () => {
              await adminApi.resetPassword(phone, pw);
              setResetPw(false);
            }, 'Password reset.')
          }
        />
      )}

      {editPhone && (
        <EditPhoneModal
          name={user.fullName}
          currentPhone={user.phone ?? ''}
          busy={busy}
          onClose={() => !busy && setEditPhone(false)}
          onSubmit={(newPhone) =>
            run(async () => {
              await adminApi.updatePhone(phone, newPhone);
              setEditPhone(false);
            }, 'Phone number updated.')
          }
        />
      )}
    </aside>
  );
}

function EditPhoneModal({
  name,
  currentPhone,
  busy,
  onClose,
  onSubmit,
}: {
  name: string;
  currentPhone: string;
  busy: boolean;
  onClose: () => void;
  onSubmit: (newPhone: string) => void;
}) {
  const [value, setValue] = useState(currentPhone);
  const [err, setErr] = useState<string | null>(null);

  return (
    <Modal title={`Edit ${name}'s phone number`} onClose={onClose}>
      <p className="modal-body">
        Correct a mistyped number. The account and its login identity move to the new
        number.
      </p>
      <div className="field">
        <span className="field-label">New phone number</span>
        <input
          className={err ? 'input input-error' : 'input'}
          type="tel"
          inputMode="tel"
          autoFocus
          placeholder="+2526XXXXXXX"
          value={value}
          onChange={(e) => {
            setValue(e.target.value);
            setErr(null);
          }}
          disabled={busy}
        />
        {err && <span className="field-hint field-hint-error">{err}</span>}
      </div>
      <div className="modal-actions">
        <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
          Cancel
        </button>
        <button
          className="btn btn-primary"
          disabled={busy}
          onClick={() => {
            const parsed = editPhoneSchema.safeParse({ newPhone: value.trim() });
            if (!parsed.success) {
              setErr(parsed.error.flatten().fieldErrors.newPhone?.[0] ?? 'Invalid.');
              return;
            }
            onSubmit(parsed.data.newPhone);
          }}
        >
          {busy ? <span className="spinner spinner-sm" /> : 'Update phone'}
        </button>
      </div>
    </Modal>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div className="detail-meta-row">
      <dt>{label}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function ResetPasswordModal({
  name,
  busy,
  onClose,
  onSubmit,
}: {
  name: string;
  busy: boolean;
  onClose: () => void;
  onSubmit: (pw: string) => void;
}) {
  const [pw, setPw] = useState('');
  const [err, setErr] = useState<string | null>(null);

  return (
    <Modal title={`Reset ${name}'s password`} onClose={onClose}>
      <div className="field">
        <span className="field-label">New password</span>
        <input
          className={err ? 'input input-error' : 'input'}
          type="text"
          autoFocus
          placeholder="At least 6 characters"
          value={pw}
          onChange={(e) => {
            setPw(e.target.value);
            setErr(null);
          }}
          disabled={busy}
        />
        {err && <span className="field-hint field-hint-error">{err}</span>}
      </div>
      <div className="modal-actions">
        <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
          Cancel
        </button>
        <button
          className="btn btn-primary"
          disabled={busy}
          onClick={() => {
            const parsed = resetPasswordSchema.safeParse({ newPassword: pw.trim() });
            if (!parsed.success) {
              setErr(parsed.error.flatten().fieldErrors.newPassword?.[0] ?? 'Invalid.');
              return;
            }
            onSubmit(parsed.data.newPassword);
          }}
        >
          {busy ? <span className="spinner spinner-sm" /> : 'Set password'}
        </button>
      </div>
    </Modal>
  );
}

function initials(name: string): string {
  return (
    name
      .split(' ')
      .map((p) => p[0])
      .filter(Boolean)
      .slice(0, 2)
      .join('')
      .toUpperCase() || '—'
  );
}

function fmtDate(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function fmtDateTime(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
}

/** "Used <when>" / "Not used yet" / "—", for the detail panel's activation summary. */
function codeStatus(user: AdminUser): string {
  if (!user.latestCodeGeneratedAtUtc) return '—';
  if (user.latestCodeRedeemed) {
    return user.latestCodeRedeemedAtUtc
      ? `Used ${fmtDateTime(user.latestCodeRedeemedAtUtc)}`
      : 'Used';
  }
  return 'Not used yet';
}

function SelectIcon() {
  return (
    <svg viewBox="0 0 24 24" className="detail-empty-icon" aria-hidden>
      <path
        fill="currentColor"
        d="M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v3H3V5Zm0 5h18v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-9Zm3 3v2h6v-2H6Z"
      />
    </svg>
  );
}
