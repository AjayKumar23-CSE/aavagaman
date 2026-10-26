import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import ErrorBanner from '../../components/ErrorBanner';
import Pagination from '../../components/Pagination';
import StatusBadge from '../../components/StatusBadge';
import { listRides, RIDE_STATUSES, type RideStatus } from '../../lib/rides';
import { addDays, formatINR, formatIST, istDayStartISO } from '../../lib/time';
import { INPUT, LABEL, UUID_RE } from '../../lib/ui';

const LIMIT = 20;
const YMD_RE = /^\d{4}-\d{2}-\d{2}$/;

function parseStatus(v: string | null): RideStatus | '' {
  return RIDE_STATUSES.includes(v as RideStatus) ? (v as RideStatus) : '';
}

/** Debounced id input; the parent remounts it (via `key`) when filters are cleared. */
function IdFilter({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const [text, setText] = useState(value);
  useEffect(() => {
    const v = text.trim();
    if (v === value) return;
    const t = setTimeout(() => onChange(v), 300);
    return () => clearTimeout(t);
  }, [text, value, onChange]);
  const invalid = text.trim() !== '' && !UUID_RE.test(text.trim());
  return (
    <label className="block">
      <span className={LABEL}>{label}</span>
      <input
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder="UUID"
        spellCheck={false}
        className={`${INPUT} font-mono ${invalid ? 'border-red-400' : ''}`}
      />
      {invalid && <span className="mt-1 block text-xs text-red-600">Not a valid id; filter ignored.</span>}
    </label>
  );
}

export default function RidesList() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const status = parseStatus(params.get('status'));
  const from = YMD_RE.test(params.get('from') ?? '') ? params.get('from')! : '';
  const to = YMD_RE.test(params.get('to') ?? '') ? params.get('to')! : '';
  const driverId = params.get('driver_id') ?? '';
  const riderId = params.get('rider_id') ?? '';
  const page = Math.max(1, Number(params.get('page')) || 1);
  // Bumped by "Clear filters" so the debounced text inputs reset too.
  const [resetKey, setResetKey] = useState(0);

  const update = useCallback(
    (next: Record<string, string | number | undefined>) =>
      setParams(
        (prev) => {
          const p = new URLSearchParams(prev);
          for (const [k, v] of Object.entries(next)) {
            if (v === '' || v === undefined || (k === 'page' && v === 1)) p.delete(k);
            else p.set(k, String(v));
          }
          return p;
        },
        { replace: true },
      ),
    [setParams],
  );
  const setDriver = useCallback((v: string) => update({ driver_id: v, page: 1 }), [update]);
  const setRider = useCallback((v: string) => update({ rider_id: v, page: 1 }), [update]);

  const query = useQuery({
    queryKey: ['rides', { status, from, to, driverId, riderId, page }],
    queryFn: () =>
      listRides({
        status: status || undefined,
        from: from ? istDayStartISO(from) : undefined,
        // `to` is exclusive on the server; include the whole selected day.
        to: to ? istDayStartISO(addDays(to, 1)) : undefined,
        driver_id: UUID_RE.test(driverId) ? driverId : undefined,
        rider_id: UUID_RE.test(riderId) ? riderId : undefined,
        page,
        limit: LIMIT,
      }),
    placeholderData: keepPreviousData,
  });

  const anyFilter = status || from || to || driverId || riderId;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Rides</h1>
          <p className="text-sm text-gray-500">Every ride request, newest first. Dates are IST calendar days.</p>
        </div>
        {anyFilter && (
          <button
            type="button"
            onClick={() => {
              setParams({}, { replace: true });
              setResetKey((k) => k + 1);
            }}
            className="text-sm text-gray-600 underline hover:text-gray-900"
          >
            Clear filters
          </button>
        )}
      </div>

      <div className="grid gap-3 rounded-lg border border-gray-200 bg-white p-4 md:grid-cols-3 xl:grid-cols-5">
        <label className="block">
          <span className={LABEL}>Status</span>
          <select value={status} onChange={(e) => update({ status: e.target.value, page: 1 })} className={INPUT}>
            <option value="">All</option>
            {RIDE_STATUSES.map((s) => (
              <option key={s} value={s}>
                {s.replace('_', ' ')}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className={LABEL}>Requested from</span>
          <input type="date" value={from} max={to || undefined} onChange={(e) => update({ from: e.target.value, page: 1 })} className={INPUT} />
        </label>
        <label className="block">
          <span className={LABEL}>Requested to</span>
          <input type="date" value={to} min={from || undefined} onChange={(e) => update({ to: e.target.value, page: 1 })} className={INPUT} />
        </label>
        <IdFilter key={`d${resetKey}`} label="Driver id" value={driverId} onChange={setDriver} />
        <IdFilter key={`r${resetKey}`} label="Rider id" value={riderId} onChange={setRider} />
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Requested (IST)</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 font-medium">Route</th>
              <th className="px-4 py-3 font-medium">Rider</th>
              <th className="px-4 py-3 font-medium">Driver</th>
              <th className="px-4 py-3 font-medium">Payment</th>
              <th className="px-4 py-3 text-right font-medium">Fare</th>
            </tr>
          </thead>
          <tbody className={`divide-y divide-gray-100 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
            {query.data?.data.map((r) => (
              <tr key={r.id} onClick={() => navigate(`/rides/${r.id}`)} className="cursor-pointer hover:bg-gray-50">
                <td className="px-4 py-3 whitespace-nowrap text-gray-700">
                  <a href={`/rides/${r.id}`} onClick={(e) => e.preventDefault()} className="hover:underline">
                    {formatIST(r.requested_at)}
                  </a>
                  <div className="font-mono text-xs text-gray-400">{r.id.slice(0, 8)}</div>
                </td>
                <td className="px-4 py-3">
                  <StatusBadge status={r.status} />
                </td>
                <td className="max-w-xs px-4 py-3">
                  <div className="truncate text-gray-900">{r.pickup.address}</div>
                  <div className="truncate text-gray-500">→ {r.drop.address}</div>
                </td>
                <td className="px-4 py-3">
                  <div className="text-gray-900">{r.rider.name ?? '—'}</div>
                  <div className="font-mono text-xs text-gray-500">{r.rider.phone_masked}</div>
                </td>
                <td className="px-4 py-3">
                  {r.driver ? (
                    <>
                      <div className="text-gray-900">{r.driver.name ?? '—'}</div>
                      <div className="font-mono text-xs text-gray-500">{r.driver.vehicle?.reg_number ?? r.driver.phone_masked}</div>
                    </>
                  ) : (
                    <span className="text-gray-400">—</span>
                  )}
                </td>
                <td className="px-4 py-3 capitalize text-gray-700">{r.payment_method}</td>
                <td className="px-4 py-3 text-right whitespace-nowrap text-gray-900">
                  {r.final_fare !== null ? (
                    formatINR(r.amount_due ?? r.final_fare)
                  ) : (
                    <span className="text-gray-500">
                      {r.est_fare_min !== null ? `${formatINR(r.est_fare_min)}–${formatINR(r.est_fare_max)}` : '—'}
                    </span>
                  )}
                </td>
              </tr>
            ))}
            {query.isPending && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
            {query.data && query.data.data.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-gray-500">
                  No rides match these filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <Pagination page={page} limit={LIMIT} total={query.data?.total ?? 0} onPage={(p) => update({ page: p })} />
    </div>
  );
}
