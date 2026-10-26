/**
 * SPEC §9.3 fare engine. Pure functions — no I/O, no clock reads.
 * Fares are GST-inclusive, in rupees.
 */
export interface FareConfigValues {
  baseFare: number;
  perKm: number;
  perMin: number;
  minFare: number;
  nightMultiplier: number;
  nightEnabled: boolean;
  gstPct: number;
  commissionPct: number;
}

export interface Estimate {
  /** Unrounded fare the range is built from (and the cap in finalFare). */
  fare: number;
  fare_min: number;
  fare_max: number;
}

const IST_OFFSET_MS = 5.5 * 3_600_000;

/** 23:00–05:00 IST. */
export function isNight(at: Date): boolean {
  const hour = new Date(at.getTime() + IST_OFFSET_MS).getUTCHours();
  return hour >= 23 || hour < 5;
}

export interface FareBreakdown {
  base: number;
  distance: number;
  time: number;
  night_multiplier: number | null;
  /** base + distance + time, after the night multiplier. */
  raw: number;
}

/** The components behind a fare, for receipts (SPEC §7.2 "fare breakdown"). */
export function breakdown(
  distanceM: number,
  durationS: number,
  cfg: FareConfigValues,
  at: Date,
): FareBreakdown {
  const base = cfg.baseFare;
  const distance = cfg.perKm * (distanceM / 1000);
  const time = cfg.perMin * (durationS / 60);
  const night = cfg.nightEnabled && isNight(at) ? cfg.nightMultiplier : null;
  const raw = (base + distance + time) * (night ?? 1);
  return { base, distance, time, night_multiplier: night, raw };
}

function rawFare(distanceM: number, durationS: number, cfg: FareConfigValues, at: Date): number {
  return breakdown(distanceM, durationS, cfg, at).raw;
}

export function estimate(
  distanceM: number,
  durationS: number,
  cfg: FareConfigValues,
  now: Date,
): Estimate {
  const fare = Math.max(cfg.minFare, rawFare(distanceM, durationS, cfg, now));
  return { fare, fare_min: Math.round(fare * 0.95), fare_max: Math.round(fare * 1.1) };
}

/** Final fare, capped at 125% of the estimate unless the drop changed. Nearest rupee. */
export function finalFare(
  actualDistanceM: number,
  actualDurationS: number,
  cfg: FareConfigValues,
  est: Pick<Estimate, 'fare'>,
  dropChanged: boolean,
  startedAt: Date,
): number {
  const f = rawFare(actualDistanceM, actualDurationS, cfg, startedAt);
  const cap = dropChanged ? Infinity : est.fare * 1.25;
  return Math.round(Math.min(Math.max(cfg.minFare, f), cap));
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/** GST contained in a GST-inclusive amount. */
export const gstOf = (fare: number, gstPct: number) => round2(fare - fare / (1 + gstPct / 100));

/** Commission is charged on the fare excluding GST. */
export const commissionOf = (
  fare: number,
  cfg: Pick<FareConfigValues, 'gstPct' | 'commissionPct'>,
) => round2((fare - gstOf(fare, cfg.gstPct)) * (cfg.commissionPct / 100));
