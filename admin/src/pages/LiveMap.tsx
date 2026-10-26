import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import type { LatLngBoundsExpression } from 'leaflet';
import { CircleMarker, Polyline, Popup } from 'react-leaflet';
import ErrorBanner from '../components/ErrorBanner';
import LeafletMap, { FitBoundsOnce, FlyTo, InvalidateOnMount } from '../components/LeafletMap';
import StatusBadge from '../components/StatusBadge';
import { getLive, type DriverLiveState, type LiveDriver, type LiveRide } from '../lib/dashboard';
import { useLiveSnapshot, useSocketConnection, useSocketStatus } from '../lib/socket';
import { formatAgo, formatIST, formatTimeIST } from '../lib/time';
import { shortId } from '../lib/ui';

/** SPEC §13: idle green, offered amber, on_trip blue. */
const STATE_COLOUR: Record<DriverLiveState, string> = {
  idle: '#16a34a',
  offered: '#d97706',
  on_trip: '#2563eb',
  offline: '#9ca3af',
};

const PICKUP_COLOUR = '#111827';
const DROP_COLOUR = '#dc2626';
const STALE_AFTER_MS = 10_000;

function hasFix(d: LiveDriver): d is LiveDriver & { lat: number; lng: number } {
  return d.lat !== null && d.lng !== null;
}

