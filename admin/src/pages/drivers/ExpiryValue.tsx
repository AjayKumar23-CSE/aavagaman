import { formatDay, isExpired } from '../../lib/time';

/** A calendar date, in red when it has passed. */
export function ExpiryValue({ value }: { value: string | null }) {
  if (!value) return <>—</>;
  return isExpired(value) ? (
    <span className="font-medium text-red-700">{formatDay(value)} (expired)</span>
  ) : (
    <>{formatDay(value)}</>
  );
}
