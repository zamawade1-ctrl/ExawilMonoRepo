/**
 * The Xawil brand mark, inline so it can be tinted per context (white on the
 * green sign-in panel, gradient elsewhere). Geometry matches the mobile app icon.
 */
export function Logo({
  size = 40,
  variant = 'color',
}: {
  size?: number;
  variant?: 'color' | 'white';
}) {
  const isWhite = variant === 'white';
  const fg = '#FFFFFF';
  const bgId = `xawil-bg-${variant}`;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      role="img"
      aria-label="e-Xawil"
    >
      {!isWhite && (
        <defs>
          <linearGradient id={bgId} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="var(--brand-gradient-start)" />
            <stop offset="100%" stopColor="var(--brand-gradient-end)" />
          </linearGradient>
          <mask id={`phone-${variant}`}>
            <rect x="122" y="277" width="260" height="470" rx="54" fill="#fff" />
            <rect x="146" y="323" width="212" height="380" rx="26" fill="#000" />
          </mask>
          <mask id={`coin-${variant}`}>
            <circle cx="762" cy="512" r="140" fill="#fff" />
            <circle cx="762" cy="512" r="88" fill="#000" />
          </mask>
        </defs>
      )}

      {!isWhite && (
        <rect width="1024" height="1024" rx="220" fill={`url(#${bgId})`} />
      )}

      {isWhite ? (
        <>
          <WhiteMark fg={fg} />
        </>
      ) : (
        <>
          <rect x="122" y="277" width="260" height="470" rx="54" fill={fg} />
          <rect x="146" y="323" width="212" height="380" rx="26" fill={`url(#${bgId})`} />
          <rect x="224" y="303" width="56" height="8" rx="4" fill={fg} />
          <rect x="452" y="495" width="120" height="34" rx="4" fill={fg} />
          <path d="M552 440 L652 512 L552 584 Z" fill={fg} />
          <circle cx="762" cy="512" r="140" fill={fg} />
          <circle cx="762" cy="512" r="88" fill={`url(#${bgId})`} />
        </>
      )}
    </svg>
  );
}

function WhiteMark({ fg }: { fg: string }) {
  return (
    <>
      <defs>
        <mask id="phone-hole-w">
          <rect x="122" y="277" width="260" height="470" rx="54" fill="#fff" />
          <rect x="146" y="323" width="212" height="380" rx="26" fill="#000" />
        </mask>
        <mask id="coin-hole-w">
          <circle cx="762" cy="512" r="140" fill="#fff" />
          <circle cx="762" cy="512" r="88" fill="#000" />
        </mask>
      </defs>
      <rect x="122" y="277" width="260" height="470" rx="54" fill={fg} mask="url(#phone-hole-w)" />
      <rect x="224" y="303" width="56" height="8" rx="4" fill={fg} />
      <rect x="452" y="495" width="120" height="34" rx="4" fill={fg} />
      <path d="M552 440 L652 512 L552 584 Z" fill={fg} />
      <circle cx="762" cy="512" r="140" fill={fg} mask="url(#coin-hole-w)" />
    </>
  );
}