export default function LiveMap() {
  useSocketConnection();
  const socketStatus = useSocketStatus();
  const { snapshot: streamed, receivedAt } = useLiveSnapshot();

  // REST snapshot for the first paint and as a 5 s fallback while the socket is down.
  const rest = useQuery({
    queryKey: ['live'],
    queryFn: getLive,
    refetchInterval: socketStatus === 'connected' ? false : 5000,
  });
  const snap = streamed ?? rest.data ?? null;
  const lastUpdate = receivedAt ?? (rest.dataUpdatedAt || null);

  // A clock in state (ticking once a second) keeps "x s ago" and the stale indicator honest without impure reads in render.
  const [now, setNow] = useState(0);
  useEffect(() => {
    const tick = () => setNow(Date.now());
    const t = setInterval(tick, 1000);
    tick();
    return () => clearInterval(t);
  }, []);

  const [focus, setFocus] = useState<{ lat: number; lng: number } | null>(null);
  const [selectedRide, setSelectedRide] = useState<string | null>(null);

  const drivers = useMemo(() => (snap?.drivers ?? []).filter(hasFix), [snap]);
  const rides = useMemo(
    () => [...(snap?.rides ?? [])].sort((a, b) => a.requested_at.localeCompare(b.requested_at)),
    [snap],
  );
  const rideByDriver = useMemo(() => new Map(rides.filter((r) => r.driver_id).map((r) => [r.driver_id!, r])), [rides]);

  const bounds = useMemo<LatLngBoundsExpression | null>(() => {
    const pts: [number, number][] = [
      ...drivers.map((d) => [d.lat, d.lng] as [number, number]),
      ...rides.flatMap((r) => [
        [r.pickup.lat, r.pickup.lng] as [number, number],
        [r.drop.lat, r.drop.lng] as [number, number],
      ]),
    ];
    return pts.length >= 2 ? pts : null;
  }, [drivers, rides]);

  const stale = socketStatus === 'connected' && lastUpdate !== null && now > 0 && now - lastUpdate > STALE_AFTER_MS;
  const feed =
    socketStatus === 'connected'
      ? stale
        ? { label: 'Stale', cls: 'bg-amber-100 text-amber-800' }
        : { label: 'Live', cls: 'bg-green-100 text-green-800' }
      : socketStatus === 'offline'
        ? { label: 'Offline — polling', cls: 'bg-gray-200 text-gray-700' }
        : { label: 'Reconnecting — polling', cls: 'bg-amber-100 text-amber-800' };

  const counts = (['idle', 'offered', 'on_trip'] as const).map((s) => ({
    state: s,
    n: (snap?.drivers ?? []).filter((d) => d.state === s).length,
  }));

  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col gap-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Live map</h1>
          <p className="text-sm text-gray-500">
            Online drivers and active rides, streamed every 2 s.
            {snap?.at && ` Snapshot ${formatTimeIST(snap.at)} IST.`}
          </p>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className={`rounded-full px-2.5 py-0.5 text-xs font-medium ${feed.cls}`}>{feed.label}</span>
          <span className="text-gray-500">
            Last update: {lastUpdate && now > 0 ? formatAgo(lastUpdate, now) : '—'}
          </span>
        </div>
      </div>

      {rest.isError && !snap && <ErrorBanner error={rest.error} onRetry={() => rest.refetch()} />}

      <div className="flex min-h-0 flex-1 gap-4">
        <div className="relative min-w-0 flex-1 overflow-hidden rounded-lg border border-gray-200 bg-white">
          <LeafletMap className="h-full w-full">
            <InvalidateOnMount />
            <FitBoundsOnce bounds={bounds} />
            <FlyTo target={focus} />
            {rides.map((r) => (
              <RideLayer key={r.ride_id} ride={r} selected={r.ride_id === selectedRide} onSelect={() => setSelectedRide(r.ride_id)} />
            ))}
            {drivers.map((d) => (
              <CircleMarker
                key={d.driver_id}
                center={[d.lat, d.lng]}
                radius={8}
                pathOptions={{ color: '#ffffff', weight: 2, fillColor: STATE_COLOUR[d.state], fillOpacity: 1 }}
              >
                <Popup>
                  <DriverPopup driver={d} ride={rideByDriver.get(d.driver_id)} />
                </Popup>
              </CircleMarker>
            ))}
          </LeafletMap>
          <div className="absolute right-3 bottom-3 z-[400] flex gap-3 rounded-md border border-gray-200 bg-white/95 px-3 py-2 text-xs text-gray-700">
            {counts.map((c) => (
              <span key={c.state} className="flex items-center gap-1.5">
                <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: STATE_COLOUR[c.state] }} />
                {c.state.replace('_', ' ')} {c.n}
              </span>
            ))}
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2.5 w-2.5 rounded-full border-2 border-white ring-1 ring-gray-900" style={{ background: PICKUP_COLOUR }} />
              pickup
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: DROP_COLOUR }} />
              drop
            </span>
          </div>
        </div>

        <aside className="flex w-80 shrink-0 flex-col overflow-hidden rounded-lg border border-gray-200 bg-white">
          <div className="border-b border-gray-200 px-4 py-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-500">
              Active rides <span className="ml-1 text-gray-400">{rides.length}</span>
            </h2>
          </div>
          <ul className="flex-1 divide-y divide-gray-100 overflow-y-auto">
            {rides.map((r) => (
              <li
                key={r.ride_id}
                className={`cursor-pointer px-4 py-3 text-sm hover:bg-gray-50 ${r.ride_id === selectedRide ? 'bg-gray-50' : ''}`}
                onClick={() => {
                  setSelectedRide(r.ride_id);
                  setFocus({ lat: r.pickup.lat, lng: r.pickup.lng });
                }}
              >
                <div className="flex items-center justify-between gap-2">
                  <Link to={`/rides/${r.ride_id}`} className="font-mono text-xs text-gray-700 hover:underline" onClick={(e) => e.stopPropagation()}>
                    {shortId(r.ride_id)}
                  </Link>
                  <StatusBadge status={r.status} />
                </div>
                <div className="mt-1 truncate text-gray-900">{r.pickup.address}</div>
                <div className="truncate text-gray-500">→ {r.drop.address}</div>
                <div className="mt-1 text-xs text-gray-500">
                  {r.rider_name ?? 'Rider'} · {r.driver_name ?? 'no driver yet'} · {formatTimeIST(r.requested_at)}
                </div>
              </li>
            ))}
            {snap && rides.length === 0 && <li className="px-4 py-8 text-center text-sm text-gray-500">No active rides.</li>}
            {!snap && <li className="px-4 py-8 text-center text-sm text-gray-400">Loading…</li>}
          </ul>
          <div className="border-t border-gray-200 px-4 py-3 text-xs text-gray-500">
            {snap ? `${snap.drivers.length} online driver${snap.drivers.length === 1 ? '' : 's'}` : ''}
            {snap && drivers.length < snap.drivers.length && ` (${snap.drivers.length - drivers.length} without a GPS fix)`}
          </div>
        </aside>
      </div>
    </div>
  );
}

