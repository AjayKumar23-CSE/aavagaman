import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';
import { DriverState, K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { LocationService } from '../location/location.service';
import { ACTIVE_STATUSES } from '../rides/ride-state';
import { RideRepository } from '../rides/ride.repository';

/** Snapshot behind GET /admin/live and the admin:live stream (SPEC §7.4, §8, §13). */
@Injectable()
export class LiveService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly location: LocationService,
    private readonly rides: RideRepository,
  ) {}

  async snapshot() {
    const ids = await this.redis.zrange(K.geo, 0, -1);
    const [users, states, locs] = await Promise.all([
      ids.length
        ? this.prisma.user.findMany({
            where: { id: { in: ids } },
            select: {
              id: true,
              name: true,
              driver: {
                select: { vehicles: { where: { active: true }, select: { regNumber: true } } },
              },
            },
          })
        : [],
      Promise.all(ids.map((id) => this.location.getState(id))),
      Promise.all(ids.map((id) => this.location.getLoc(id))),
    ]);
    const byId = new Map(users.map((u) => [u.id, u]));
    const drivers = ids.map((id, i) => ({
      driver_id: id,
      name: byId.get(id)?.name ?? null,
      reg_number: byId.get(id)?.driver?.vehicles[0]?.regNumber ?? null,
      state: states[i] as DriverState,
      lat: locs[i]?.lat ?? null,
      lng: locs[i]?.lng ?? null,
      heading: locs[i]?.heading ?? 0,
      updated_at: locs[i]?.ts ? new Date(locs[i]!.ts!).toISOString() : null,
    }));

    const active = await this.rides.findMany(
      { status: { in: [...ACTIVE_STATUSES] } },
      { take: 200 },
    );
    const rides = active.map((r) => ({
      ride_id: r.id,
      status: r.status,
      rider_name: r.rider.name,
      driver_id: r.driverId,
      driver_name: r.driver?.user.name ?? null,
      pickup: { lat: r.coords.pickup_lat, lng: r.coords.pickup_lng, address: r.pickupAddress },
      drop: { lat: r.coords.drop_lat, lng: r.coords.drop_lng, address: r.dropAddress },
      requested_at: r.requestedAt,
      accepted_at: r.acceptedAt,
    }));
    return { at: new Date().toISOString(), drivers, rides };
  }
}
