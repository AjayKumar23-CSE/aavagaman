import { isCallable, tooSoon } from './calls.service';

describe('calls rules', () => {
  it('calls are allowed only while a driver is on the way or the trip runs', () => {
    expect(isCallable('ACCEPTED')).toBe(true);
    expect(isCallable('ARRIVED')).toBe(true);
    expect(isCallable('STARTED')).toBe(true);
    expect(isCallable('REQUESTED')).toBe(false);
    expect(isCallable('COMPLETED')).toBe(false);
    expect(isCallable('CANCELLED')).toBe(false);
  });

  it('tooSoon blocks a repeat within the interval only', () => {
    const now = new Date('2026-10-18T10:00:30Z');
    expect(tooSoon(null, now, 15)).toBe(false);
    expect(tooSoon({ createdAt: new Date('2026-10-18T10:00:20Z') }, now, 15)).toBe(true);
    expect(tooSoon({ createdAt: new Date('2026-10-18T10:00:10Z') }, now, 15)).toBe(false);
  });
});
