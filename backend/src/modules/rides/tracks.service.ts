import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';
import type { LatLng } from '../../common/geo/geo';
import type { TrackPoint } from './tracks';

export interface TrackFix extends LatLng {
  speed?: number;
  accuracy?: number;
  /** Client timestamp (epoch ms); used when within 2 minutes of server time. */
  ts?: number;
}

const MAX_CLOCK_SKEW_MS = 2 * 60_000;

/** ride_tracks storage (SPEC §5). Points are written while a driver is on a ride. */
@Injectable()
export class TracksService {
  constructor(private readonly prisma: PrismaService) {}

  recordedAt(fix: TrackFix, now = new Date()): Date {
    if (fix.ts && Math.abs(now.getTime() - fix.ts) <= MAX_CLOCK_SKEW_MS) return new Date(fix.ts);
    return now;
  }

  async record(rideId: string, fix: TrackFix, at = this.recordedAt(fix)) {
    await this.prisma.$executeRaw`
      INSERT INTO ride_tracks (ride_id, recorded_at, point, speed_mps, accuracy_m)
      VALUES (${rideId}::uuid, ${at}, ST_SetSRID(ST_MakePoint(${fix.lng}, ${fix.lat}), 4326)::geography,
              ${fix.speed ?? null}::real, ${fix.accuracy ?? null}::real)
      ON CONFLICT DO NOTHING`;
  }

  async between(rideId: string, from: Date, to: Date): Promise<TrackPoint[]> {
    const rows = await this.prisma.$queryRaw<
      { lat: number; lng: number; recorded_at: Date; accuracy_m: number | null }[]
    >`
      SELECT ST_Y(point::geometry) AS lat, ST_X(point::geometry) AS lng, recorded_at, accuracy_m
      FROM ride_tracks
      WHERE ride_id = ${rideId}::uuid AND recorded_at BETWEEN ${from} AND ${to}
      ORDER BY recorded_at`;
    return rows.map((r) => ({
      lat: r.lat,
      lng: r.lng,
      recordedAt: r.recorded_at,
      accuracyM: r.accuracy_m,
    }));
  }

  /** GeoJSON LineString of the whole track (admin ride detail, SPEC §7.4). */
  async geojson(rideId: string) {
    const rows = await this.prisma.$queryRaw<{ lat: number; lng: number; recorded_at: Date }[]>`
      SELECT ST_Y(point::geometry) AS lat, ST_X(point::geometry) AS lng, recorded_at
      FROM ride_tracks WHERE ride_id = ${rideId}::uuid ORDER BY recorded_at`;
    return {
      type: 'Feature' as const,
      properties: {
        ride_id: rideId,
        points: rows.length,
        from: rows[0]?.recorded_at ?? null,
        to: rows.at(-1)?.recorded_at ?? null,
      },
      geometry: { type: 'LineString' as const, coordinates: rows.map((r) => [r.lng, r.lat]) },
    };
  }
}
