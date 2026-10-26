/** Indian mobile numbers in E.164 (SPEC §5: e.g. +9198xxxxxxxx). */
export const INDIAN_MOBILE = /^\+91[6-9]\d{9}$/;

/** Accepts "98xxxxxxxx", "098…", "91…", "+91 98…" and returns E.164, or null. */
export function normalizeIndianPhone(input: string): string | null {
  const digits = input.replace(/[\s\-()]/g, '');
  let n = digits;
  if (/^[6-9]\d{9}$/.test(n)) n = '+91' + n;
  else if (/^0[6-9]\d{9}$/.test(n)) n = '+91' + n.slice(1);
  else if (/^91[6-9]\d{9}$/.test(n)) n = '+' + n;
  return INDIAN_MOBILE.test(n) ? n : null;
}

/** "+919812345678" → "******5678" (SPEC §16: phones masked in logs/payloads). */
export function maskPhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  return '*'.repeat(Math.max(0, phone.length - 4 - 3)) + phone.slice(-4);
}
