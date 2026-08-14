import { useEffect, useState } from 'react';
import { Logo } from '../components/Logo';
import { apiRequest, ApiError } from '../lib/api';
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
          <>
            <div className="download-version">
              <span className="download-badge">Latest</span>
              <span className="download-vname">Version {release.versionName}</span>
              <span className="download-vcode">build {release.versionCode}</span>
            </div>
            {released && (
              <div className="download-date">Released {released}</div>
            )}

            {release.releaseNotes && release.releaseNotes.trim() !== '' && (
              <div className="download-notes">
                <div className="download-notes-title">What&apos;s new</div>
                <p>{release.releaseNotes}</p>
              </div>
            )}

            {canDownload ? (
              <a
                className="download-btn"
                href={release.apkUrl}
                target="_blank"
                rel="noopener noreferrer"
                download
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
          </>
        )}
      </div>
      <p className="download-foot">
        Installs over the existing app as an update — no uninstall needed.
      </p>
    </div>
  );
}
