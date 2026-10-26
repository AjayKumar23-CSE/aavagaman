import type { DocType, VerificationStatus } from '@prisma/client';

/** Documents a driver must have approved before going online (D-013). */
export const MANDATORY_DOCS: readonly DocType[] = [
  'driving_licence',
  'rc',
  'insurance',
  'permit',
  'id_proof',
  'selfie',
];

/** Document types that carry an expiry date the driver must supply. */
export const EXPIRING_DOCS: readonly DocType[] = [
  'driving_licence',
  'insurance',
  'permit',
  'fitness',
];

export const UPLOAD_CONTENT_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/pdf': 'pdf',
};

export interface DocLike {
  docType: DocType;
  status: VerificationStatus;
  expiry: Date | null;
  uploadedAt: Date | null;
}

/** Most recent upload per document type. */
export function latestByType<T extends DocLike>(docs: T[]): Map<DocType, T> {
  const out = new Map<DocType, T>();
  for (const d of [...docs].sort(
    (a, b) => (b.uploadedAt?.getTime() ?? 0) - (a.uploadedAt?.getTime() ?? 0),
  )) {
    if (!out.has(d.docType)) out.set(d.docType, d);
  }
  return out;
}

/** Start of today in IST, as a UTC instant (dates are compared in IST, SPEC §2). */
export function todayIST(now = new Date()): Date {
  const ist = new Date(now.getTime() + 5.5 * 3_600_000);
  return new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate()));
}

/** Minimum age to register as a driver (LMV licence age). */
export const MIN_DRIVER_AGE = 18;

/** Whether someone born on `dob` has turned `years` by today (IST). */
export function hasTurned(dob: Date, years: number, now = new Date()): boolean {
  const birthday = new Date(
    Date.UTC(dob.getUTCFullYear() + years, dob.getUTCMonth(), dob.getUTCDate()),
  );
  return birthday.getTime() <= todayIST(now).getTime();
}

export const isExpired = (expiry: Date | null, now = new Date()) =>
  expiry !== null && expiry.getTime() < todayIST(now).getTime();

/** Mandatory types that are missing, not approved or expired. */
export function documentProblems(docs: DocLike[], now = new Date()) {
  const latest = latestByType(docs);
  const missing: DocType[] = [];
  const unapproved: DocType[] = [];
  const expired: DocType[] = [];
  for (const t of MANDATORY_DOCS) {
    const d = latest.get(t);
    if (!d || d.status === 'rejected') missing.push(t);
    else if (d.status !== 'approved') unapproved.push(t);
    else if (isExpired(d.expiry, now)) expired.push(t);
  }
  return { missing, unapproved, expired };
}

/** SPEC §7.3: online only when approved and all mandatory docs approved and unexpired. */
export function canGoOnline(
  status: VerificationStatus,
  docs: DocLike[],
  now = new Date(),
): boolean {
  if (status !== 'approved') return false;
  const p = documentProblems(docs, now);
  return !p.missing.length && !p.unapproved.length && !p.expired.length;
}

/** Driver verification transitions available to an admin. */
export const DRIVER_ACTIONS = {
  approve: { from: ['pending', 'rejected'], to: 'approved' },
  reject: { from: ['pending', 'approved'], to: 'rejected' },
  suspend: { from: ['approved'], to: 'suspended' },
  reinstate: { from: ['suspended'], to: 'approved' },
} as const satisfies Record<
  string,
  { from: readonly VerificationStatus[]; to: VerificationStatus }
>;

export type DriverAction = keyof typeof DRIVER_ACTIONS;
