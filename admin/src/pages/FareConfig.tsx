import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import Card from '../components/Card';
import ErrorBanner from '../components/ErrorBanner';
import StatusBadge from '../components/StatusBadge';
import { errorMessage } from '../lib/api';
import { createFareConfig, listFareConfigs, previewFare, type FareConfig, type FareConfigInput, type FarePreview } from '../lib/fareConfig';
import { formatINR, formatIST, fromISTDateTimeLocal } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_PRIMARY, BTN_SECONDARY, INPUT, LABEL, shortId } from '../lib/ui';
import { VEHICLE_TYPES, type VehicleTypeId } from '../lib/drivers';

type NumKey = 'base_fare' | 'per_km' | 'per_min' | 'min_fare' | 'cancellation_fee' | 'night_multiplier' | 'commission_pct' | 'gst_pct';

const FIELDS: { key: NumKey; label: string; step: string; min: number; hint?: string }[] = [
  { key: 'base_fare', label: 'Base fare (₹)', step: '1', min: 0 },
  { key: 'per_km', label: 'Per km (₹)', step: '0.5', min: 0 },
  { key: 'per_min', label: 'Per minute (₹)', step: '0.1', min: 0 },
  { key: 'min_fare', label: 'Minimum fare (₹)', step: '1', min: 0 },
  { key: 'cancellation_fee', label: 'Cancellation fee (₹)', step: '1', min: 0 },
  { key: 'night_multiplier', label: 'Night multiplier', step: '0.05', min: 1, hint: '22:00–06:00 IST when enabled' },
  { key: 'commission_pct', label: 'Commission (%)', step: '0.5', min: 0 },
  { key: 'gst_pct', label: 'GST (%)', step: '0.5', min: 0 },
];

type Form = Record<NumKey, string> & { night_enabled: boolean; effective_from: string };

const BASE_DEFAULTS = { night_multiplier: '1', commission_pct: '15', gst_pct: '5', night_enabled: false, effective_from: '' };

/** Starting values per vehicle class, same as the seed (D-056). */
const DEFAULTS: Record<VehicleTypeId, Form> = {
  bike: { ...BASE_DEFAULTS, base_fare: '20', per_km: '6', per_min: '1', min_fare: '30', cancellation_fee: '10' },
  auto: { ...BASE_DEFAULTS, base_fare: '30', per_km: '9', per_min: '1', min_fare: '40', cancellation_fee: '20' },
  mini: { ...BASE_DEFAULTS, base_fare: '40', per_km: '10', per_min: '1.25', min_fare: '60', cancellation_fee: '25' },
  sedan: { ...BASE_DEFAULTS, base_fare: '50', per_km: '12', per_min: '1.5', min_fare: '80', cancellation_fee: '30' },
};

const TYPE_LABEL: Record<VehicleTypeId, string> = { bike: 'Bike', auto: 'Auto', mini: 'Mini', sedan: 'Sedan' };

function fromConfig(c: FareConfig): Form {
  return {
    base_fare: String(c.base_fare),
    per_km: String(c.per_km),
    per_min: String(c.per_min),
    min_fare: String(c.min_fare),
    cancellation_fee: String(c.cancellation_fee),
    night_multiplier: String(c.night_multiplier),
    commission_pct: String(c.commission_pct),
    gst_pct: String(c.gst_pct),
    night_enabled: c.night_enabled,
    effective_from: '',
  };
}

/** Returns the request body, or null while any numeric field is blank/invalid. */
function toInput(f: Form): FareConfigInput | null {
  const n: Partial<Record<NumKey, number>> = {};
  for (const { key, min } of FIELDS) {
    const v = Number(f[key]);
    if (f[key].trim() === '' || !Number.isFinite(v) || v < min) return null;
    n[key] = v;
  }
  return {
    ...(n as Record<NumKey, number>),
    night_enabled: f.night_enabled,
    ...(f.effective_from ? { effective_from: fromISTDateTimeLocal(f.effective_from) } : {}),
  };
}

function versionState(c: FareConfig, currentId: string | null, asOf: number): 'current' | 'scheduled' | 'superseded' {
  if (c.id === currentId) return 'current';
  return new Date(c.effective_from).getTime() > asOf ? 'scheduled' : 'superseded';
}

