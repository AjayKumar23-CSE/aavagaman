import { useCallback, useState } from 'react';
import { Link, useParams } from 'react-router';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import Card, { Field } from '../../components/Card';
import ConfirmDialog from '../../components/ConfirmDialog';
import ErrorBanner from '../../components/ErrorBanner';
import ReasonDialog from '../../components/ReasonDialog';
import StatusBadge from '../../components/StatusBadge';
import { errorMessage } from '../../lib/api';
import {
  adjustFare,
  cancelRide,
  getRide,
  markCash,
  reassignRide,
  RIDE_ACTIONS,
  type Ride,
  type RideAction,
  type RideEvent,
} from '../../lib/rides';
import { useSocketEvents, type RideStatusEvent } from '../../lib/socket';
import { formatDuration, formatINR, formatIST, formatKm } from '../../lib/time';
import { toast } from '../../lib/toast';
import { BTN_DANGER, BTN_SUCCESS, shortId } from '../../lib/ui';
import AdjustFareDialog from './AdjustFareDialog';
import ReassignDialog from './ReassignDialog';
import RideMap from './RideMap';

const ACTIVE = ['REQUESTED', 'ACCEPTED', 'ARRIVED', 'STARTED'];

const TIMESTAMPS: { key: keyof Ride; label: string }[] = [
  { key: 'requested_at', label: 'Requested' },
  { key: 'accepted_at', label: 'Accepted' },
  { key: 'arrived_at', label: 'Arrived' },
  { key: 'started_at', label: 'Started' },
  { key: 'completed_at', label: 'Completed' },
  { key: 'paid_at', label: 'Paid' },
  { key: 'cancelled_at', label: 'Cancelled' },
];

function describeEvent(e: RideEvent): string {
  const meta = e.meta ?? {};
  if (meta.type === 'fare_adjusted') return `Fare adjusted ${formatINR(Number(meta.from))} → ${formatINR(Number(meta.to))}`;
  if (e.from_status === null) return `Ride ${e.to_status.toLowerCase()}`;
  if (e.from_status === e.to_status) return `Updated while ${e.to_status.toLowerCase()}`;
  return `${e.from_status.toLowerCase()} → ${e.to_status.toLowerCase().replace('_', ' ')}`;
}

function metaLines(meta: Record<string, unknown> | null): string[] {
  if (!meta) return [];
  return Object.entries(meta)
    .filter(([k, v]) => k !== 'type' && v !== null && v !== undefined && v !== '')
    .map(([k, v]) => `${k.replace(/_/g, ' ')}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`);
}

