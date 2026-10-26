import {
  breakdown,
  commissionOf,
  estimate,
  FareConfigValues,
  finalFare,
  gstOf,
  isNight,
} from './fare.engine';

// Seed config (SPEC §5) — Appendix B uses 50 / 12 / 1.5 / min 80.
const cfg: FareConfigValues = {
  baseFare: 50,
  perKm: 12,
  perMin: 1.5,
  minFare: 80,
  nightMultiplier: 1.25,
  nightEnabled: false,
  gstPct: 5,
  commissionPct: 15,
};
const night: FareConfigValues = { ...cfg, nightEnabled: true };

const DAY = new Date('2026-09-28T06:30:00Z'); // 12:00 IST
const NIGHT = new Date('2026-09-28T18:30:00Z'); // 00:00 IST

describe('fare engine — SPEC Appendix B', () => {
  it('2.0 km / 8 min → 86, range 82–95', () => {
    expect(estimate(2000, 480, cfg, DAY)).toEqual({ fare: 86, fare_min: 82, fare_max: 95 });
  });

  it('10.0 km / 30 min → 215, range 204–237', () => {
    expect(estimate(10_000, 1800, cfg, DAY)).toEqual({ fare: 215, fare_min: 204, fare_max: 237 });
  });

  it('1.0 km / 4 min → min fare 80, range 76–88', () => {
    expect(estimate(1000, 240, cfg, DAY)).toEqual({ fare: 80, fare_min: 76, fare_max: 88 });
  });

  it('10.0 km / 30 min at night ×1.25 → 268.75, range 255–296', () => {
    expect(estimate(10_000, 1800, night, NIGHT)).toEqual({
      fare: 268.75,
      fare_min: 255,
      fare_max: 296,
    });
  });

  it('final: est 215, actual 14 km / 45 min, drop unchanged → capped 268.75 → 269', () => {
    const est = estimate(10_000, 1800, cfg, DAY);
    expect(finalFare(14_000, 2700, cfg, est, false, DAY)).toBe(269);
  });
});

describe('fare engine — branches', () => {
  it('final fare is uncapped when the drop changed', () => {
    const est = estimate(10_000, 1800, cfg, DAY);
    expect(finalFare(14_000, 2700, cfg, est, true, DAY)).toBe(286); // 285.5 → 286
  });

  it('final fare never goes below the minimum', () => {
    const est = estimate(1000, 240, cfg, DAY);
    expect(finalFare(200, 60, cfg, est, false, DAY)).toBe(80);
  });

  it('final fare below the cap is charged as-is', () => {
    const est = estimate(10_000, 1800, cfg, DAY);
    expect(finalFare(11_000, 1800, cfg, est, false, DAY)).toBe(227);
  });

  it('night uses the trip start time, and only when enabled', () => {
    const est = estimate(10_000, 1800, night, NIGHT);
    expect(finalFare(10_000, 1800, night, est, false, NIGHT)).toBe(269);
    expect(finalFare(10_000, 1800, night, est, false, DAY)).toBe(215);
    expect(estimate(10_000, 1800, cfg, NIGHT).fare).toBe(215);
  });

  it('min fare applies before the night multiplier is compared', () => {
    // raw 68 × 1.25 = 85 > 80
    expect(estimate(1000, 240, night, NIGHT).fare).toBe(85);
  });

  it.each([
    ['2026-09-28T17:29:00Z', false], // 22:59 IST
    ['2026-09-28T17:30:00Z', true], // 23:00 IST
    ['2026-09-28T23:29:00Z', true], // 04:59 IST
    ['2026-09-28T23:30:00Z', false], // 05:00 IST
  ])('isNight(%s) = %s', (iso, expected) => {
    expect(isNight(new Date(iso))).toBe(expected);
  });

  it('GST and commission (commission on fare excl. GST)', () => {
    expect(gstOf(210, 5)).toBe(10);
    expect(commissionOf(210, cfg)).toBe(30); // (210 − 10) × 15%
  });
});

describe('fare engine — breakdown', () => {
  it('exposes the components that sum to the raw fare', () => {
    const b = breakdown(10_000, 1800, cfg, DAY);
    expect(b).toEqual({ base: 50, distance: 120, time: 45, night_multiplier: null, raw: 215 });
    const n = breakdown(10_000, 1800, night, NIGHT);
    expect(n.night_multiplier).toBe(1.25);
    expect(n.raw).toBeCloseTo(268.75);
  });
});
