import { haversineM, LatLng } from '../../common/geo/geo';

export interface TrackPoint extends LatLng {
  recordedAt: Date;
  accuracyM: number | null;
}

/** SPEC §9.3: drop points with accuracy > 50 m or an implied speed > 40 m/s. */
export const MAX_ACCURACY_M = 50;
export const MAX_SPEED_MPS = 40;
/** Below this many accepted points the distance falls back to OSRM. */
export const MIN_TRACK_POINTS = 3;

/** Filters a chronological track down to the points that count towards distance. */
export function acceptedTrackPoints(points: TrackPoint[]): TrackPoint[] {
  const out: TrackPoint[] = [];
  for (const p of [...points].sort((a, b) => a.recordedAt.getTime() - b.recordedAt.getTime())) {
    if (p.accuracyM !== null && p.accuracyM > MAX_ACCURACY_M) continue;
    const prev = out[out.length - 1];
    if (prev) {
      const dt = (p.recordedAt.getTime() - prev.recordedAt.getTime()) / 1000;
      const d = haversineM(prev, p);
      if (dt <= 0 || d / dt > MAX_SPEED_MPS) continue;
    }
    out.push(p);
  }
  return out;
}

/** Sum of haversine legs over the accepted points, in metres (rounded). */
export function trackDistanceM(points: TrackPoint[]): number {
  const pts = acceptedTrackPoints(points);
  let total = 0;
  for (let i = 1; i < pts.length; i++) total += haversineM(pts[i - 1], pts[i]);
  return Math.round(total);
}
