import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { DriverState, K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';

export interface DriverFix {
  lat: number;
  lng: number;
  heading?: number;
  speed?: number;
  accuracy?: number;
  ts?: number;
}

export interface NearbyDriver {
  driverId: string;
  distanceM: number;
  lat: number;
  lng: number;
}

// Compare-and-set so state moves are atomic (idle ⇄ offered, on_trip → idle).
const CAS_STATE = `
if redis.call('GET', KEYS[1]) == ARGV[1] then
  redis.call('SET', KEYS[1], ARGV[2])
  return 1
end
return 0`;

/** Driver presence and positions in Redis (SPEC §6). */
@Injectable()
export class LocationService {
  constructor(
    private readonly redis: RedisService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  async getState(driverId: string): Promise<DriverState> {
    return ((await this.redis.get(K.state(driverId))) as DriverState | null) ?? 'offline';
  }

  setState(driverId: string, state: DriverState) {
    return this.redis.set(K.state(driverId), state);
  }

  /** Atomically moves `from` → `to`; false if the driver was not in `from`. */
  async casState(driverId: string, from: DriverState, to: DriverState): Promise<boolean> {
    return (await this.redis.eval(CAS_STATE, 1, K.state(driverId), from, to)) === 1;
  }

  private write(driverId: string, fix: DriverFix) {
    const ttl = this.config.DRIVER_HEARTBEAT_TTL_SECONDS;
    const loc = {
      lat: fix.lat,
      lng: fix.lng,
      heading: fix.heading ?? 0,
      speed: fix.speed ?? 0,
      ts: fix.ts ?? Date.now(),
    };
    return this.redis
      .multi()
      .geoadd(K.geo, fix.lng, fix.lat, driverId)
      .set(K.hb(driverId), new Date().toISOString(), 'EX', ttl)
      .hset(K.loc(driverId), loc)
      .expire(K.loc(driverId), 60)
      .exec();
  }

  async goOnline(driverId: string, fix: DriverFix, vehicleType: string, state: DriverState) {
    await this.redis.set(K.vehicleType(driverId), vehicleType);
    await this.setState(driverId, state);
    await this.write(driverId, fix);
  }

  async goOffline(driverId: string) {
    await this.redis
      .multi()
      .zrem(K.geo, driverId)
      .del(K.hb(driverId), K.loc(driverId))
      .set(K.state(driverId), 'offline')
      .exec();
  }

  /** A ride left this driver (paid, cancelled, re-queued): back to idle if still on it. */
  async releaseFromRide(driverId: string, rideId: string) {
    await this.casState(driverId, 'on_trip', 'idle');
    await this.redis.del(K.driverRide(driverId), K.eta(rideId), K.nearbyPushed(rideId));
  }

  /** Records a fix; 409 DRIVER_OFFLINE tells the app to call POST /driver/online again. */
  async ingest(driverId: string, fix: DriverFix): Promise<DriverState> {
    const state = await this.getState(driverId);
    if (state === 'offline') {
      throw new AppException(
        'DRIVER_OFFLINE',
        'You are offline. Go online again.',
        HttpStatus.CONFLICT,
      );
    }
    await this.write(driverId, fix);
    return state;
  }

  async getLoc(driverId: string): Promise<(DriverFix & { heading: number }) | null> {
    const h = await this.redis.hgetall(K.loc(driverId));
    if (!h.lat) return null;
    return {
      lat: Number(h.lat),
      lng: Number(h.lng),
      heading: Number(h.heading),
      speed: Number(h.speed),
      ts: Number(h.ts),
    };
  }

  /** Online drivers near a point, nearest first (GEOSEARCH … ASC). */
  async nearby(lat: number, lng: number, radiusKm: number, count: number): Promise<NearbyDriver[]> {
    const rows = (await this.redis.call(
      'GEOSEARCH',
      K.geo,
      'FROMLONLAT',
      lng,
      lat,
      'BYRADIUS',
      radiusKm,
      'km',
      'ASC',
      'COUNT',
      count,
      'WITHDIST',
      'WITHCOORD',
    )) as [string, string, [string, string]][];
    return rows.map(([driverId, dist, [lng2, lat2]]) => ({
      driverId,
      distanceM: Math.round(Number(dist) * 1000),
      lat: Number(lat2),
      lng: Number(lng2),
    }));
  }

  /** Drivers in the GEO set whose heartbeat key has expired. */
  async staleDrivers(): Promise<string[]> {
    const members = await this.redis.zrange(K.geo, 0, -1);
    if (!members.length) return [];
    const alive = await this.redis.pipeline(members.map((m) => ['exists', K.hb(m)])).exec();
    return members.filter((_, i) => alive?.[i]?.[1] === 0);
  }
}
