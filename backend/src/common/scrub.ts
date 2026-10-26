const SENSITIVE =
  /^(phone|phone_masked|token|access_token|refresh_token|fcm_token|code|otp|trip_otp|password|authorization|cookie)$/i;

/** Deep-copies `value`, replacing sensitive keys (SPEC §16: Sentry scrubs phone and token fields). */
export function scrub<T>(value: T, depth = 0): T {
  if (depth > 8 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((v) => scrub(v, depth + 1)) as T;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    out[k] = SENSITIVE.test(k) ? '[redacted]' : scrub(v, depth + 1);
  }
  return out as T;
}
