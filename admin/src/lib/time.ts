/** SPEC §2: timestamps are stored in UTC and displayed in IST. */
const IST = new Intl.DateTimeFormat('en-IN', {
  timeZone: 'Asia/Kolkata',
  dateStyle: 'medium',
  timeStyle: 'short',
});

const IST_TIME = new Intl.DateTimeFormat('en-IN', {
  timeZone: 'Asia/Kolkata',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hour12: false,
});

const IST_YMD = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Kolkata',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

const IST_PARTS = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Kolkata',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const DAY = new Intl.DateTimeFormat('en-IN', { timeZone: 'UTC', dateStyle: 'medium' });
const DAY_SHORT = new Intl.DateTimeFormat('en-IN', { timeZone: 'UTC', day: 'numeric', month: 'short' });

const INR = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 });

const IST_OFFSET = '+05:30';

export function formatIST(value: string | Date): string {
  return IST.format(typeof value === 'string' ? new Date(value) : value);
}

/** Time of day only (HH:mm:ss IST), for "last update" style indicators. */
export function formatTimeIST(value: string | Date): string {
  return IST_TIME.format(typeof value === 'string' ? new Date(value) : value);
}

/** Formats a calendar date (YYYY-MM-DD, no time zone) such as a document expiry. */
export function formatDay(ymd: string): string {
  return DAY.format(new Date(ymd + 'T00:00:00Z'));
}

/** "4 Oct" — compact calendar date for chart axes. */
export function formatDayShort(ymd: string): string {
  return DAY_SHORT.format(new Date(ymd + 'T00:00:00Z'));
}

/** Today's date in IST as YYYY-MM-DD. */
export function todayIST(): string {
  return IST_YMD.format(new Date());
}

/** True when a YYYY-MM-DD expiry date is before today (IST). */
export function isExpired(ymd: string | null | undefined): boolean {
  return !!ymd && ymd < todayIST();
}

/** Adds `n` calendar days to a YYYY-MM-DD date. */
export function addDays(ymd: string, n: number): string {
  const d = new Date(ymd + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** Monday (YYYY-MM-DD) of the Mon–Sun week containing the given date. */
export function mondayOf(ymd: string): string {
  const dow = (new Date(ymd + 'T00:00:00Z').getUTCDay() + 6) % 7;
  return addDays(ymd, -dow);
}

/** 00:00 IST of a calendar day as an ISO instant, for `from`/`to` query params. */
export function istDayStartISO(ymd: string): string {
  return new Date(`${ymd}T00:00:00${IST_OFFSET}`).toISOString();
}

/** Instant → value for an `<input type="datetime-local">` expressed in IST. */
export function toISTDateTimeLocal(value: string | Date): string {
  const parts = IST_PARTS.formatToParts(typeof value === 'string' ? new Date(value) : value);
  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? '';
  // "24" can appear for midnight in some engines; normalise to 00.
  const hour = get('hour') === '24' ? '00' : get('hour');
  return `${get('year')}-${get('month')}-${get('day')}T${hour}:${get('minute')}`;
}

/** `<input type="datetime-local">` value interpreted in IST → ISO instant. */
export function fromISTDateTimeLocal(local: string): string {
  return new Date(`${local}:00${IST_OFFSET}`).toISOString();
}

export function formatINR(value: number | null | undefined): string {
  return value === null || value === undefined ? '—' : INR.format(value);
}

export function formatKm(metres: number | null | undefined): string {
  return metres === null || metres === undefined ? '—' : `${(metres / 1000).toFixed(1)} km`;
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return '—';
  const m = Math.round(seconds / 60);
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} min`;
}

/** "just now", "12 s ago", "3 min ago" — for freshness indicators. Pass `now` from a ticking state to re-render live. */
export function formatAgo(value: string | Date | number, now: number = Date.now()): string {
  const t = typeof value === 'number' ? value : new Date(value).getTime();
  const s = Math.max(0, Math.round((now - t) / 1000));
  if (s < 5) return 'just now';
  if (s < 60) return `${s} s ago`;
  const m = Math.round(s / 60);
  return m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
}
