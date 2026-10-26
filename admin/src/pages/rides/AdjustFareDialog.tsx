import { useState } from 'react';
import Modal from '../../components/Modal';
import { errorMessage } from '../../lib/api';
import type { Ride } from '../../lib/rides';
import { formatINR } from '../../lib/time';
import { BTN_DANGER, BTN_SECONDARY, INPUT, LABEL } from '../../lib/ui';

interface Props {
  ride: Ride;
  onConfirm: (finalFare: number, reason: string) => Promise<unknown>;
  onClose: () => void;
}

const MAX_REASON = 300;

export default function AdjustFareDialog({ ride, onConfirm, onClose }: Props) {
  const [fare, setFare] = useState(ride.final_fare !== null ? String(ride.final_fare) : '');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const value = Number(fare);
  const validFare = fare.trim() !== '' && Number.isFinite(value) && value >= 0;
  const trimmed = reason.trim();
  const fee = ride.cancellation_fee ?? 0;

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    if (!validFare || !trimmed) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirm(Math.round(value * 100) / 100, trimmed);
      onClose();
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <Modal title="Adjust fare" onClose={onClose} busy={busy}>
      <form onSubmit={submit} className="space-y-4">
        <p className="text-sm text-gray-600">
          Current final fare {formatINR(ride.final_fare)}
          {ride.est_fare_min !== null && ` (estimate ${formatINR(ride.est_fare_min)}–${formatINR(ride.est_fare_max)})`}. The change is
          logged in the audit trail and a pending online payment picks up the new amount.
        </p>
        <label className="block">
          <span className={LABEL}>
            New final fare (₹) <span className="text-red-600">*</span>
          </span>
          <input
            type="number"
            min={0}
            step="0.01"
            autoFocus
            value={fare}
            onChange={(e) => setFare(e.target.value)}
            className={INPUT}
          />
          {validFare && fee > 0 && (
            <span className="mt-1 block text-xs text-gray-500">
              Rider pays {formatINR(value + fee)} including a {formatINR(fee)} carried-over cancellation fee.
            </span>
          )}
        </label>
        <label className="block">
          <span className={LABEL}>
            Reason <span className="text-red-600">*</span>
          </span>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            maxLength={MAX_REASON}
            rows={3}
            className={INPUT}
            placeholder="e.g. Meter dispute resolved in rider's favour"
          />
          <span className="mt-1 block text-right text-xs text-gray-400">
            {reason.length}/{MAX_REASON}
          </span>
        </label>
        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy} className={BTN_SECONDARY}>
            Cancel
          </button>
          <button type="submit" disabled={busy || !validFare || !trimmed} className={BTN_DANGER}>
            {busy ? 'Saving…' : 'Adjust fare'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