export default function FareConfigPage() {
  const query = useQuery({ queryKey: ['fare-config'], queryFn: listFareConfigs });
  const [type, setType] = useState<VehicleTypeId>('sedan');
  const currentId = query.data?.current_ids?.[type] ?? null;
  const rows = query.data?.data.filter((c) => c.vehicle_type === type) ?? [];
  const current = rows.find((c) => c.id === currentId) ?? null;
  const asOf = query.dataUpdatedAt;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">Fare config</h1>
        <p className="text-sm text-gray-500">
          Versions are append-only; the newest one whose effective time has passed is used for estimates. Final fares are capped at 1.25× the
          estimate.
        </p>
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="flex flex-wrap gap-2" role="tablist" aria-label="Vehicle type">
        {VEHICLE_TYPES.map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={t === type}
            onClick={() => setType(t)}
            className={`rounded-full border px-4 py-1.5 text-sm font-medium ${
              t === type ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50'
            }`}
          >
            {TYPE_LABEL[t]}
            {query.data && !query.data.current_ids?.[t] && <span className="ml-1 text-xs opacity-70">(not set)</span>}
          </button>
        ))}
      </div>

      <div className="grid gap-6 xl:grid-cols-5">
        <Card title="History" flush className="self-start xl:col-span-3">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-4 py-2 font-medium">Effective from (IST)</th>
                  <th className="px-4 py-2 font-medium">State</th>
                  <th className="px-4 py-2 text-right font-medium">Base</th>
                  <th className="px-4 py-2 text-right font-medium">/km</th>
                  <th className="px-4 py-2 text-right font-medium">/min</th>
                  <th className="px-4 py-2 text-right font-medium">Min</th>
                  <th className="px-4 py-2 text-right font-medium">Cancel fee</th>
                  <th className="px-4 py-2 text-right font-medium">Night</th>
                  <th className="px-4 py-2 text-right font-medium">Comm.</th>
                  <th className="px-4 py-2 text-right font-medium">GST</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {rows.map((c) => {
                  const state = versionState(c, currentId, asOf);
                  return (
                    <tr key={c.id} className={state === 'current' ? 'bg-gray-50' : ''}>
                      <td className="px-4 py-2 whitespace-nowrap text-gray-900">
                        {formatIST(c.effective_from)}
                        <div className="font-mono text-xs text-gray-400">{shortId(c.id)}</div>
                      </td>
                      <td className="px-4 py-2">
                        <StatusBadge status={state} />
                      </td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.base_fare}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.per_km}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.per_min}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.min_fare}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.cancellation_fee}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.night_enabled ? `×${c.night_multiplier}` : 'off'}</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.commission_pct}%</td>
                      <td className="px-4 py-2 text-right tabular-nums">{c.gst_pct}%</td>
                    </tr>
                  );
                })}
                {query.isPending && (
                  <tr>
                    <td colSpan={10} className="px-4 py-8 text-center text-gray-400">
                      Loading…
                    </td>
                  </tr>
                )}
                {query.data && rows.length === 0 && (
                  <tr>
                    <td colSpan={10} className="px-4 py-8 text-center text-gray-500">
                      No {TYPE_LABEL[type].toLowerCase()} fares yet: riders cannot choose this type until a version exists.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>

        <Card title={`New ${TYPE_LABEL[type].toLowerCase()} version`} className="xl:col-span-2">
          {/* Keyed on the type + current version so the form is seeded from it without effects. */}
          {query.data ? (
            <NewVersionForm key={`${type}-${current?.id ?? 'none'}`} type={type} current={current} />
          ) : (
            <p className="text-sm text-gray-400">Loading…</p>
          )}
        </Card>
      </div>
    </div>
  );
}

interface PreviewState {
  /** Serialised input the result belongs to; a mismatch with the live input means "updating". */
  key: string;
  result?: FarePreview;
  error?: string;
}

