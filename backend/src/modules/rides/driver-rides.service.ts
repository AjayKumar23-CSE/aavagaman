import { HttpStatus, Injectable } from '@nestjs/common';
import { RideStatus } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { PageQuery, skipTake } from '../../common/pagination';
import { PrismaService } from '../../common/prisma.service';
import { commissionOf, gstOf } from '../fare/fare.engine';
import { MatchingService } from '../matching/matching.service';
import { presentRide } from './ride.presenter';
import { LoadedRide, RideRepository } from './ride.repository';

/** Driver's open ride: assigned and not yet paid (COMPLETED = collect payment). */
export const DRIVER_OPEN_STATUSES: RideStatus[] = ['ACCEPTED', 'ARRIVED', 'STARTED', 'COMPLETED'];

@Injectable()
export class DriverRidesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rides: RideRepository,
    private readonly matching: MatchingService,
  ) {}

  async active(driverId: string) {
    const [ride] = await this.rides.findMany(
      { driverId, status: { in: DRIVER_OPEN_STATUSES } },
      { take: 1 },
    );
    if (!ride) throw new AppException('NO_ACTIVE_RIDE', 'No active ride', HttpStatus.NOT_FOUND);
    return presentRide(ride, 'driver');
  }

  /** GET /driver/rides — history, newest first. */
  async list(driverId: string, q: PageQuery) {
    const where = { driverId };
    const [rides, total] = await Promise.all([
      this.rides.findMany(where, skipTake(q)),
      this.prisma.ride.count({ where }),
    ]);
    const configIds = [...new Set(rides.flatMap((r) => (r.fareConfigId ? [r.fareConfigId] : [])))];
    const configs = new Map(
      (
        await this.prisma.fareConfig.findMany({
          where: { id: { in: configIds } },
          select: { id: true, gstPct: true, commissionPct: true },
        })
      ).map((c) => [c.id, { gstPct: Number(c.gstPct), commissionPct: Number(c.commissionPct) }]),
    );
    return {
      data: rides.map((r) => ({
        ...presentRide(r, 'driver'),
        earning: earningOf(r, r.fareConfigId ? configs.get(r.fareConfigId) : undefined),
      })),
      page: q.page,
      limit: q.limit,
      total,
    };
  }

  async accept(driverId: string, rideId: string) {
    return presentRide(await this.matching.accept(driverId, rideId), 'driver');
  }

  reject(driverId: string, rideId: string) {
    return this.matching.reject(driverId, rideId);
  }
}

/**
 * Per-trip split for the driver's Earnings list (SPEC §12): fare, the
 * platform's commission, GST and what the driver keeps. Same arithmetic as
 * settlements; null until there is a final fare.
 */
function earningOf(r: LoadedRide, cfg?: { gstPct: number; commissionPct: number }) {
  if (r.finalFare === null || !cfg) return null;
  const fare = Number(r.finalFare);
  const commission = commissionOf(fare, cfg);
  const gst = gstOf(fare, cfg.gstPct);
  return { fare, commission, gst, net: Math.round((fare - commission - gst) * 100) / 100 };
}
