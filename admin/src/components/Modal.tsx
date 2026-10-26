import { useEffect, type ReactNode } from 'react';

interface Props {
  title: string;
  onClose: () => void;
  children: ReactNode;
  /** Prevents closing while a request is in flight. */
  busy?: boolean;
}

export default function Modal({ title, onClose, children, busy }: Props) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !busy) onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, busy]);

  return (
    <div
      // Above Leaflet's panes and controls (z-index up to 1000).
      className="fixed inset-0 z-[1100] flex items-center justify-center bg-gray-900/40 p-4"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget && !busy) onClose();
      }}
    >
      <div role="dialog" aria-modal="true" aria-label={title} className="w-full max-w-lg rounded-lg bg-white shadow-xl">
        <div className="border-b border-gray-200 px-5 py-3">
          <h2 className="text-base font-semibold text-gray-900">{title}</h2>
        </div>
        <div className="p-5">{children}</div>
      </div>
    </div>
  );
}
