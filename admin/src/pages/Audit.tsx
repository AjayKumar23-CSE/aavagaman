import { Fragment, useCallback, useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import ErrorBanner from '../components/ErrorBanner';
import Pagination from '../components/Pagination';
import { AUDIT_ENTITIES, listAudit, type AuditEntry } from '../lib/audit';
import { formatIST } from '../lib/time';
import { INPUT, LABEL, shortId, UUID_RE } from '../lib/ui';

const LIMIT = 25;

function entityLink(e: AuditEntry): string | null {
  if (!e.entity_id) return null;
  switch (e.entity) {
    case 'ride':
      return `/rides/${e.entity_id}`;
    case 'driver':
      return `/drivers/${e.entity_id}`;
    case 'service_area':
      return '/service-areas';
    case 'fare_config':
      return '/fare-config';
    case 'sos_alert':
      return '/sos?tab=acknowledged';
    case 'driver_settlement':
      return '/settlements?week=all';
    default:
      return null;
  }
}

function Json({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span className="text-gray-400">—</span>;
  return <pre className="max-h-64 overflow-auto rounded-md bg-gray-50 p-3 text-xs text-gray-800">{JSON.stringify(value, null, 2)}</pre>;
}

/** Text filter that commits to the URL after a pause; UUID fields are validated client-side. Remounted (key) on clear. */
function TextFilter({ label, value, onChange, uuid, list }: { label: string; value: string; onChange: (v: string) => void; uuid?: boolean; list?: string }) {
  const [text, setText] = useState(value);
  useEffect(() => {
    const v = text.trim();
    if (v === value) return;
    const t = setTimeout(() => onChange(v), 300);
    return () => clearTimeout(t);
  }, [text, value, onChange]);
  const invalid = uuid && text.trim() !== '' && !UUID_RE.test(text.trim());
  return (
    <label className="block">
      <span className={LABEL}>{label}</span>
      <input value={text} onChange={(e) => setText(e.target.value)} list={list} spellCheck={false} className={`${INPUT} ${uuid ? 'font-mono' : ''} ${invalid ? 'border-red-400' : ''}`} />
      {invalid && <span className="mt-1 block text-xs text-red-600">Not a valid id; filter ignored.</span>}
    </label>
  );
}

export default function Audit() {
  const [params, setParams] = useSearchParams();
  const entity = params.get('entity') ?? '';
  const entityId = params.get('entity_id') ?? '';
  const actorId = params.get('actor_id') ?? '';
  const page = Math.max(1, Number(params.get('page')) || 1);
  const [open, setOpen] = useState<Set<number>>(new Set());
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
  const setEntity = useCallback((v: string) => update({ entity: v, page: 1 }), [update]);
  const setEntityId = useCallback((v: string) => update({ entity_id: v, page: 1 }), [update]);
  const setActorId = useCallback((v: string) => update({ actor_id: v, page: 1 }), [update]);

  const query = useQuery({
    queryKey: ['audit', { entity, entityId, actorId, page }],
    queryFn: () =>
      listAudit({
        entity: entity || undefined,
        entity_id: UUID_RE.test(entityId) ? entityId : undefined,
        actor_id: UUID_RE.test(actorId) ? actorId : undefined,
        page,
        limit: LIMIT,
      }),
    placeholderData: keepPreviousData,
  });

  const toggle = (id: number) =>
    setOpen((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-gray-900">Audit log</h1>
          <p className="text-sm text-gray-500">Every admin action with its before/after snapshot. Click a row to expand.</p>
        </div>
        {(entity || entityId || actorId) && (
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

      <div key={resetKey} className="grid gap-3 rounded-lg border border-gray-200 bg-white p-4 md:grid-cols-3">
        <TextFilter label="Entity" value={entity} onChange={setEntity} list="audit-entities" />
        <datalist id="audit-entities">
          {AUDIT_ENTITIES.map((e) => (
            <option key={e} value={e} />
          ))}
        </datalist>
        <TextFilter label="Entity id" value={entityId} onChange={setEntityId} uuid />
        <TextFilter label="Actor id" value={actorId} onChange={setActorId} uuid />
      </div>

      {query.isError && <ErrorBanner error={query.error} onRetry={() => query.refetch()} />}

      <div className="overflow-x-auto rounded-lg border border-gray-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
            <tr>
              <th className="w-8 px-4 py-3" />
              <th className="px-4 py-3 font-medium">When (IST)</th>
              <th className="px-4 py-3 font-medium">Actor</th>
              <th className="px-4 py-3 font-medium">Action</th>
              <th className="px-4 py-3 font-medium">Entity</th>
            </tr>
          </thead>
          <tbody className={`divide-y divide-gray-100 ${query.isPlaceholderData ? 'opacity-60' : ''}`}>
            {query.data?.data.map((e) => {
              const expanded = open.has(e.id);
              const link = entityLink(e);
              return (
                <Fragment key={e.id}>
                  <tr onClick={() => toggle(e.id)} className="cursor-pointer hover:bg-gray-50" aria-expanded={expanded}>
                    <td className="px-4 py-3 text-gray-400">{expanded ? '▾' : '▸'}</td>
                    <td className="px-4 py-3 whitespace-nowrap text-gray-700">{formatIST(e.at)}</td>
                    <td className="px-4 py-3">
                      <div className="text-gray-900">{e.actor_name ?? (e.actor_id ? 'Unknown' : 'System')}</div>
                      {e.actor_id && <div className="font-mono text-xs text-gray-400">{shortId(e.actor_id)}</div>}
                    </td>
                    <td className="px-4 py-3 font-mono text-gray-900">{e.action}</td>
                    <td className="px-4 py-3">
                      <span className="text-gray-700">{e.entity}</span>
                      {e.entity_id && (
                        <span className="ml-2 font-mono text-xs text-gray-500">
                          {link ? (
                            <Link to={link} onClick={(ev) => ev.stopPropagation()} className="underline">
                              {shortId(e.entity_id)}
                            </Link>
                          ) : (
                            shortId(e.entity_id)
                          )}
                        </span>
                      )}
                    </td>
                  </tr>
                  {expanded && (
                    <tr className="bg-gray-50/60">
                      <td />
                      <td colSpan={4} className="px-4 pb-4">
                        <div className="grid gap-4 md:grid-cols-2">
                          <div>
                            <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-500">Before</div>
                            <Json value={e.before} />
                          </div>
                          <div>
                            <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-500">After</div>
                            <Json value={e.after} />
                          </div>
                        </div>
                        <div className="mt-2 font-mono text-xs text-gray-400">
                          #{e.id} · entity_id {e.entity_id ?? '—'} · actor_id {e.actor_id ?? '—'}
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              );
            })}
            {query.isPending && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
            {query.data && query.data.data.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-gray-500">
                  No audit entries match.
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