export default function RideDetail() {
  const { id = '' } = useParams();
  const queryClient = useQueryClient();
  const [dialog, setDialog] = useState<RideAction | null>(null);

  const query = useQuery({
    queryKey: ['ride', id],
    queryFn: () => getRide(id),
    refetchInterval: (q) => (q.state.data && ACTIVE.includes(q.state.data.ride.status) ? 15_000 : false),
  });

  // Live status pushes (SPEC §8 ride:status reaches admins) refresh the page without polling.
  const onRideStatus = useCallback(
    (e: RideStatusEvent) => {
      if (e.ride_id === id) void queryClient.invalidateQueries({ queryKey: ['ride', id] });
    },
    [id, queryClient],
  );
  useSocketEvents({ onRideStatus });

  const afterAction = (message: string) => {
    void queryClient.invalidateQueries({ queryKey: ['ride', id] });
    void queryClient.invalidateQueries({ queryKey: ['rides'] });
    void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    toast.success(message);
  };

  const cancelMut = useMutation({ mutationFn: (reason: string) => cancelRide(id, reason), onSuccess: () => afterAction('Ride cancelled') });
  const reassignMut = useMutation({ mutationFn: (driverId: string) => reassignRide(id, driverId), onSuccess: () => afterAction('Ride reassigned') });
  const fareMut = useMutation({
    mutationFn: ({ fare, reason }: { fare: number; reason: string }) => adjustFare(id, fare, reason),
    onSuccess: () => afterAction('Fare adjusted'),
  });
  const cashMut = useMutation({ mutationFn: () => markCash(id), onSuccess: () => afterAction('Marked as paid in cash') });

  if (query.isPending) return <p className="text-sm text-gray-500">Loading ride…</p>;
  if (query.isError || !query.data) {
    return (
      <div className="space-y-4">
        <Link to="/rides" className="text-sm text-gray-600 hover:text-gray-900">
          ← Rides
        </Link>
        <ErrorBanner error={query.error} onRetry={() => query.refetch()} />
      </div>
    );
  }

  const { ride, events, offers, payment, track, calls = [] } = query.data;
  const applicable = RIDE_ACTIONS.filter((a) => a.from.includes(ride.status));

  return (
    <div className="space-y-6">
      <Link to="/rides" className="text-sm text-gray-600 hover:text-gray-900">
        ← Rides
      </Link>

      <section className="rounded-lg border border-gray-200 bg-white p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-semibold text-gray-900">
                Ride <span className="font-mono">{shortId(ride.id)}</span>
              </h1>
              <StatusBadge status={ride.status} />
              <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium capitalize text-gray-700">{ride.payment_method}</span>
            </div>
            <p className="mt-1 text-sm text-gray-500">
              Requested {formatIST(ride.requested_at)} IST
              {query.isFetching && ' · refreshing…'}
            </p>
            <p className="font-mono text-xs text-gray-400">{ride.id}</p>
          </div>
          <div className="flex flex-col items-end gap-2">
            <div className="flex flex-wrap justify-end gap-2">
              {RIDE_ACTIONS.map((a) => {
                const ok = a.from.includes(ride.status);
                return (
                  <button
                    key={a.action}
                    type="button"
                    disabled={!ok}
                    title={ok ? undefined : `Only for ${a.from.map((s) => s.toLowerCase()).join(', ')} rides`}
                    onClick={() => setDialog(a.action)}
                    className={a.destructive ? BTN_DANGER : BTN_SUCCESS}
                  >
                    {a.label}
                  </button>
                );
              })}
            </div>
            <p className="text-xs text-gray-500">
              {applicable.length
                ? `Available for a ${ride.status.toLowerCase().replace('_', ' ')} ride: ${applicable.map((a) => a.label.toLowerCase()).join(', ')}.`
                : `No admin actions apply to a ${ride.status.toLowerCase().replace('_', ' ')} ride.`}
            </p>
          </div>
        </div>
        {ride.status === 'CANCELLED' && (
          <div className="mt-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-800">
            Cancelled by <span className="font-medium">{ride.cancelled_by ?? 'unknown'}</span>
            {ride.cancel_reason && <> — {ride.cancel_reason}</>}
            {(ride.cancellation_fee ?? 0) > 0 && <> · fee {formatINR(ride.cancellation_fee)}</>}
          </div>
        )}
      </section>

      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card title="Route and GPS track" flush>
            <RideMap ride={ride} track={track} />
          </Card>

          <Card title="Timeline">
            <ol className="relative space-y-4 border-l border-gray-200 pl-5">
              {events.map((e) => (
                <li key={e.id} className="relative">
                  <span className="absolute -left-[26px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-white bg-gray-400 ring-1 ring-gray-300" />
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <span className="text-sm font-medium text-gray-900 capitalize">{describeEvent(e)}</span>
                    <span className="text-xs text-gray-500">{formatIST(e.at)} IST</span>
                  </div>
                  <div className="text-xs text-gray-500">
                    by {e.actor}
                    {e.actor_id && <span className="font-mono"> {shortId(e.actor_id)}</span>}
                  </div>
                  {metaLines(e.meta).map((line) => (
                    <div key={line} className="text-xs text-gray-600">
                      {line}
                    </div>
                  ))}
                </li>
              ))}
              {events.length === 0 && <li className="text-sm text-gray-500">No events recorded.</li>}
            </ol>
          </Card>

          <Card title={`Offers (${offers.length})`} flush>
            <table className="w-full text-left text-sm">
              <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-5 py-2 font-medium">Driver</th>
                  <th className="px-5 py-2 font-medium">Distance to pickup</th>
                  <th className="px-5 py-2 font-medium">Offered (IST)</th>
                  <th className="px-5 py-2 font-medium">Responded</th>
                  <th className="px-5 py-2 font-medium">Response</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {offers.map((o) => (
                  <tr key={o.id}>
                    <td className="px-5 py-2">
                      <Link to={`/drivers/${o.driver_id}`} className="text-gray-900 hover:underline">
                        {o.driver_name ?? shortId(o.driver_id)}
                      </Link>
                    </td>
                    <td className="px-5 py-2 text-gray-700">{formatKm(o.distance_to_pickup_m)}</td>
                    <td className="px-5 py-2 whitespace-nowrap text-gray-700">{formatIST(o.offered_at)}</td>
                    <td className="px-5 py-2 whitespace-nowrap text-gray-700">{o.responded_at ? formatIST(o.responded_at) : '—'}</td>
                    <td className="px-5 py-2">{o.response === 'accepted' ? <StatusBadge status="approved" /> : o.response === 'rejected' ? <StatusBadge status="rejected" /> : o.response ? <span className="text-gray-500">{o.response}</span> : <span className="text-gray-400">awaiting</span>}</td>
                  </tr>
                ))}
                {offers.length === 0 && (
                  <tr>
                    <td colSpan={5} className="px-5 py-6 text-center text-gray-500">
                      No offers were made.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </Card>
        </div>

        <div className="space-y-6">
          <Card title={`Calls (${calls.length})`} flush>
            <table className="w-full text-left text-sm">
              <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-5 py-2 font-medium">When (IST)</th>
                  <th className="px-5 py-2 font-medium">From</th>
                  <th className="px-5 py-2 font-medium">Outcome</th>
                  <th className="px-5 py-2 font-medium">Talk time</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {calls.map((c) => (
                  <tr key={c.id}>
                    <td className="px-5 py-2 whitespace-nowrap text-gray-700">{formatIST(c.created_at)}</td>
                    <td className="px-5 py-2 text-gray-700">{c.caller_id === ride.rider?.id ? 'Rider → driver' : 'Driver → rider'}</td>
                    <td className="px-5 py-2">
                      {c.status === 'completed' ? <StatusBadge status="approved" /> : c.status === 'failed' ? <StatusBadge status="rejected" /> : <span className="capitalize text-gray-500">{c.status.replace('_', ' ')}</span>}
                      {c.failure_reason && <div className="mt-1 max-w-56 text-xs text-red-700">{c.failure_reason}</div>}
                    </td>
                    <td className="px-5 py-2 text-gray-700">{c.duration_s != null ? `${Math.floor(c.duration_s / 60)}:${String(c.duration_s % 60).padStart(2, '0')}` : '—'}</td>
                  </tr>
                ))}
                {calls.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-5 py-4 text-center text-gray-500">
                      No calls were made. Calls go through the Aavagaman number, so neither side sees the other's phone.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </Card>

          <Card title="Trip">
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
              <div className="col-span-2">
                <dt className="text-xs text-gray-500">Pickup</dt>
                <dd className="text-sm text-gray-900">{ride.pickup.address}</dd>
                <dd className="font-mono text-xs text-gray-400">
                  {ride.pickup.lat.toFixed(5)}, {ride.pickup.lng.toFixed(5)}
                </dd>
              </div>
              <div className="col-span-2">
                <dt className="text-xs text-gray-500">Drop</dt>
                <dd className="text-sm text-gray-900">{ride.drop.address}</dd>
                <dd className="font-mono text-xs text-gray-400">
                  {ride.drop.lat.toFixed(5)}, {ride.drop.lng.toFixed(5)}
                </dd>
              </div>
              <Field label="Estimated distance / time">
                {formatKm(ride.est_distance_m)} · {formatDuration(ride.est_duration_s)}
              </Field>
              <Field label="Actual distance / time">
                {formatKm(ride.actual_distance_m)} · {formatDuration(ride.actual_duration_s)}
              </Field>
              <Field label="Estimated fare">
                {ride.est_fare_min !== null ? `${formatINR(ride.est_fare_min)}–${formatINR(ride.est_fare_max)}` : null}
              </Field>
              <Field label="Final fare">{ride.final_fare !== null ? formatINR(ride.final_fare) : null}</Field>
              <Field label="Cancellation fee">{(ride.cancellation_fee ?? 0) > 0 ? formatINR(ride.cancellation_fee) : '₹0'}</Field>
              <Field label="Amount due">{ride.amount_due !== null ? <span className="font-semibold">{formatINR(ride.amount_due)}</span> : null}</Field>
              <Field label="Trip OTP">
                <span className="font-mono">{ride.trip_otp}</span>
                {ride.otp_attempts > 0 && <span className={`ml-2 text-xs ${ride.otp_attempts >= 3 ? 'text-red-700' : 'text-amber-700'}`}>{ride.otp_attempts} wrong attempt{ride.otp_attempts === 1 ? '' : 's'}</span>}
              </Field>
              <Field label="Vehicle type">{ride.vehicle_type}</Field>
              {TIMESTAMPS.filter((t) => ride[t.key]).map((t) => (
                <Field key={t.key} label={`${t.label} (IST)`}>
                  {formatIST(ride[t.key] as string)}
                </Field>
              ))}
            </dl>
            <p className="mt-4 text-xs text-gray-500">
              Share token <span className="font-mono">{ride.share_token}</span> · fare config{' '}
              <Link to="/fare-config" className="font-mono underline">
                {shortId(ride.fare_config_id)}
              </Link>{' '}
              ·{' '}
              <Link to={`/audit?entity=ride&entity_id=${ride.id}`} className="underline">
                audit trail
              </Link>
            </p>
          </Card>

          <Card title="Rider">
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
              <Field label="Name">{ride.rider.name}</Field>
              <Field label="Phone">
                <span className="font-mono">{ride.rider.phone}</span>
              </Field>
              <Field label="Rating">{ride.rider.rating?.toFixed(2)}</Field>
              <Field label="History">
                <Link to={`/rides?rider_id=${ride.rider.id}`} className="underline">
                  All rides
                </Link>
              </Field>
            </dl>
          </Card>

          <Card title="Driver">
            {ride.driver ? (
              <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
                <Field label="Name">
                  <Link to={`/drivers/${ride.driver.id}`} className="underline">
                    {ride.driver.name ?? 'Unnamed'}
                  </Link>
                </Field>
                <Field label="Phone">
                  <span className="font-mono">{ride.driver.phone}</span>
                </Field>
                <Field label="Rating">{ride.driver.rating?.toFixed(2)}</Field>
                <Field label="Vehicle">
                  {ride.driver.vehicle ? (
                    <>
                      <span className="font-mono">{ride.driver.vehicle.reg_number}</span> · {ride.driver.vehicle.colour} {ride.driver.vehicle.make}{' '}
                      {ride.driver.vehicle.model}
                    </>
                  ) : null}
                </Field>
                <Field label="History">
                  <Link to={`/rides?driver_id=${ride.driver.id}`} className="underline">
                    All rides
                  </Link>
                </Field>
              </dl>
            ) : (
              <p className="text-sm text-gray-500">No driver assigned.</p>
            )}
          </Card>

          <Card title="Payment">
            {payment ? (
              <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
                <Field label="Status">
                  <StatusBadge status={payment.status} />
                </Field>
                <Field label="Method">
                  <span className="capitalize">{payment.method}</span>
                </Field>
                <Field label="Amount">{formatINR(payment.amount)}</Field>
                <Field label="Paid (IST)">{payment.paid_at ? formatIST(payment.paid_at) : null}</Field>
                <Field label="Gateway order">
                  <span className="font-mono text-xs">{payment.gateway_order_id ?? '—'}</span>
                </Field>
                <Field label="Gateway payment">
                  <span className="font-mono text-xs">{payment.gateway_payment_id ?? '—'}</span>
                </Field>
              </dl>
            ) : (
              <p className="text-sm text-gray-500">No payment record yet{ACTIVE.includes(ride.status) ? ' — created when the trip completes.' : '.'}</p>
            )}
          </Card>
        </div>
      </div>

      {dialog === 'cancel' && (
        <ReasonDialog
          title="Cancel ride"
          description={`The ride is cancelled on behalf of the platform with no fee${ride.driver ? `; ${ride.driver.name ?? 'the driver'} is released` : ''}. Rider and driver are notified.`}
          confirmLabel="Cancel ride"
          onConfirm={(reason) => cancelMut.mutateAsync(reason)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog === 'reassign' && (
        <ReassignDialog ride={ride} onConfirm={(driverId) => reassignMut.mutateAsync(driverId)} onClose={() => setDialog(null)} />
      )}
      {dialog === 'adjust-fare' && (
        <AdjustFareDialog ride={ride} onConfirm={(fare, reason) => fareMut.mutateAsync({ fare, reason })} onClose={() => setDialog(null)} />
      )}
      {dialog === 'mark-cash' && (
        <ConfirmDialog
          title="Mark cash collected"
          description={
            <>
              Records that the driver received <span className="font-semibold">{formatINR(ride.amount_due)}</span> in cash and marks the ride paid.
              Use this only when the driver cannot do it from the app.
            </>
          }
          confirmLabel="Mark as paid in cash"
          onConfirm={() => cashMut.mutateAsync().catch((e) => Promise.reject(new Error(errorMessage(e))))}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}
