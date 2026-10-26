import { useCallback, useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import StatusBadge from '../../components/StatusBadge';
import { errorMessage } from '../../lib/api';
import { listDrivers, VERIFICATION_STATUSES, type VerificationStatus } from '../../lib/drivers';
import { formatIST } from '../../lib/time';

const LIMIT = 20;
const TABS: { value: VerificationStatus | ''; label: string }[] = [
  { value: '', label: 'All' },
  ...VERIFICATION_STATUSES.map((s) => ({ value: s, label: s[0].toUpperCase() + s.slice(1) })),
];

function parseStatus(v: string | null): VerificationStatus | '' {
  return VERIFICATION_STATUSES.includes(v as VerificationStatus) ? (v as VerificationStatus) : '';
}

export default function DriversList() {
  const navigate = useNavigate();
  // Filters live in the URL so back-navigation from a detail page restores them.
  const [params, setParams] = useSearchParams();
  const status = parseStatus(params.get('status'));
  const q = params.get('q') ?? '';
  const page = Math.max(1, Number(params.get('page')) || 1);

  const [search, setSearch] = useState(q);

  const update = useCallback(
    (next: { status?: string; q?: string; page?: number }) =>
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

  // Debounce the search box into the URL (~300 ms).
  useEffect(() => {
    const value = search.trim();
    if (value === q) return;
    const t = setTimeout(() => update({ q: value, page: 1 }), 300);
    return () => clearTimeout(t);
  }, [search, q, update]);

  const query = useQuery({
    queryKey: ['drivers', { status, q, page, limit: LIMIT }],
    queryFn: () => listDrivers({ status: status || undefined, q: q || undefined, page, limit: LIMIT }),
    placeholderData: keepPreviousData,
  });

  const total = query.data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / LIMIT));
  const from = total === 0 ? 0 : (page - 1) * LIMIT + 1;
  const to = Math.min(page * LIMIT, total);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Drivers</h1>
          <p className="text-sm text-gray-500">Review registrations, documents and account status.</p>
        </div>
        <input
          type="search"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          maxLength={60}
          placeholder="Search name, phone, licence or reg. no."
          className="w-80 rounded-md border border-gray-300 bg-white px-3 py-2 text-sm focus:border-gray-900 focus:outline-none"
        />
      </div>

      <div className="flex gap-1 border-b border-gray-200">
        {TABS.map((t) => (
          <button
            key={t.value || 'all'}
            type="button"
            onClick={() => update({ status: t.value, page: 1 })}
            className={`-mb-px border-b-2 px-4 py-2 text-sm ${
              status === t.value
                ? 'border-gray-900 font-medium text-gray-900'
                : 'border-transparent text-gray-500 hover:text-gray-800'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {query.isError && (
        <div
          role="alert"
          className="flex items-center justify-between rounded-md bg-red-50 px-4 py-3 text-sm text-red-700"
        >
          <span>{errorMessage(query.error)}</span>
          <button type="button" onClick={() => query.refetch()} className="font-medium underline">
            Retry
          </button>
        </div>
      )}

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="px-4 py-3 font-medium">Name</th>
              <th className="px-4 py-3 font-medium">Phone</th>
              <th className="px-4 py-3 font-medium">Vehicle</th>
              <th className="px-4 py-3 font-medium">Status</th>
              <th className="px-4 py-3 text-right font-medium">Pending docs</th>
              <th className="px-4 py-3 font-medium">Registered (IST)</th>
            </tr>
          </thead>
          <tbody className={`divide-y divide-gray-100 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
            {query.data?.data.map((d) => (
              <tr
                key={d.user_id}
                onClick={() => navigate(`/drivers/${d.user_id}`)}
                className="cursor-pointer hover:bg-gray-50"
              >
                <td className="px-4 py-3">
                  <a
                    href={`/drivers/${d.user_id}`}
                    onClick={(e) => e.preventDefault()}
                    className="font-medium text-gray-900 hover:underline"
                  >
                    {d.name ?? '—'}
                  </a>
                  {d.user_status !== 'active' && <span className="ml-2 text-xs text-red-600">({d.user_status})</span>}
                  {d.licence_flagged && (
                    <span
                      title="The licence number is not in the standard format"
                      className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-800"
                    >
                      Check licence
                    </span>
                  )}
                </td>
                <td className="px-4 py-3 font-mono text-gray-700">{d.phone_masked}</td>
                <td className="px-4 py-3 font-mono text-gray-700">{d.reg_number ?? '—'}</td>
                <td className="px-4 py-3">
                  <StatusBadge status={d.verification_status} />
                </td>
                <td className="px-4 py-3 text-right">
                  {d.pending_documents > 0 ? (
                    <span className="inline-flex min-w-6 justify-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-800">
                      {d.pending_documents}
                    </span>
                  ) : (
                    <span className="text-gray-400">0</span>
                  )}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-gray-600">{formatIST(d.created_at)}</td>
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
                  No drivers match these filters.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex items-center justify-between text-sm text-gray-600">
        <span>{total > 0 ? `Showing ${from}–${to} of ${total}` : ''}</span>
        <div className="flex items-center gap-2">
          <button
            type="button"
            disabled={page <= 1}
            onClick={() => update({ page: page - 1 })}
            className="rounded-md border border-gray-300 bg-white px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40"
          >
            Previous
          </button>
          <span>
            Page {page} of {pages}
          </span>
          <button
            type="button"
            disabled={page >= pages}
            onClick={() => update({ page: page + 1 })}
            className="rounded-md border border-gray-300 bg-white px-3 py-1.5 hover:bg-gray-50 disabled:opacity-40"
          >
            Next
          </button>
        </div>
      </div>
    </div>
  );
}
