import { Link, useSearchParams } from 'react-router';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import ErrorBanner from '../components/ErrorBanner';
import Pagination from '../components/Pagination';
import StatusBadge from '../components/StatusBadge';
import { errorMessage } from '../lib/api';
import { ackSos, listSos, mapsLink } from '../lib/sos';
import { formatAgo, formatIST } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_SMALL_DARK, shortId } from '../lib/ui';

const LIMIT = 20;

export default function Sos() {
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') === 'acknowledged' ? 'acknowledged' : 'open';
  const page = Math.max(1, Number(params.get('page')) || 1);
  const acknowledged = tab === 'acknowledged';

  const query = useQuery({
    queryKey: ['sos', { acknowledged, page }],
    queryFn: () => listSos({ acknowledged, page, limit: LIMIT }),
    placeholderData: keepPreviousData,
    refetchInterval: acknowledged ? false : 15_000,
  });

  const ack = useMutation({
    mutationFn: (id: string) => ackSos(id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['sos'] });
      void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      toast.success('SOS acknowledged');
    },
    onError: (e) => toast.error(errorMessage(e)),
  });

  const setTab = (t: 'open' | 'acknowledged') => setParams(t === 'open' ? {} : { tab: t }, { replace: true });

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold text-gray-900">SOS alerts</h1>
        <p className="text-sm text-gray-500">
          Raised from the rider or driver app; the app dials 112 itself. Acknowledge once someone is handling it.
        </p>
      </div>

      <div className="flex gap-1 border-b border-gray-200">
        {(['open', 'acknowledged'] as const).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`-mb-px border-b-2 px-4 py-2 text-sm capitalize ${
              tab === t ? 'border-gray-900 font-medium text-gray-900' : 'border-transparent text-gray-500 hover:text-gray-800'
            }`}
          >
            {t}
            {t === 'open' && !acknowledged && query.data && query.data.total > 0 && (
              <span className="ml-2 rounded-full bg-red-600 px-1.5 text-xs font-semibold text-white">{query.data.total}</span>
            )}
          </button>
        ))}
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Raised (IST)</th>
              <th className="px-4 py-3 font-medium">Who</th>
              <th className="px-4 py-3 font-medium">Ride</th>
              <th className="px-4 py-3 font-medium">Location</th>
              <th className="px-4 py-3 font-medium">{acknowledged ? 'Acknowledged' : 'Status'}</th>
              <th className="px-4 py-3 text-right font-medium">Action</th>
            </tr>
          </thead>
          <tbody className={`divide-y divide-gray-100 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
            {query.data?.data.map((s) => (
              <tr key={s.id} className={!s.acknowledged_at ? 'bg-red-50/40 hover:bg-red-50' : 'hover:bg-gray-50'}>
                <td className="px-4 py-3 whitespace-nowrap">
                  <div className="text-gray-900">{formatIST(s.created_at)}</div>
                  <div className="text-xs text-gray-500">{formatAgo(s.created_at)}</div>
                </td>
                <td className="px-4 py-3">
                  <div className="text-gray-900">
                    {s.user_name ?? 'Unnamed'} <span className="ml-1 rounded bg-gray-100 px-1.5 py-0.5 text-xs capitalize text-gray-700">{s.user_role}</span>
                  </div>
                  <div className="font-mono text-xs text-gray-500">{s.user_phone}</div>
                </td>
                <td className="px-4 py-3">
                  {s.ride_id ? (
                    <Link to={`/rides/${s.ride_id}`} className="font-mono text-gray-900 underline">
                      {shortId(s.ride_id)}
                    </Link>
                  ) : (
                    '—'
                  )}
                </td>
                <td className="px-4 py-3">
                  {s.lat !== null && s.lng !== null ? (
                    <a href={mapsLink(s.lat, s.lng)} target="_blank" rel="noreferrer" className="text-blue-700 underline">
                      {s.lat.toFixed(5)}, {s.lng.toFixed(5)} ↗
                    </a>
                  ) : (
                    '—'
                  )}
                </td>
                <td className="px-4 py-3">
                  {s.acknowledged_at ? (
                    <div>
                      <div className="text-gray-900">{formatIST(s.acknowledged_at)}</div>
                      <div className="font-mono text-xs text-gray-500">by {shortId(s.acknowledged_by)}</div>
                    </div>
                  ) : (
                    <StatusBadge status="open" />
                  )}
                </td>
                <td className="px-4 py-3 text-right">
                  {!s.acknowledged_at && (
                    <button
                      type="button"
                      disabled={ack.isPending && ack.variables === s.id}
                      onClick={() => ack.mutate(s.id)}
                      className={BTN_SMALL_DARK}
                    >
                      Acknowledge
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {query.isPending && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
            {query.data && query.data.data.length === 0 && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                  {acknowledged ? 'Nothing acknowledged yet.' : 'No open SOS alerts.'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <Pagination
        page={page}
        limit={LIMIT}
        total={query.data?.total ?? 0}
        onPage={(p) =>
          setParams(
            (prev) => {
              const n = new URLSearchParams(prev);
              if (p === 1) n.delete('page');
              else n.set('page', String(p));
              return n;
            },
            { replace: true },
          )
        }
      />
    </div>
  );
}
