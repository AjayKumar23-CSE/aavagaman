import { useState, type ReactNode } from 'react';
import Modal from './Modal';
import { errorMessage } from '../lib/api';
import { BTN_DANGER, BTN_PRIMARY, BTN_SECONDARY, INPUT, LABEL } from '../lib/ui';

interface NoteField {
  label: string;
  placeholder?: string;
  required?: boolean;
  maxLength?: number;
}

interface Props {
  title: string;
  description?: ReactNode;
  confirmLabel: string;
  tone?: 'danger' | 'primary';
  /** Optional free-text field (e.g. a payment reference or an unblock note). */
  note?: NoteField;
  /** Resolves on success (dialog closes); rejects to show the error inline. */
  onConfirm: (note: string) => Promise<unknown>;
  onClose: () => void;
}

/** Confirmation for actions that need no mandatory reason (ReasonDialog covers the destructive ones). */
export default function ConfirmDialog({ title, description, confirmLabel, tone = 'primary', note, onConfirm, onClose }: Props) {
  const [value, setValue] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const trimmed = value.trim();
  const blocked = !!note?.required && !trimmed;

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    if (blocked) {
      setError(`${note!.label} is required.`);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onConfirm(trimmed);
      onClose();
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <Modal title={title} onClose={onClose} busy={busy}>
      <form onSubmit={submit} className="space-y-4">
        {description && <div className="text-sm text-gray-600">{description}</div>}
        {note && (
          <label className="block">
            <span className={LABEL}>
              {note.label} {note.required && <span className="text-red-600">*</span>}
            </span>
            <input
              autoFocus
              value={value}
              onChange={(e) => setValue(e.target.value)}
              maxLength={note.maxLength ?? 120}
              placeholder={note.placeholder}
              className={INPUT}
            />
          </label>
        )}
        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy} className={BTN_SECONDARY}>
            Cancel
          </button>
          <button type="submit" disabled={busy || blocked} className={tone === 'danger' ? BTN_DANGER : BTN_PRIMARY}>
            {busy ? 'Working…' : confirmLabel}
          </button>
        </div>
      </form>
    </Modal>
  );
}
