import { Injectable, NotFoundException } from '@nestjs/common';
import { RideStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { LocationService } from '../location/location.service';
import { RideRepository } from '../rides/ride.repository';

const LIVE: RideStatus[] = ['ACCEPTED', 'ARRIVED', 'STARTED'];

/** Public "share my trip" view (SPEC §7.2 GET /share/:token). No rider identity, no phone numbers. */
@Injectable()
export class ShareService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly rides: RideRepository,
    private readonly location: LocationService,
  ) {}

  async view(token: string) {
    const row = await this.prisma.ride.findUnique({
      where: { shareToken: token },
      select: { id: true },
    });
    if (!row) throw new NotFoundException('This trip link is not valid');
    const ride = await this.rides.get(row.id);
    const live = LIVE.includes(ride.status) && ride.driverId;
    const loc = live ? await this.location.getLoc(ride.driverId!) : null;
    const eta = ride.status === 'ACCEPTED' ? await this.redis.get(K.eta(ride.id)) : null;
    return {
      status: ride.status,
      driver_name: ride.driver?.user.name ?? null,
      vehicle: ride.vehicle
        ? {
            reg_number: ride.vehicle.regNumber,
            make: ride.vehicle.make,
            model: ride.vehicle.model,
            colour: ride.vehicle.colour,
          }
        : null,
      current_location: loc
        ? {
            lat: loc.lat,
            lng: loc.lng,
            heading: loc.heading,
            at: loc.ts ? new Date(loc.ts).toISOString() : null,
          }
        : null,
      eta_s: eta ? Number(eta) : null,
      pickup: {
        lat: ride.coords.pickup_lat,
        lng: ride.coords.pickup_lng,
        address: ride.pickupAddress,
      },
      drop: { lat: ride.coords.drop_lat, lng: ride.coords.drop_lng, address: ride.dropAddress },
      started_at: ride.startedAt,
      completed_at: ride.completedAt,
      updated_at: new Date().toISOString(),
    };
  }
}
