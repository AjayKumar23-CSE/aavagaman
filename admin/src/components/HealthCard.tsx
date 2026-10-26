import { useQuery } from '@tanstack/react-query';
import { getHealth } from '../lib/api';
import { formatTimeIST } from '../lib/time';

function Dot({ ok }: { ok: boolean | undefined }) {
  const colour = ok === undefined ? 'bg-gray-300' : ok ? 'bg-green-500' : 'bg-red-500';
  return <span className={`inline-block h-2.5 w-2.5 rounded-full ${colour}`} />;
}

/** Phase 0 backend health indicator, kept compact on the dashboard. */
export default function HealthCard() {
  const health = useQuery({ queryKey: ['health'], queryFn: getHealth, refetchInterval: 10_000 });

  return (
    <section className="flex items-center gap-4 rounded-lg border border-gray-200 bg-white px-4 py-2 text-xs">
      <span className="font-medium uppercase tracking-wide text-gray-500">Backend</span>
      {health.isError ? (
        <span className="text-red-600">API unreachable</span>
      ) : (
        (['db', 'redis', 'osrm'] as const).map((k) => (
          <span key={k} className="flex items-center gap-1.5 text-gray-700">
            <Dot ok={health.data?.[k]} />
            <span className="uppercase">{k}</span>
          </span>
        ))
      )}
      {health.dataUpdatedAt > 0 && (
        <span className="ml-auto text-gray-400">Checked {formatTimeIST(new Date(health.dataUpdatedAt))} IST</span>
      )}
    </section>
  );
}
