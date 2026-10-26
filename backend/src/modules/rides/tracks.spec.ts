import { acceptedTrackPoints, trackDistanceM, TrackPoint } from './tracks';

const t0 = Date.parse('2026-09-28T10:00:00Z');
const pt = (lat: number, lng: number, s: number, acc: number | null = 10): TrackPoint => ({
  lat,
  lng,
  recordedAt: new Date(t0 + s * 1000),
  accuracyM: acc,
});

describe('ride tracks', () => {
  // 0.001° latitude ≈ 111 m
  const straight = [
    pt(28.63, 77.21, 0),
    pt(28.631, 77.21, 10),
    pt(28.632, 77.21, 20),
    pt(28.633, 77.21, 30),
  ];

  it('sums haversine legs over a clean track', () => {
    expect(trackDistanceM(straight)).toBeGreaterThan(330);
    expect(trackDistanceM(straight)).toBeLessThan(336);
  });

  it('drops inaccurate points', () => {
    const noisy = [...straight.slice(0, 2), pt(28.9, 77.9, 15, 500), ...straight.slice(2)];
    expect(acceptedTrackPoints(noisy)).toHaveLength(4);
    expect(trackDistanceM(noisy)).toBe(trackDistanceM(straight));
  });

  it('drops GPS jumps faster than 40 m/s', () => {
    // 1 km in 10 s = 100 m/s
    const jumpy = [...straight.slice(0, 2), pt(28.64, 77.21, 20), ...straight.slice(2)];
    const accepted = acceptedTrackPoints(jumpy);
    expect(accepted.map((p) => p.lat)).toEqual([28.63, 28.631, 28.632, 28.633]);
  });

  it('sorts by time and ignores duplicate timestamps', () => {
    const shuffled = [straight[2], straight[0], straight[3], straight[1], pt(28.7, 77.3, 20)];
    expect(acceptedTrackPoints(shuffled).map((p) => p.lat)).toEqual([
      28.63, 28.631, 28.632, 28.633,
    ]);
  });

  it('accepts points without an accuracy value', () => {
    expect(
      acceptedTrackPoints([pt(28.63, 77.21, 0, null), pt(28.631, 77.21, 10, null)]),
    ).toHaveLength(2);
  });
});
