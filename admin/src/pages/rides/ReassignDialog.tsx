import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import Modal from '../../components/Modal';
import { errorMessage } from '../../lib/api';
import { getLive, haversineM } from '../../lib/dashboard';
import type { Ride } from '../../lib/rides';
import { formatAgo } from '../../lib/time';
import { BTN_DANGER, BTN_SECONDARY } from '../../lib/ui';

interface Props {
  ride: Ride;
  onConfirm: (driverId: string) => Promise<unknown>;
  onClose: () => void;
}

/** Candidates are the online, idle drivers from the live snapshot, nearest to the pickup first. */
export default function ReassignDialog({ ride, onConfirm, onClose }: Props) {
  const live = useQuery({ queryKey: ['live'], queryFn: getLive, refetchInterval: 5000 });
  const [choice, setChoice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const candidates = useMemo(
    () =>
      (live.data?.drivers ?? [])
        .filter((d) => d.state === 'idle' && d.driver_id !== ride.driver?.id && d.lat !== null && d.lng !== null)
        .map((d) => ({ ...d, distance_m: haversineM({ lat: d.lat!, lng: d.lng! }, ride.pickup) }))
        .sort((a, b) => a.distance_m - b.distance_m),
    [live.data, ride.driver?.id, ride.pickup],
  );

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    if (!choice) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirm(choice);
      onClose();
    } catch (err) {
      setError(errorMessage(err));
      setBusy(false);
    }
  }

  return (
    <Modal title="Reassign driver" onClose={onClose} busy={busy}>
      <form onSubmit={submit} className="space-y-4">
        <p className="text-sm text-gray-600">
          {ride.driver?.name ?? 'The current driver'} loses this ride and is told it was cancelled; the chosen driver gets it as
          accepted. Only online, idle drivers can be chosen.
        </p>
        <div className="max-h-72 overflow-y-auto rounded-md border border-gray-200">
          {live.isPending && <p className="px-4 py-6 text-center text-sm text-gray-400">Loading online drivers…</p>}
          {live.isError && <p className="px-4 py-3 text-sm text-red-700">{errorMessage(live.error)}</p>}
          {live.data && candidates.length === 0 && (
            <p className="px-4 py-6 text-center text-sm text-gray-500">No other idle drivers are online right now.</p>
          )}
          {candidates.map((d) => (
            <label key={d.driver_id} className="flex cursor-pointer items-center gap-3 border-b border-gray-100 px-4 py-2.5 text-sm last:border-b-0 hover:bg-gray-50">
              <input type="radio" name="driver" checked={choice === d.driver_id} onChange={() => setChoice(d.driver_id)} />
              <span className="flex-1">
                <span className="font-medium text-gray-900">{d.name ?? 'Unnamed driver'}</span>
                <span className="ml-2 font-mono text-xs text-gray-500">{d.reg_number ?? '—'}</span>
              </span>
              <span className="text-xs text-gray-500">
                {(d.distance_m / 1000).toFixed(1)} km away · fix {d.updated_at ? formatAgo(d.updated_at) : '?'}
              </span>
            </label>
          ))}
        </div>
        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" onClick={onClose} disabled={busy} className={BTN_SECONDARY}>
            Cancel
          </button>
          <button type="submit" disabled={busy || !choice} className={BTN_DANGER}>
            {busy ? 'Reassigning…' : 'Reassign ride'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