function NewVersionForm({ type, current }: { type: VehicleTypeId; current: FareConfig | null }) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<Form>(() => (current ? fromConfig(current) : DEFAULTS[type]));
  const [distanceKm, setDistanceKm] = useState('10');
  const [durationMin, setDurationMin] = useState('30');
  const [preview, setPreview] = useState<PreviewState | null>(null);

  const input = useMemo(() => toInput(form), [form]);
  const distance_m = Math.round(Number(distanceKm) * 1000);
  const duration_s = Math.round(Number(durationMin) * 60);
  const previewReady = input !== null && Number.isFinite(distance_m) && distance_m >= 0 && Number.isFinite(duration_s) && duration_s >= 0;
  const previewKey = previewReady ? JSON.stringify({ input, distance_m, duration_s }) : null;

  // Debounced live preview against the server's fare engine; results are tagged with their input.
  useEffect(() => {
    if (!previewKey || !input) return;
    let cancelled = false;
    const t = setTimeout(() => {
      previewFare({ ...input, distance_m, duration_s, at: input.effective_from })
        .then((result) => {
          if (!cancelled) setPreview({ key: previewKey, result });
        })
        .catch((e) => {
          if (!cancelled) setPreview({ key: previewKey, error: errorMessage(e) });
        });
    }, 400);
    return () => {
      cancelled = true;
      clearTimeout(t);
    };
  }, [previewKey, input, distance_m, duration_s]);

  const create = useMutation({
    mutationFn: (body: FareConfigInput) => createFareConfig({ ...body, vehicle_type: type }),
    onSuccess: (created) => {
      void queryClient.invalidateQueries({ queryKey: ['fare-config'] });
      setForm(fromConfig(created));
      toast.success(
        new Date(created.effective_from).getTime() > new Date().getTime() + 1000
          ? `New ${TYPE_LABEL[type].toLowerCase()} fare version scheduled for ${formatIST(created.effective_from)} IST`
          : `New ${TYPE_LABEL[type].toLowerCase()} fare version is live for the next estimate`,
      );
    },
    onError: (err) => toast.error(errorMessage(err)),
  });

  const set = (key: keyof Form, value: string | boolean) => setForm((f) => ({ ...f, [key]: value }));
  const fresh = preview !== null && preview.key === previewKey;
  const shown = previewReady ? preview : null;

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (input) create.mutate(input);
      }}
    >
      <div className="grid grid-cols-2 gap-3">
        {FIELDS.map((f) => (
          <label key={f.key} className="block">
            <span className={LABEL}>{f.label}</span>
            <input
              type="number"
              required
              min={f.min}
              step={f.step}
              value={form[f.key]}
              onChange={(e) => set(f.key, e.target.value)}
              className={INPUT}
              disabled={f.key === 'night_multiplier' && !form.night_enabled}
            />
            {f.hint && <span className="mt-1 block text-xs text-gray-400">{f.hint}</span>}
          </label>
        ))}
      </div>
      <label className="flex items-center gap-2 text-sm text-gray-700">
        <input type="checkbox" checked={form.night_enabled} onChange={(e) => set('night_enabled', e.target.checked)} />
        Night multiplier enabled
      </label>
      <label className="block">
        <span className={LABEL}>Effective from (IST)</span>
        <input type="datetime-local" value={form.effective_from} onChange={(e) => set('effective_from', e.target.value)} className={INPUT} />
        <span className="mt-1 block text-xs text-gray-400">Leave empty to apply immediately.</span>
      </label>

      <div className="rounded-md border border-gray-200 bg-gray-50 p-4">
        <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-gray-500">Preview calculator</div>
        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className={LABEL}>Distance (km)</span>
            <input type="number" min={0} step="0.1" value={distanceKm} onChange={(e) => setDistanceKm(e.target.value)} className={INPUT} />
          </label>
          <label className="block">
            <span className={LABEL}>Duration (min)</span>
            <input type="number" min={0} step="1" value={durationMin} onChange={(e) => setDurationMin(e.target.value)} className={INPUT} />
          </label>
        </div>
        <div className="mt-3 text-sm">
          {!previewReady && <span className="text-gray-500">Fill in every field to preview.</span>}
          {previewReady && !shown && <span className="text-gray-400">Calculating…</span>}
          {shown?.error && fresh && <span className="text-red-700">{shown.error}</span>}
          {shown?.result && (
            <div className={`flex flex-wrap items-baseline gap-x-6 gap-y-1 ${fresh ? '' : 'opacity-60'}`}>
              <span>
                <span className="text-gray-500">Estimate</span>{' '}
                <span className="text-lg font-semibold text-gray-900">{formatINR(shown.result.fare)}</span>
              </span>
              <span>
                <span className="text-gray-500">Shown range</span>{' '}
                <span className="font-medium">
                  {formatINR(shown.result.fare_min)}–{formatINR(shown.result.fare_max)}
                </span>
              </span>
              <span>
                <span className="text-gray-500">Final-fare cap</span> <span className="font-medium">{formatINR(shown.result.cap)}</span>
              </span>
              {!fresh && <span className="text-xs text-gray-400">updating…</span>}
            </div>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between gap-3">
        <button type="button" onClick={() => setForm(current ? fromConfig(current) : DEFAULTS[type])} className={BTN_SECONDARY}>
          Reset to current
        </button>
        <button type="submit" disabled={!input || create.isPending} className={BTN_PRIMARY}>
          {create.isPending ? 'Saving…' : 'Create version'}
        </button>
      </div>
    </form>
  );
}
