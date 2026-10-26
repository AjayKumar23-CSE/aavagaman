import { Link } from 'react-router';
import { useQuery } from '@tanstack/react-query';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { DASHBOARD_REFRESH_MS } from '../App';
import Card from '../components/Card';
import ErrorBanner from '../components/ErrorBanner';
import HealthCard from '../components/HealthCard';
import { getDashboard, type Dashboard as DashboardData } from '../lib/dashboard';
import { RIDE_STATUSES } from '../lib/rides';
import { formatAgo, formatINR, formatIST } from '../lib/time';

/** Single-series bar: one hue (dataviz slot 1), labels in ink, recessive grid. */
const SERIES_1 = '#2a78d6';
const INK_MUTED = '#898781';
const GRID = '#e1e0d9';

interface Tile {
  label: string;
  value: (d: DashboardData) => string;
  to?: string;
  tone?: (d: DashboardData) => 'alert' | 'warn' | undefined;
}

const TILES: Tile[] = [
  { label: 'Rides today', value: (d) => String(d.rides_total), to: '/rides' },
  { label: 'Completed', value: (d) => String(d.completed) },
  { label: 'Cancelled', value: (d) => String(d.cancellations), to: '/rides?status=CANCELLED' },
  { label: 'Online drivers', value: (d) => String(d.online_drivers), to: '/live' },
  { label: 'Revenue (paid)', value: (d) => formatINR(d.revenue) },
  {
    label: 'Pending drivers',
    value: (d) => String(d.pending_drivers),
    to: '/drivers?status=pending',
    tone: (d) => (d.pending_drivers > 0 ? 'warn' : undefined),
  },
  { label: 'Open SOS', value: (d) => String(d.open_sos), to: '/sos', tone: (d) => (d.open_sos > 0 ? 'alert' : undefined) },
];

export default function Dashboard() {
  const query = useQuery({ queryKey: ['dashboard'], queryFn: getDashboard, refetchInterval: DASHBOARD_REFRESH_MS });
  const d = query.data;
  const chart = RIDE_STATUSES.map((s) => ({ status: s.toLowerCase().replace('_', ' '), count: d?.rides_by_status[s] ?? 0 }));

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Dashboard</h1>
          <p className="text-sm text-gray-500">
            Today in IST{d ? ` (since ${formatIST(d.day_start)})` : ''}.
            {query.dataUpdatedAt > 0 && ` Updated ${formatAgo(query.dataUpdatedAt)}; refreshes every 30 s.`}
          </p>
        </div>
        <Link
          to="/live"
          className="rounded-md bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-800"
        >
          Open live map →
        </Link>
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4 xl:grid-cols-7">
        {TILES.map((t) => {
          const tone = d ? t.tone?.(d) : undefined;
          const body = (
            <>
              <div className="text-xs font-medium uppercase tracking-wide text-gray-500">{t.label}</div>
              <div
                className={`mt-1 text-2xl font-semibold ${
                  tone === 'alert' ? 'text-red-700' : tone === 'warn' ? 'text-amber-700' : 'text-gray-900'
                }`}
              >
                {d ? t.value(d) : '—'}
              </div>
            </>
          );
          const cls = `block rounded-lg border bg-white p-4 ${
            tone === 'alert' ? 'border-red-300' : 'border-gray-200'
          } ${t.to ? 'hover:border-gray-400' : ''}`;
          return t.to ? (
            <Link key={t.label} to={t.to} className={cls}>
              {body}
            </Link>
          ) : (
            <div key={t.label} className={cls}>
              {body}
            </div>
          );
        })}
      </div>

      <Card title="Rides by status (today)">
        <div className="h-64">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={chart} margin={{ top: 8, right: 8, left: -16, bottom: 0 }} barCategoryGap="30%">
              <CartesianGrid vertical={false} stroke={GRID} />
              <XAxis dataKey="status" tick={{ fontSize: 12, fill: INK_MUTED }} axisLine={{ stroke: GRID }} tickLine={false} />
              <YAxis allowDecimals={false} tick={{ fontSize: 12, fill: INK_MUTED }} axisLine={false} tickLine={false} />
              <Tooltip cursor={{ fill: '#f3f4f6' }} contentStyle={{ fontSize: 12, borderRadius: 6 }} />
              <Bar dataKey="count" name="Rides" fill={SERIES_1} radius={[4, 4, 0, 0]} maxBarSize={48} isAnimationActive={false} />
            </BarChart>
          </ResponsiveContainer>
        </div>
        {d && d.rides_total === 0 && <p className="mt-2 text-center text-sm text-gray-500">No rides requested yet today.</p>}
      </Card>

      <HealthCard />
    </div>
  );
}
