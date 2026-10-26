import { createHmac } from 'node:crypto';
import { HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { canGoOnline } from '../drivers/driver-rules';
import { MatchingService } from '../matching/matching.service';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { DRIVER_ACTIVE_STATUSES } from '../rides/ride-state';
import { RideRepository } from '../rides/ride.repository';
import { RoutingService } from '../routing/routing.service';
import { haversineM } from '../../common/geo/geo';
import { PushService } from '../notifications/push.service';
import { TracksService } from '../rides/tracks.service';
import { DriverFix, LocationService } from './location.service';

/** SPEC §9.7: ETA to pickup recomputed at most every 15 s while ACCEPTED. */
export const ETA_REFRESH_SECONDS = 15;
/** SPEC §14: "Your driver is nearby" once the driver is within this distance of the pickup. */
export const NEARBY_PUSH_M = 300;
const NEARBY_MAX = 10;

@Injectable()
export class PresenceService {
  private readonly logger = new Logger(PresenceService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly location: LocationService,
    private readonly matching: MatchingService,
    private readonly rides: RideRepository,
    private readonly routing: RoutingService,
    private readonly rt: RealtimeEmitter,
    private readonly tracks: TracksService,
    private readonly push: PushService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  private activeRide(driverId: string) {
    return this.prisma.ride.findFirst({
      where: { driverId, status: { in: [...DRIVER_ACTIVE_STATUSES] } },
      select: { id: true },
    });
  }

  /** POST /driver/online — 403 unless approved with every mandatory document valid. */
  async online(driverId: string, fix: DriverFix) {
    const d = await this.prisma.driver.findUnique({
      where: { userId: driverId },
      include: { user: true, documents: true, vehicles: { where: { active: true } } },
    });
    if (
      !d ||
      d.user.status !== 'active' ||
      !canGoOnline(d.verificationStatus, d.documents) ||
      !d.vehicles.length
    ) {
      throw new AppException(
        'NOT_ELIGIBLE',
        'Your account is not approved to go online',
        HttpStatus.FORBIDDEN,
      );
    }
    const active = await this.activeRide(driverId);
    const current = await this.location.getState(driverId);
    // Reconnecting mid-trip or mid-offer keeps that state.
    const state = active ? 'on_trip' : current === 'offered' ? 'offered' : 'idle';
    if (active) await this.redis.set(K.driverRide(driverId), active.id);
    await this.location.goOnline(driverId, fix, d.vehicles[0].vehicleType, state);
    return state;
  }

  /** POST /driver/offline — 409 while on a trip; an open offer counts as rejected. */
  async offline(driverId: string) {
    if (await this.activeRide(driverId)) {
      throw new AppException(
        'ON_TRIP',
        'Finish your ride before going offline',
        HttpStatus.CONFLICT,
      );
    }
    // Every open offer counts as rejected (SPEC §9.4).
    await this.matching.withdrawFrom(driverId, 'rejected').catch(() => undefined);
    await this.location.goOffline(driverId);
  }

  /** REST and WebSocket location ingest; fans out to the rider/admin during a ride. */
  async ingest(driverId: string, fix: DriverFix) {
    const state = await this.location.ingest(driverId, fix);
    if (state === 'on_trip')
      await this.fanOut(driverId, fix).catch((e: Error) =>
        this.logger.warn(`fan-out: ${e.message}`),
      );
  }

  private async fanOut(driverId: string, fix: DriverFix) {
    const rideId = await this.redis.get(K.driverRide(driverId));
    if (!rideId) return;
    const ride = await this.rides.find(rideId);
    if (!ride || ride.driverId !== driverId || !DRIVER_ACTIVE_STATUSES.includes(ride.status)) {
      await this.redis.del(K.driverRide(driverId));
      return;
    }
    await this.tracks.record(rideId, fix);
    let eta_s: number | undefined;
    if (ride.status === 'ACCEPTED') {
      const pickup = { lat: ride.coords.pickup_lat, lng: ride.coords.pickup_lng };
      if (haversineM(fix, pickup) <= NEARBY_PUSH_M) {
        const first = await this.redis.set(K.nearbyPushed(rideId), '1', 'EX', 3600, 'NX');
        if (first) {
          void this.push.toUser(ride.riderId, {
            title: 'Your driver is nearby',
            body: 'Your driver is nearby',
            data: { type: 'driver_nearby', ride_id: rideId },
          });
        }
      }
      const cached = await this.redis.get(K.eta(rideId));
      if (cached) eta_s = Number(cached);
      else {
        const pickup = { lat: ride.coords.pickup_lat, lng: ride.coords.pickup_lng };
        eta_s = await this.routing
          .route(fix, pickup)
          .then((r) => r.duration_s)
          .catch(() => undefined);
        if (eta_s !== undefined)
          await this.redis.set(K.eta(rideId), eta_s, 'EX', ETA_REFRESH_SECONDS);
      }
    }
    const payload = {
      ride_id: rideId,
      driver_id: driverId,
      lat: fix.lat,
      lng: fix.lng,
      heading: fix.heading ?? 0,
      ...(eta_s !== undefined ? { eta_s } : {}),
    };
    this.rt.toUser(ride.riderId, 'driver:position', payload);
    this.rt.toAdmins('driver:position', payload);
  }

  /**
   * GET /drivers/nearby — "cars around you": up to 10 idle drivers, ids replaced by a
   * daily-rotating opaque token so riders cannot track individual drivers (D-024).
   */
  async nearbyForRider(lat: number, lng: number) {
    const candidates = await this.location.nearby(
      lat,
      lng,
      this.config.DEFAULT_SEARCH_RADIUS_KM,
      NEARBY_MAX * 3,
    );
    const day = new Date().toISOString().slice(0, 10);
    const out: { driver_id: string; lat: number; lng: number; heading: number; vehicle_type: string }[] = [];
    for (const c of candidates) {
      if ((await this.location.getState(c.driverId)) !== 'idle') continue;
      const loc = await this.location.getLoc(c.driverId);
      out.push({
        driver_id: createHmac('sha256', this.config.JWT_ACCESS_SECRET)
          .update(`${c.driverId}:${day}`)
          .digest('hex')
          .slice(0, 16),
        lat: c.lat,
        lng: c.lng,
        heading: loc?.heading ?? 0,
        vehicle_type: (await this.redis.get(K.vehicleType(c.driverId))) ?? 'sedan',
      });
      if (out.length === NEARBY_MAX) break;
    }
    return out;
  }

  /** Latest position of a ride's driver, for rider:subscribe and share links. */
  async lastPosition(driverId: string) {
    return this.location.getLoc(driverId);
  }
}
