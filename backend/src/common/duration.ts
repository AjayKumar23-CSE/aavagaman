const UNITS: Record<string, number> = { s: 1_000, m: 60_000, h: 3_600_000, d: 86_400_000 };

/** "15m" / "90d" / "30s" → milliseconds. */
export function parseDurationMs(value: string): number {
  const m = /^(\d+)\s*([smhd])$/.exec(value.trim());
  if (!m) throw new Error(`Invalid duration "${value}" (use e.g. 30s, 15m, 12h, 90d)`);
  return Number(m[1]) * UNITS[m[2]];
}
