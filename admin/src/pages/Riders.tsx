import { useCallback, useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import ConfirmDialog from '../components/ConfirmDialog';
import ErrorBanner from '../components/ErrorBanner';
import Pagination from '../components/Pagination';
import ReasonDialog from '../components/ReasonDialog';
import StatusBadge from '../components/StatusBadge';
import { blockRider, listRiders, unblockRider, type Rider } from '../lib/riders';
import { formatIST } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_SMALL, BTN_SMALL_DANGER } from '../lib/ui';

const LIMIT = 20;

type Dialog = { kind: 'block'; rider: Rider } | { kind: 'unblock'; rider: Rider };

export default function Riders() {
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const q = params.get('q') ?? '';
  const page = Math.max(1, Number(params.get('page')) || 1);
  const [search, setSearch] = useState(q);
  const [dialog, setDialog] = useState<Dialog | null>(null);

  const update = useCallback(
    (next: { q?: string; page?: number }) =>
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

  useEffect(() => {
    const value = search.trim();
    if (value === q) return;
    const t = setTimeout(() => update({ q: value, page: 1 }), 300);
    return () => clearTimeout(t);
  }, [search, q, update]);

  const query = useQuery({
    queryKey: ['riders', { q, page }],
    queryFn: () => listRiders({ q: q || undefined, page, limit: LIMIT }),
    placeholderData: keepPreviousData,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['riders'] });
  const blockMut = useMutation({
    mutationFn: ({ id, reason }: { id: string; reason: string }) => blockRider(id, reason),
    onSuccess: () => {
      void invalidate();
      toast.success('Rider blocked');
    },
  });
  const unblockMut = useMutation({
    mutationFn: ({ id, note }: { id: string; note?: string }) => unblockRider(id, note),
    onSuccess: () => {
      void invalidate();
      toast.success('Rider unblocked');
    },
  });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Riders</h1>
          <p className="text-sm text-gray-500">Blocked riders cannot sign in or request rides.</p>
        </div>
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          maxLength={60}
          placeholder="Search name, phone or email"
          className="w-80 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm focus:border-gray-900 focus:outline-none"
        />
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Name</th>
              <th className="px-4 py-3 font-medium">Phone</th>
              <th className="px-4 py-3 font-medium">Email</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 text-right font-medium">Rating</th>
              <th className="px-4 py-3 text-right font-medium">Rides</th>
              <th className="px-4 py-3 font-medium">Joined (IST)</th>
              <th className="px-4 py-3 text-right font-medium">Actions</th>
            </tr>
          </thead>
          <tbody className={`divide-y divide-gray-100 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
            {query.data?.data.map((r) => (
              <tr key={r.id} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <div className="font-medium text-gray-900">{r.name ?? '—'}</div>
                  <div className="font-mono text-xs text-gray-400">{r.id.slice(0, 8)}</div>
                </td>
                <td className="px-4 py-3 font-mono text-gray-700">{r.phone}</td>
                <td className="px-4 py-3 text-gray-700">{r.email ?? '—'}</td>
                <td className="px-4 py-3">
                  <StatusBadge status={r.status} />
                </td>
                <td className="px-4 py-3 text-right text-gray-700">
                  {r.rating_avg.toFixed(2)} <span className="text-xs text-gray-400">({r.rating_count})</span>
                </td>
                <td className="px-4 py-3 text-right">
                  <Link to={`/rides?rider_id=${r.id}`} className="text-gray-900 underline">
                    {r.rides_count}
                  </Link>
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-gray-600">{formatIST(r.created_at)}</td>
                <td className="px-4 py-3 text-right">
                  {r.status === 'active' ? (
                    <button type="button" onClick={() => setDialog({ kind: 'block', rider: r })} className={BTN_SMALL_DANGER}>
                      Block
                    </button>
                  ) : (
                    <button type="button" onClick={() => setDialog({ kind: 'unblock', rider: r })} className={BTN_SMALL}>
                      Unblock
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {query.isPending && (
              <tr>
                <td colSpan={8} className="px-4 py-8 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
            {query.data && query.data.data.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-8 text-center text-gray-500">
                  No riders match.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <Pagination page={page} limit={LIMIT} total={query.data?.total ?? 0} onPage={(p) => update({ page: p })} />

      {dialog?.kind === 'block' && (
        <ReasonDialog
          title={`Block ${dialog.rider.name ?? dialog.rider.phone}`}
          description="The rider is signed out everywhere and cannot request rides until unblocked."
          confirmLabel="Block rider"
          onConfirm={(reason) => blockMut.mutateAsync({ id: dialog.rider.id, reason })}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'unblock' && (
        <ConfirmDialog
          title={`Unblock ${dialog.rider.name ?? dialog.rider.phone}`}
          description="The rider can sign in and request rides again."
          confirmLabel="Unblock rider"
          note={{ label: 'Note (optional)', placeholder: 'Why the block is lifted', maxLength: 300 }}
          onConfirm={(note) => unblockMut.mutateAsync({ id: dialog.rider.id, note: note || undefined })}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}
