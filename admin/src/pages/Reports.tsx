import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import Card from '../components/Card';
import ErrorBanner from '../components/ErrorBanner';
import { errorMessage } from '../lib/api';
import { downloadDailyCsv, getDailyReport, type DailyRow } from '../lib/reports';
import { addDays, formatDay, formatDayShort, formatINR, todayIST } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_PRIMARY, BTN_SMALL, BTN_SMALL_DARK, INPUT, LABEL } from '../lib/ui';

/** dataviz categorical slots in fixed order; ink/grid from the reference palette. */
const SLOT = ['#2a78d6', '#eb6834', '#1baf7a'];
const INK_MUTED = '#898781';
const GRID = '#e1e0d9';
const YMD_RE = /^\d{4}-\d{2}-\d{2}$/;
const DEFAULT_DAYS = 14;

const COLUMNS: { key: keyof DailyRow; label: string; money?: boolean }[] = [
  { key: 'requested', label: 'Requested' },
  { key: 'completed', label: 'Completed' },
  { key: 'cancelled', label: 'Cancelled' },
  { key: 'no_driver', label: 'No driver' },
  { key: 'paid_rides', label: 'Paid rides' },
  { key: 'revenue', label: 'Revenue', money: true },
  { key: 'gross_fares', label: 'Gross fares', money: true },
  { key: 'gst', label: 'GST', money: true },
  { key: 'commission', label: 'Commission', money: true },
  { key: 'cash', label: 'Cash', money: true },
  { key: 'online', label: 'Online', money: true },
];

const PRESETS = [7, 14, 30, 90];

const tooltipStyle = { fontSize: 12, borderRadius: 6 };
const axisTick = { fontSize: 12, fill: INK_MUTED };

export default function Reports() {
  const [params, setParams] = useSearchParams();
  const today = todayIST();
  const to = YMD_RE.test(params.get('to') ?? '') ? params.get('to')! : today;
  const from = YMD_RE.test(params.get('from') ?? '') ? params.get('from')! : addDays(to, -(DEFAULT_DAYS - 1));
  const setRange = (f: string, t: string) => setParams({ from: f, to: t }, { replace: true });

  const query = useQuery({
    queryKey: ['report-daily', from, to],
    queryFn: () => getDailyReport(from, to),
    placeholderData: keepPreviousData,
    enabled: from <= to,
  });
  const rows = query.data?.data ?? [];
  const totals = COLUMNS.map((c) => ({ ...c, value: rows.reduce((s, r) => s + (r[c.key] as number), 0) }));
  const chart = rows.map((r) => ({ ...r, label: formatDayShort(r.day) }));

  const [downloading, setDownloading] = useState(false);
  async function download() {
    setDownloading(true);
    try {
      await downloadDailyCsv(from, to);
    } catch (e) {
      toast.error(errorMessage(e));
    } finally {
      setDownloading(false);
    }
  }

  const money = (v: number) => formatINR(v);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Reports</h1>
          <p className="text-sm text-gray-500">Daily totals per IST calendar day. Revenue counts rides paid that day.</p>
        </div>
        <button type="button" onClick={download} disabled={downloading || from > to} className={BTN_PRIMARY}>
          {downloading ? 'Preparing…' : 'Download CSV'}
        </button>
      </div>

      <div className="flex flex-wrap items-end gap-3 rounded-lg border border-gray-200 bg-white p-4">
        <label className="block">
          <span className={LABEL}>From</span>
          <input type="date" value={from} max={to} onChange={(e) => e.target.value && setRange(e.target.value, to)} className={INPUT} />
        </label>
        <label className="block">
          <span className={LABEL}>To</span>
          <input type="date" value={to} min={from} max={today} onChange={(e) => e.target.value && setRange(from, e.target.value)} className={INPUT} />
        </label>
        <div className="flex gap-2 pb-0.5">
          {PRESETS.map((d) => (
            <button
              key={d}
              type="button"
              onClick={() => setRange(addDays(today, -(d - 1)), today)}
              className={to === today && from === addDays(today, -(d - 1)) ? BTN_SMALL_DARK : BTN_SMALL}
            >
              Last {d} days
            </button>
          ))}
        </div>
        {from > to && <span className="pb-2 text-sm text-red-600">"From" must be on or before "To".</span>}
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className={`grid gap-6 lg:grid-cols-2 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
        <Card title="Rides per day">
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chart} margin={{ top: 8, right: 8, left: -16, bottom: 0 }} barCategoryGap="25%" barGap={2}>
                <CartesianGrid vertical={false} stroke={GRID} />
                <XAxis dataKey="label" tick={axisTick} axisLine={{ stroke: GRID }} tickLine={false} interval="preserveStartEnd" />
                <YAxis allowDecimals={false} tick={axisTick} axisLine={false} tickLine={false} />
                <Tooltip cursor={{ fill: '#f3f4f6' }} contentStyle={tooltipStyle} />
                <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="requested" name="Requested" fill={SLOT[0]} radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false} />
                <Bar dataKey="completed" name="Completed" fill={SLOT[1]} radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false} />
                <Bar dataKey="cancelled" name="Cancelled" fill={SLOT[2]} radius={[4, 4, 0, 0]} maxBarSize={24} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>
        <Card title="Revenue per day: cash vs online">
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chart} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="30%">
                <CartesianGrid vertical={false} stroke={GRID} />
                <XAxis dataKey="label" tick={axisTick} axisLine={{ stroke: GRID }} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={axisTick} axisLine={false} tickLine={false} tickFormatter={(v: number) => `₹${v}`} width={64} />
                <Tooltip cursor={{ fill: '#f3f4f6' }} contentStyle={tooltipStyle} formatter={(v) => money(Number(v))} />
                <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="cash" name="Cash" stackId="rev" fill={SLOT[0]} stroke="#ffffff" strokeWidth={1} maxBarSize={32} isAnimationActive={false} />
                <Bar dataKey="online" name="Online" stackId="rev" fill={SLOT[1]} stroke="#ffffff" strokeWidth={1} radius={[4, 4, 0, 0]} maxBarSize={32} isAnimationActive={false} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>

      <div className={`overflow-x-auto rounded-lg border border-gray-200 bg-white ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Day</th>
              {COLUMNS.map((c) => (
                <th key={c.key} className="px-4 py-3 text-right font-medium">
                  {c.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((r) => (
              <tr key={r.day} className="hover:bg-gray-50">
                <td className="px-4 py-2 whitespace-nowrap text-gray-900">{formatDay(r.day)}</td>
                {COLUMNS.map((c) => (
                  <td key={c.key} className="px-4 py-2 text-right tabular-nums text-gray-700">
                    {c.money ? money(r[c.key] as number) : r[c.key]}
                  </td>
                ))}
              </tr>
            ))}
            {query.isPending && (
              <tr>
                <td colSpan={COLUMNS.length + 1} className="px-4 py-8 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
          </tbody>
          {rows.length > 0 && (
            <tfoot className="border-t border-gray-200 bg-gray-50 font-medium">
              <tr>
                <td className="px-4 py-2 text-gray-900">Total</td>
                {totals.map((c) => (
                  <td key={c.key} className="px-4 py-2 text-right tabular-nums text-gray-900">
                    {c.money ? money(c.value) : c.value}
                  </td>
                ))}
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  );
}
