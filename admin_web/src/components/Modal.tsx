import { useEffect, type ReactNode } from 'react';

/**
 * A small accessible modal used for confirm dialogs and the reset-password form.
 * Closes on Escape and backdrop click; traps nothing fancy — the console has one
 * modal at a time.
 */
export function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <h3 className="modal-title">{title}</h3>
        {children}
      </div>
    </div>
  );
}
