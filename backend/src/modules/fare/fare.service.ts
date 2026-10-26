import { HttpStatus, Injectable } from '@nestjs/common';
import type { FareConfig } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import type { LatLng } from '../../common/geo/geo';
import { PrismaService } from '../../common/prisma.service';
import { DEFAULT_VEHICLE_TYPE, VEHICLE_SEATS, VEHICLE_TYPES } from '../../common/vehicle-types';
import { GeofenceService } from '../geofence/geofence.service';
import { RoutingService } from '../routing/routing.service';
import { estimate, FareConfigValues } from './fare.engine';

export const toFareValues = (c: FareConfig): FareConfigValues => ({
  baseFare: Number(c.baseFare),
  perKm: Number(c.perKm),
  perMin: Number(c.perMin),
  minFare: Number(c.minFare),
  nightMultiplier: Number(c.nightMultiplier),
  nightEnabled: c.nightEnabled,
  gstPct: Number(c.gstPct),
  commissionPct: Number(c.commissionPct),
});

@Injectable()
export class FareService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly routing: RoutingService,
    private readonly geofence: GeofenceService,
  ) {}

  /** Latest config whose effective_from has passed (SPEC §7.4 "new effective config"). */
  async current(vehicleType = 'sedan', at = new Date()): Promise<FareConfig> {
    const cfg = await this.prisma.fareConfig.findFirst({
      where: { vehicleType, effectiveFrom: { lte: at } },
      orderBy: { effectiveFrom: 'desc' },
    });
    if (!cfg)
      throw new AppException(
        'FARE_CONFIG_MISSING',
        'Fares are not configured',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    return cfg;
  }

  /** Latest effective config of every vehicle class that has one, in display order (D-056). */
  async currentAll(at = new Date()): Promise<FareConfig[]> {
    const rows = await this.prisma.fareConfig.findMany({
      where: { effectiveFrom: { lte: at } },
      orderBy: { effectiveFrom: 'desc' },
    });
    const byType = new Map<string, FareConfig>();
    for (const r of rows) if (!byType.has(r.vehicleType)) byType.set(r.vehicleType, r);
    const configs = VEHICLE_TYPES.flatMap((t) => byType.get(t) ?? []);
    if (!configs.length)
      throw new AppException(
        'FARE_CONFIG_MISSING',
        'Fares are not configured',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    return configs;
  }

  /**
   * One route, one fare per vehicle class. The top-level fields describe the
   * default class (sedan) so older app builds keep working; `options` carries
   * every class the rider can pick (D-056).
   */
  async estimate(pickup: LatLng, drop: LatLng) {
    const [route, configs, pickupIn, dropIn] = await Promise.all([
      this.routing.route(pickup, drop),
      this.currentAll(),
      this.geofence.isInsideServiceArea(pickup.lat, pickup.lng),
      this.geofence.isInsideServiceArea(drop.lat, drop.lng),
    ]);
    const now = new Date();
    const options = configs.map((cfg) => {
      const e = estimate(route.distance_m, route.duration_s, toFareValues(cfg), now);
      return {
        vehicle_type: cfg.vehicleType,
        seats: VEHICLE_SEATS[cfg.vehicleType as keyof typeof VEHICLE_SEATS] ?? 4,
        fare_min: e.fare_min,
        fare_max: e.fare_max,
        fare_config_id: cfg.id,
      };
    });
    const primary = options.find((o) => o.vehicle_type === DEFAULT_VEHICLE_TYPE) ?? options[0];
    return {
      distance_m: route.distance_m,
      duration_s: route.duration_s,
      vehicle_type: primary.vehicle_type,
      fare_min: primary.fare_min,
      fare_max: primary.fare_max,
      currency: 'INR' as const,
      in_service_area: { pickup: pickupIn, drop: dropIn },
      fare_config_id: primary.fare_config_id,
      options,
    };
  }
}
