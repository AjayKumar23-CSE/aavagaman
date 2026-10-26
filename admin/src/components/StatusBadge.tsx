const COLOURS: Record<string, string> = {
  // driver verification / documents
  pending: 'bg-amber-100 text-amber-800 ring-amber-200',
  approved: 'bg-green-100 text-green-800 ring-green-200',
  rejected: 'bg-red-100 text-red-800 ring-red-200',
  suspended: 'bg-gray-800 text-white ring-gray-800',
  missing: 'bg-white text-red-700 ring-red-300',
  expired: 'bg-red-600 text-white ring-red-600',
  // rides (SPEC §10)
  REQUESTED: 'bg-amber-100 text-amber-800 ring-amber-200',
  ACCEPTED: 'bg-sky-100 text-sky-800 ring-sky-200',
  ARRIVED: 'bg-indigo-100 text-indigo-800 ring-indigo-200',
  STARTED: 'bg-blue-600 text-white ring-blue-600',
  COMPLETED: 'bg-emerald-100 text-emerald-800 ring-emerald-200',
  PAID: 'bg-green-600 text-white ring-green-600',
  CANCELLED: 'bg-red-100 text-red-800 ring-red-200',
  NO_DRIVER: 'bg-gray-200 text-gray-700 ring-gray-300',
  // users / payments / live states / settlements
  active: 'bg-green-100 text-green-800 ring-green-200',
  blocked: 'bg-red-600 text-white ring-red-600',
  paid: 'bg-green-100 text-green-800 ring-green-200',
  created: 'bg-amber-100 text-amber-800 ring-amber-200',
  failed: 'bg-red-100 text-red-800 ring-red-200',
  idle: 'bg-green-100 text-green-800 ring-green-200',
  offered: 'bg-amber-100 text-amber-800 ring-amber-200',
  on_trip: 'bg-blue-100 text-blue-800 ring-blue-200',
  offline: 'bg-gray-100 text-gray-600 ring-gray-200',
  settled: 'bg-green-100 text-green-800 ring-green-200',
  open: 'bg-red-600 text-white ring-red-600',
  acknowledged: 'bg-gray-100 text-gray-700 ring-gray-200',
  current: 'bg-gray-900 text-white ring-gray-900',
  scheduled: 'bg-amber-100 text-amber-800 ring-amber-200',
  superseded: 'bg-gray-100 text-gray-600 ring-gray-200',
};

export default function StatusBadge({ status }: { status: string }) {
  const colour = COLOURS[status] ?? 'bg-gray-100 text-gray-700 ring-gray-200';
  // Enum values such as NO_DRIVER / on_trip read better as "no driver" / "on trip".
  const label = (/^[A-Z_]+$/.test(status) ? status.toLowerCase() : status).replace(/_/g, ' ');
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap capitalize ring-1 ring-inset ${colour}`}
    >
      {label}
    </span>
  );
}
