import { useState, type FormEvent } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Logo } from '../components/Logo';
import { AuthError, useAuthStore } from '../store/auth';
import { signInSchema } from '../lib/schemas';

/**
 * The admin sign-in: a clean two-panel split — a full-green left panel with the
 * white logo & product story, and a white right panel with the form. Matches the
 * mobile app's white + Leon-green identity.
 */
export function SignInPage() {
  const user = useAuthStore((s) => s.user);
  const signIn = useAuthStore((s) => s.signIn);
  const loading = useAuthStore((s) => s.loading);
  const navigate = useNavigate();

  const [phoneNumber, setPhoneNumber] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{
    phoneNumber?: string;
    password?: string;
  }>({});

  // Already signed in → skip the form.
  if (user && user.role.toLowerCase() === 'admin') {
    return <Navigate to="/dashboard" replace />;
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setFieldErrors({});

    const parsed = signInSchema.safeParse({ phoneNumber, password });
    if (!parsed.success) {
      const flat = parsed.error.flatten().fieldErrors;
      setFieldErrors({
        phoneNumber: flat.phoneNumber?.[0],
        password: flat.password?.[0],
      });
      return;
    }

    try {
      await signIn(parsed.data);
      navigate('/dashboard', { replace: true });
    } catch (err) {
      setError(err instanceof AuthError ? err.message : 'Sign-in failed.');
    }
  }

  return (
    <div className="signin">
      {/* Left: full-green brand panel with the white logo */}
      <section className="signin-brand">
        <div className="signin-brand-inner">
          <div className="signin-brand-mark">
            <Logo size={72} variant="white" />
            <span className="signin-brand-name">Xawil</span>
          </div>
          <h1 className="signin-brand-title">Admin console</h1>
          <p className="signin-brand-copy">
            Manage customers, plans and activation codes for the Xawil
            auto-forwarding service — all in one place.
          </p>
          <ul className="signin-brand-list">
            <li>Live view of every account and its plan</li>
            <li>Generate phone-bound activation codes</li>
            <li>Reset devices &amp; passwords, expire plans</li>
          </ul>
        </div>
        <p className="signin-brand-foot">Authorized administrators only.</p>
      </section>

      {/* Right: white form panel */}
      <section className="signin-form-panel">
        <form className="signin-form" onSubmit={onSubmit} noValidate>
          <div className="signin-form-head">
            <h2>Sign in</h2>
            <p>Use your administrator credentials to continue.</p>
          </div>

          {error && <div className="alert alert-error">{error}</div>}

          <label className="field">
            <span className="field-label">Phone number</span>
            <input
              type="tel"
              autoComplete="username"
              inputMode="tel"
              placeholder="+2526XXXXXXX"
              value={phoneNumber}
              onChange={(e) => setPhoneNumber(e.target.value)}
              className={fieldErrors.phoneNumber ? 'input input-error' : 'input'}
              disabled={loading}
              autoFocus
            />
            {fieldErrors.phoneNumber && (
              <span className="field-hint field-hint-error">
                {fieldErrors.phoneNumber}
              </span>
            )}
          </label>

          <label className="field">
            <span className="field-label">Password</span>
            <div className="input-wrap">
              <input
                type={showPassword ? 'text' : 'password'}
                autoComplete="current-password"
                placeholder="Your password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className={fieldErrors.password ? 'input input-error' : 'input'}
                disabled={loading}
              />
              <button
                type="button"
                className="input-affix"
                onClick={() => setShowPassword((s) => !s)}
                tabIndex={-1}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? 'Hide' : 'Show'}
              </button>
            </div>
            {fieldErrors.password && (
              <span className="field-hint field-hint-error">
                {fieldErrors.password}
              </span>
            )}
          </label>

          <button
            type="submit"
            className="btn btn-primary btn-block btn-lg"
            disabled={loading}
          >
            {loading ? <span className="spinner spinner-sm" /> : 'Sign in'}
          </button>
        </form>
      </section>
    </div>
  );
}
