import { dismissToast, useToasts, type Toast } from '../lib/toast';

const STYLE: Record<Toast['kind'], string> = {
  error: 'border-red-200 bg-red-50 text-red-800',
  success: 'border-green-200 bg-green-50 text-green-800',
  alert: 'border-red-300 bg-red-600 text-white shadow-lg',
};

interface Props {
  /** Toasts render outside the router, so navigation is injected. */
  onNavigate?: (to: string) => void;
}

export default function Toaster({ onNavigate }: Props) {
  const toasts = useToasts();
  return (
    <div className="pointer-events-none fixed right-4 bottom-4 z-[1200] flex w-96 max-w-[calc(100vw-2rem)] flex-col gap-2">
      {toasts.map((t) => (
        <div
          key={t.id}
          role={t.kind === 'success' ? 'status' : 'alert'}
          className={`pointer-events-auto flex items-start gap-3 rounded-md border px-4 py-3 text-sm shadow-md ${STYLE[t.kind]}`}
        >
          <div className="flex-1">
            <span>{t.message}</span>
            {t.action && (
              <a
                href={t.action.to}
                onClick={(e) => {
                  if (!onNavigate) return;
                  e.preventDefault();
                  onNavigate(t.action!.to);
                  dismissToast(t.id);
                }}
                className="ml-2 font-medium underline"
              >
                {t.action.label}
              </a>
            )}
          </div>
          <button
            type="button"
            onClick={() => dismissToast(t.id)}
            className="text-current opacity-60 hover:opacity-100"
            aria-label="Dismiss"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
