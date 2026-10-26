import {
  canGoOnline,
  documentProblems,
  DocLike,
  hasTurned,
  isExpired,
  latestByType,
  MANDATORY_DOCS,
  todayIST,
} from './driver-rules';

const day = (s: string) => new Date(s + 'T00:00:00Z');
const NOW = new Date('2026-09-28T10:00:00Z');

const approvedSet = (overrides: Partial<Record<string, Partial<DocLike>>> = {}): DocLike[] =>
  MANDATORY_DOCS.map((t) => ({
    docType: t,
    status: 'approved',
    expiry: t === 'driving_licence' ? day('2030-01-01') : null,
    uploadedAt: day('2026-09-01'),
    ...overrides[t],
  }));

describe('driver rules', () => {
  it('todayIST rolls over at IST midnight, not UTC', () => {
    // 19:00 UTC on the 28th is 00:30 IST on the 29th
    expect(todayIST(new Date('2026-09-28T19:00:00Z')).toISOString()).toBe(
      '2026-09-29T00:00:00.000Z',
    );
    expect(todayIST(new Date('2026-09-28T18:00:00Z')).toISOString()).toBe(
      '2026-09-28T00:00:00.000Z',
    );
  });

  it('a document expiring today is still valid', () => {
    expect(isExpired(day('2026-09-28'), NOW)).toBe(false);
    expect(isExpired(day('2026-09-27'), NOW)).toBe(true);
    expect(isExpired(null, NOW)).toBe(false);
  });

  it('uses the latest upload per type', () => {
    const docs: DocLike[] = [
      { docType: 'rc', status: 'rejected', expiry: null, uploadedAt: day('2026-09-01') },
      { docType: 'rc', status: 'pending', expiry: null, uploadedAt: day('2026-09-02') },
    ];
    expect(latestByType(docs).get('rc')!.status).toBe('pending');
  });

  it('allows online only with every mandatory doc approved and unexpired', () => {
    expect(canGoOnline('approved', approvedSet(), NOW)).toBe(true);
    expect(canGoOnline('pending', approvedSet(), NOW)).toBe(false);
    expect(canGoOnline('suspended', approvedSet(), NOW)).toBe(false);
    expect(
      canGoOnline(
        'approved',
        approvedSet().filter((d) => d.docType !== 'selfie'),
        NOW,
      ),
    ).toBe(false);
    expect(canGoOnline('approved', approvedSet({ insurance: { status: 'pending' } }), NOW)).toBe(
      false,
    );
    expect(
      canGoOnline('approved', approvedSet({ driving_licence: { expiry: day('2026-01-01') } }), NOW),
    ).toBe(false);
  });

  it('classifies document problems', () => {
    const p = documentProblems(
      approvedSet({
        rc: { status: 'rejected' },
        permit: { status: 'pending' },
        insurance: { expiry: day('2025-01-01') },
      }),
      NOW,
    );
    expect(p).toEqual({ missing: ['rc'], unapproved: ['permit'], expired: ['insurance'] });
  });

  it('hasTurned counts birthdays by the IST date', () => {
    const dob = day('2008-10-12');
    // 18:00 UTC on the 11th is still the 11th in IST (23:30).
    expect(hasTurned(dob, 18, new Date('2026-10-11T18:00:00Z'))).toBe(false);
    // 18:30 UTC on the 11th is 00:00 IST on the 12th: the 18th birthday.
    expect(hasTurned(dob, 18, new Date('2026-10-11T18:30:00Z'))).toBe(true);
    expect(hasTurned(day('2030-01-01'), 18, NOW)).toBe(false);
  });
});
