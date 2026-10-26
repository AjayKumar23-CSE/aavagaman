import { useSyncExternalStore } from 'react';

export interface ToastAction {
  label: string;
  /** In-app path to navigate to. */
  to: string;
}

export interface Toast {
  id: number;
  kind: 'success' | 'error' | 'alert';
  message: string;
  action?: ToastAction;
}

const DURATION_MS: Record<Toast['kind'], number> = { success: 4000, error: 8000, alert: 20_000 };

let toasts: Toast[] = [];
let nextId = 1;
const listeners = new Set<() => void>();

function emit() {
  for (const l of listeners) l();
}

export function dismissToast(id: number): void {
  toasts = toasts.filter((t) => t.id !== id);
  emit();
}

function push(kind: Toast['kind'], message: string, action?: ToastAction) {
  const id = nextId++;
  toasts = [...toasts, { id, kind, message, action }];
  emit();
  setTimeout(() => dismissToast(id), DURATION_MS[kind]);
}

export const toast = {
  success: (message: string) => push('success', message),
  error: (message: string) => push('error', message),
  /** Operational alert (SOS, suspensions…): stays longer and can link to the relevant page. */
  alert: (message: string, action?: ToastAction) => push('alert', message, action),
};

export function useToasts(): Toast[] {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => toasts,
  );
}
