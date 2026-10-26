import { useState } from 'react';
import Modal from './Modal';
import { errorMessage } from '../lib/api';

interface Props {
  title: string;
  description?: string;
  confirmLabel: string;
  /** Resolves on success (dialog closes); rejects to show the error inline. */
  onConfirm: (reason: string) => Promise<unknown>;
  onClose: () => void;
}

const MAX_REASON = 500;

/** SPEC §13: every destructive action is confirmed with a mandatory reason. */
export default function ReasonDialog({ title, description, confirmLabel, onConfirm, onClose }: Props) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const trimmed = reason.trim();

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    if (!trimmed) {
      setError('A reason is required.');
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
        {description && <p className="text-sm text-gray-600">{description}</p>}
        <label className="block">
          <span className="mb-1 block text-sm font-medium text-gray-700">
            Reason <span className="text-red-600">*</span>
          </span>
          <textarea
            autoFocus
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={MAX_REASON}
            rows={3}
            className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus:border-gray-900 focus:outline-none"
            placeholder="Shown to the driver"
          />
          <span className="mt-1 block text-right text-xs text-gray-400">
            {reason.length}/{MAX_REASON}
          </span>
        </label>
        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="rounded-md border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={busy || !trimmed}
            className="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
          >
            {busy ? 'Working…' : confirmLabel}
          </button>
        </div>
      </form>
    </Modal>
  );
}