function RideLayer({ ride, selected, onSelect }: { ride: LiveRide; selected: boolean; onSelect: () => void }) {
  const line: [number, number][] = [
    [ride.pickup.lat, ride.pickup.lng],
    [ride.drop.lat, ride.drop.lng],
  ];
  const popup = (
    <Popup>
      <RidePopup ride={ride} />
    </Popup>
  );
  return (
    <>
      <Polyline
        positions={line}
        pathOptions={{ color: selected ? '#2563eb' : '#374151', weight: selected ? 4 : 2, dashArray: '6 6', opacity: 0.8 }}
        eventHandlers={{ click: onSelect }}
      >
        {popup}
      </Polyline>
      <CircleMarker center={line[0]} radius={5} pathOptions={{ color: '#ffffff', weight: 2, fillColor: PICKUP_COLOUR, fillOpacity: 1 }} eventHandlers={{ click: onSelect }}>
        {popup}
      </CircleMarker>
      <CircleMarker center={line[1]} radius={5} pathOptions={{ color: '#ffffff', weight: 2, fillColor: DROP_COLOUR, fillOpacity: 1 }} eventHandlers={{ click: onSelect }}>
        {popup}
      </CircleMarker>
    </>
  );
}

function RidePopup({ ride }: { ride: LiveRide }) {
  return (
    <div className="space-y-1 text-sm">
      <div className="flex items-center gap-2">
        <span className="font-mono text-xs">{shortId(ride.ride_id)}</span>
        <StatusBadge status={ride.status} />
      </div>
      <div>
        <span className="text-gray-500">From</span> {ride.pickup.address}
      </div>
      <div>
        <span className="text-gray-500">To</span> {ride.drop.address}
      </div>
      <div>
        <span className="text-gray-500">Rider</span> {ride.rider_name ?? '—'} · <span className="text-gray-500">Driver</span>{' '}
        {ride.driver_name ?? '—'}
      </div>
      <div className="text-xs text-gray-500">Requested {formatIST(ride.requested_at)} IST</div>
      <Link to={`/rides/${ride.ride_id}`} className="font-medium text-blue-700 underline">
        Open ride
      </Link>
    </div>
  );
}

function DriverPopup({ driver, ride }: { driver: LiveDriver; ride: LiveRide | undefined }) {
  return (
    <div className="space-y-1 text-sm">
      <div className="flex items-center gap-2">
        <span className="font-medium">{driver.name ?? 'Unnamed driver'}</span>
        <StatusBadge status={driver.state} />
      </div>
      <div className="font-mono text-xs text-gray-700">{driver.reg_number ?? '—'}</div>
      <div className="text-xs text-gray-500">
        Heading {Math.round(driver.heading)}° · fix {driver.updated_at ? formatAgo(driver.updated_at) : 'unknown'}
      </div>
      <div className="flex gap-3">
        <Link to={`/drivers/${driver.driver_id}`} className="font-medium text-blue-700 underline">
          Driver profile
        </Link>
        {ride && (
          <Link to={`/rides/${ride.ride_id}`} className="font-medium text-blue-700 underline">
            Current ride
          </Link>
        )}
      </div>
    </div>
  );
}
