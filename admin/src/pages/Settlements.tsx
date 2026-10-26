import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import ConfirmDialog from '../components/ConfirmDialog';
import ErrorBanner from '../components/ErrorBanner';
import StatusBadge from '../components/StatusBadge';
import { errorMessage } from '../lib/api';
import { generateSettlements, listSettlements, settleSettlement, type Settlement } from '../lib/settlements';
import { addDays, formatDay, formatINR, formatIST, mondayOf, todayIST } from '../lib/time';
import { toast } from '../lib/toast';
import { BTN_PRIMARY, BTN_SMALL, BTN_SMALL_DARK, INPUT, LABEL } from '../lib/ui';

const YMD_RE = /^\d{4}-\d{2}-\d{2}$/;
type Filter = 'all' | 'pending' | 'settled';

function payableLabel(amount: number): { text: string; cls: string } {
  if (amount > 0) return { text: 'Platform pays driver', cls: 'text-green-700' };
  if (amount < 0) return { text: 'Driver owes platform', cls: 'text-red-700' };
  return { text: 'Nothing due', cls: 'text-gray-500' };
}

export default function Settlements() {
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const lastWeek = mondayOf(addDays(todayIST(), -7));
  const allWeeks = params.get('week') === 'all';
  const week = allWeeks ? '' : YMD_RE.test(params.get('week') ?? '') ? mondayOf(params.get('week')!) : lastWeek;
  const setWeek = (w: string) => setParams({ week: w || 'all' }, { replace: true });
  const [filter, setFilter] = useState<Filter>('all');
  const [settling, setSettling] = useState<Settlement | null>(null);

  const query = useQuery({
    queryKey: ['settlements', week],
    queryFn: () => listSettlements(week || undefined),
    placeholderData: keepPreviousData,
  });
  const rows = (query.data ?? []).filter((s) => (filter === 'all' ? true : filter === 'settled' ? !!s.settled_at : !s.settled_at));
  const pendingTotal = (query.data ?? []).filter((s) => !s.settled_at).reduce((n, s) => n + s.amount_payable, 0);

  const generate = useMutation({
    mutationFn: () => generateSettlements(week || undefined),
    onSuccess: (res) => {
      void queryClient.invalidateQueries({ queryKey: ['settlements'] });
      toast.success(
        `Generated ${res.settlements.length} statement${res.settlements.length === 1 ? '' : 's'} for ${formatDay(res.period_start)} – ${formatDay(res.period_end)}`,
      );
    },
    onError: (e) => toast.error(errorMessage(e)),
  });
  const settle = useMutation({
    mutationFn: ({ id, reference }: { id: string; reference: string }) => settleSettlement(id, reference),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['settlements'] });
      toast.success('Marked settled');
    },
  });

  const weekIsCurrentOrFuture = !!week && week >= mondayOf(todayIST());

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Settlements</h1>
          <p className="text-sm text-gray-500">Weekly (Mon–Sun, IST) statements per driver, built from PAID rides.</p>
        </div>
        <button
          type="button"
          disabled={generate.isPending || weekIsCurrentOrFuture}
          title={weekIsCurrentOrFuture ? 'The week has not ended yet' : undefined}
          onClick={() => generate.mutate()}
          className={BTN_PRIMARY}
        >
          {generate.isPending ? 'Generating…' : week ? `Generate for week of ${formatDay(week)}` : 'Generate for last week'}
        </button>
      </div>

      <div className="flex flex-wrap items-end gap-3 rounded-lg border border-gray-200 bg-white p-4">
        <label className="block">
          <span className={LABEL}>Any day in the week</span>
          <input type="date" value={week} onChange={(e) => e.target.value && setWeek(e.target.value)} className={INPUT} />
        </label>
        <div className="flex gap-2 pb-0.5">
          <button type="button" disabled={!week} onClick={() => setWeek(addDays(week, -7))} className={BTN_SMALL}>
            ← Previous week
          </button>
          <button type="button" disabled={!week} onClick={() => setWeek(addDays(week, 7))} className={BTN_SMALL}>
            Next week →
          </button>
          <button type="button" onClick={() => setWeek(lastWeek)} className={BTN_SMALL}>
            Last week
          </button>
          <button type="button" onClick={() => setWeek('')} className={allWeeks ? BTN_SMALL_DARK : BTN_SMALL}>
            All weeks
          </button>
        </div>
        <div className="ml-auto flex gap-1 rounded-md border border-gray-300 p-0.5 text-sm">
          {(['all', 'pending', 'settled'] as Filter[]).map((f) => (
            <button
              key={f}
              type="button"
              onClick={() => setFilter(f)}
              className={`rounded px-3 py-1 capitalize ${filter === f ? 'bg-gray-900 text-white' : 'text-gray-700 hover:bg-gray-100'}`}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      <div className="rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700">
        <span className="font-medium">
          {week ? `Week ${formatDay(week)} – ${formatDay(addDays(week, 6))}` : 'All weeks'}
        </span>
        {' · '}
        <span className="font-medium">Amount payable</span> = online collected − commission − GST on gross fares.{' '}
        <span className="text-green-700">Positive: the platform pays the driver.</span>{' '}
        <span className="text-red-700">Negative: the driver owes the platform</span> (cash they kept exceeds what the platform is due).
        {query.data && query.data.length > 0 && (
          <>
            {' · '}Pending net: <span className={`font-medium ${payableLabel(pendingTotal).cls}`}>{formatINR(pendingTotal)}</span>
          </>
        )}
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className={`overflow-x-auto rounded-lg border border-gray-200 bg-white ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Driver</th>
              {!week && <th className="px-4 py-3 font-medium">Week</th>}
              <th className="px-4 py-3 text-right font-medium">Rides</th>
              <th className="px-4 py-3 text-right font-medium">Gross fares</th>
              <th className="px-4 py-3 text-right font-medium">Commission</th>
              <th className="px-4 py-3 text-right font-medium">Cash</th>
              <th className="px-4 py-3 text-right font-medium">Online</th>
              <th className="px-4 py-3 text-right font-medium">Amount payable</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 text-right font-medium">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {rows.map((s) => {
              const pay = payableLabel(s.amount_payable);
              return (
                <tr key={s.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <Link to={`/drivers/${s.driver_id}`} className="font-medium text-gray-900 hover:underline">
                      {s.driver_name ?? 'Unnamed driver'}
                    </Link>
                    <div className="font-mono text-xs text-gray-500">{s.driver_phone}</div>
                  </td>
                  {!week && (
                    <td className="px-4 py-3 whitespace-nowrap text-gray-700">
                      {formatDay(s.period_start)} – {formatDay(s.period_end)}
                    </td>
                  )}
                  <td className="px-4 py-3 text-right tabular-nums">{s.rides_count}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatINR(s.gross_fares)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatINR(s.commission)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatINR(s.cash_collected)}</td>
                  <td className="px-4 py-3 text-right tabular-nums">{formatINR(s.online_collected)}</td>
                  <td className="px-4 py-3 text-right">
                    <div className={`font-semibold tabular-nums ${pay.cls}`}>{formatINR(Math.abs(s.amount_payable))}</div>
                    <div className={`text-xs ${pay.cls}`}>{pay.text}</div>
                  </td>
                  <td className="px-4 py-3">
                    {s.settled_at ? (
                      <div>
                        <StatusBadge status="settled" />
                        <div className="mt-1 text-xs text-gray-500">{formatIST(s.settled_at)} IST</div>
                        {s.reference && <div className="font-mono text-xs text-gray-700">{s.reference}</div>}
                      </div>
                    ) : (
                      <StatusBadge status="pending" />
                    )}
                  </td>
                  <td className="px-4 py-3 text-right">
                    {!s.settled_at && (
                      <button type="button" onClick={() => setSettling(s)} className={BTN_SMALL}>
                        Mark settled
                      </button>
                    )}
                  </td>
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
                  {query.data.length === 0
                    ? week
                      ? 'No statements for this week yet — generate them once the week has ended.'
                      : 'No statements yet.'
                    : `No ${filter} statements.`}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {settling && (
        <ConfirmDialog
          title={`Mark settled: ${settling.driver_name ?? settling.driver_phone}`}
          description={
            <>
              {payableLabel(settling.amount_payable).text}: <span className="font-semibold">{formatINR(Math.abs(settling.amount_payable))}</span> for{' '}
              {formatDay(settling.period_start)} – {formatDay(settling.period_end)}. Record the bank/UPI reference of the transfer.
            </>
          }
          confirmLabel="Mark settled"
          note={{ label: 'Payment reference', placeholder: 'e.g. NEFT UTR 1234567890', required: true, maxLength: 120 }}
          onConfirm={(reference) => settle.mutateAsync({ id: settling.id, reference })}
          onClose={() => setSettling(null)}
        />
      )}
    </div>
  );
}
