import { useEffect, useState } from 'react';
import { Logo } from '../components/Logo';
import { apiRequest, ApiError } from '../lib/api';
import { API_BASE_URL } from '../lib/config';
import { appUpdateSchema, type AppUpdate } from '../lib/schemas';

/**
 * PUBLIC download / update page — no auth, no account, no admin. Anyone with the
 * URL (share it in WhatsApp) can open it, see the current app version + release
 * notes, and download the latest signed APK. It reads the same public endpoint
 * the mobile app's mandatory-update check uses:
 *   GET /api/app-updates/android
 * so the version shown here and the one the app enforces never drift apart.
 */
export function DownloadPage() {
  const [release, setRelease] = useState<AppUpdate | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'unavailable'>(
    'loading',
  );

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const data = await apiRequest<AppUpdate>('/api/app-updates/android', {
          schema: appUpdateSchema,
        });
        if (!alive) return;
        setRelease(data);
        setStatus('ready');
      } catch (err) {
        if (!alive) return;
        // 404 = no active release configured yet; any other error = backend down.
        void (err instanceof ApiError);
        setStatus('unavailable');
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  const released = release?.releasedAtUtc
    ? new Date(release.releasedAtUtc).toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      })
    : null;

  const canDownload = !!release && release.apkUrl.startsWith('https://');

  // Route the button through the public tracking redirect so every click is
  // counted server-side before the browser is 302'd to the signed APK.
  const downloadHref = `${API_BASE_URL}/api/app-updates/android/download`;

  const downloadCount = release?.downloadCount ?? 0;
  const downloadLabel =
    downloadCount === 1 ? '1 download' : `${downloadCount.toLocaleString()} downloads`;

  return (
    <div className="download">
      <div className="download-card">
        <div className="download-mark">
          <Logo size={64} />
        </div>
        <h1 className="download-title">e-Xawil</h1>
        <p className="download-sub">Android app — download &amp; updates</p>

        {status === 'loading' && (
          <div className="download-muted">Loading the latest version…</div>
        )}

        {status === 'unavailable' && (
          <div className="download-muted">
            No download is available right now. Please check back shortly.
          </div>
        )}

        {status === 'ready' && release && (
          // On desktop this becomes a 3-column grid (get · install · appear-on-top);
          // on mobile it stays a single stacked column, unchanged from before.
          <div className="download-body">
            <div className="download-col-get">
              <div className="download-version">
                <span className="download-badge">Latest</span>
                <span className="download-vname">
                  Version {release.versionName}
                </span>
                <span className="download-vcode">build {release.versionCode}</span>
              </div>
              {released && (
                <div className="download-date">Released {released}</div>
              )}

              <div className="download-count" title="Total APK downloads">
                <svg
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  aria-hidden="true"
                >
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" y1="15" x2="12" y2="3" />
                </svg>
                <span>{downloadLabel}</span>
              </div>

              {release.releaseNotes && release.releaseNotes.trim() !== '' && (
                <div className="download-notes">
                  <div className="download-notes-title">What&apos;s new</div>
                  <p>{release.releaseNotes}</p>
                </div>
              )}

              {canDownload ? (
                <a
                  className="download-btn"
                  href={downloadHref}
                  rel="noopener noreferrer"
                >
                  Download / Update ({release.versionName})
                </a>
              ) : (
                <div className="download-muted">
                  The download link is being prepared. Please check back shortly.
                </div>
              )}

              <ol className="download-steps">
                <li>Tap the button to download the APK.</li>
                <li>Open it; if asked, allow installing apps from this source.</li>
                <li>
                  Tap <strong>Install</strong> (or <strong>Update</strong>) — your
                  data is kept.
                </li>
              </ol>
            </div>

            <div className="download-setup-title">
              After installing — enable these permissions
            </div>

            <div className="download-perm download-perm--install">
              <div className="download-perm-name">
                1. Allow installing the app
              </div>
              <p className="download-perm-why">
                When you open the APK, Android may block it. On that prompt tap{' '}
                <strong>Settings</strong>, turn on{' '}
                <strong>Allow from this source</strong>, go back, then tap{' '}
                <strong>Install</strong>.
              </p>
              <Path
                label="Samsung"
                steps={[
                  'Settings',
                  'Apps',
                  'e-Xawil',
                  'Install unknown apps',
                  'Allow',
                ]}
              />
            </div>

            <div className="download-perm download-perm--overlay">
              <div className="download-perm-name">
                2. Appear on top{' '}
                <span className="download-perm-alt">
                  (Display over other apps)
                </span>
              </div>
              <p className="download-perm-why">
                Lets e-Xawil finish forwarding money automatically, even while
                another app is open. Required for auto-forwarding to work
                reliably.
              </p>
              <Path
                label="Samsung (Galaxy)"
                steps={[
                  'Settings',
                  'Apps',
                  'e-Xawil',
                  '⋮ menu',
                  'Special access',
                  'Appear on top',
                  'On',
                ]}
              />
              <Path
                label="Fastest"
                steps={[
                  'Settings',
                  'Search "Appear on top"',
                  'e-Xawil',
                  'On',
                ]}
              />
              <Path
                label="Other Android"
                steps={[
                  'Settings',
                  'Apps',
                  'Special app access',
                  'Display over other apps',
                  'e-Xawil',
                  'On',
                ]}
              />
            </div>
          </div>
        )}
      </div>
      <p className="download-foot">
        Installs over the existing app as an update — no uninstall needed.
      </p>
    </div>
  );
}

/**
 * One tap-path rendered as wrap-friendly breadcrumb chips, e.g.
 * `Samsung: Settings › Apps › e-Xawil › …`. The chips wrap on narrow phones so
 * the guide stays readable on any screen width.
 */
function Path({ label, steps }: { label: string; steps: string[] }) {
  return (
    <div className="download-path">
      <span className="download-path-label">{label}</span>
      {steps.map((step, i) => (
        <span className="download-path-frag" key={`${label}-${i}`}>
          {i > 0 && <span className="download-path-sep">›</span>}
          <span className="download-path-step">{step}</span>
        </span>
      ))}
    </div>
  );
}
