import { randomBytes, randomInt } from 'node:crypto';
import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, RideStatus } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { DEFAULT_VEHICLE_TYPE } from '../../common/vehicle-types';
import { toWkt } from '../../common/geo/geo';
import { PrismaService } from '../../common/prisma.service';
import { estimate } from '../fare/fare.engine';
import { FareService, toFareValues } from '../fare/fare.service';
import { GeofenceService } from '../geofence/geofence.service';
import { MatchingService } from '../matching/matching.service';
import { RoutingService } from '../routing/routing.service';
import { Page, PageQuery, skipTake } from '../../common/pagination';
import { CancellationService } from './cancellation.service';
import { CancelRideDto, CreateRideDto } from './dto/ride.dto';
import { buildReceipt } from './receipt';
import { RideEventsService } from './ride-events.service';
import { presentRide } from './ride.presenter';
import { RidePublisher } from './ride.publisher';
import { RideRepository } from './ride.repository';

/** Statuses in which the rider app should resume into the ride (COMPLETED = awaiting payment). */
export const RIDER_OPEN_STATUSES: RideStatus[] = [
  'REQUESTED',
  'ACCEPTED',
  'ARRIVED',
  'STARTED',
  'COMPLETED',
];
const RIDER_BLOCKING_STATUSES: RideStatus[] = ['REQUESTED', 'ACCEPTED', 'ARRIVED', 'STARTED'];

@Injectable()
export class RidesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rides: RideRepository,
    private readonly events: RideEventsService,
    private readonly publisher: RidePublisher,
    private readonly matching: MatchingService,
    private readonly routing: RoutingService,
    private readonly geofence: GeofenceService,
    private readonly cancellation: CancellationService,
    private readonly fares: FareService,
  ) {}

  async create(riderId: string, dto: CreateRideDto) {
    if (!(await this.geofence.isInsideServiceArea(dto.pickup.lat, dto.pickup.lng))) {
      throw new AppException(
        'OUTSIDE_SERVICE_AREA',
        'Pickup is outside our service area',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const vehicleType = dto.vehicle_type ?? DEFAULT_VEHICLE_TYPE;
    const cfg = await this.prisma.fareConfig.findUnique({ where: { id: dto.fare_config_id } });
    if (!cfg || cfg.vehicleType !== vehicleType) {
      throw new AppException(
        'FARE_CONFIG_INVALID',
        'Fare has changed. Please get a new estimate.',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    // Recomputed server-side: the client's numbers are never trusted.
    const route = await this.routing.route(dto.pickup, dto.drop);
    const est = estimate(route.distance_m, route.duration_s, toFareValues(cfg), new Date());

    const rideId = await this.prisma.$transaction(async (tx) => {
      // Serialise per rider so two taps cannot create two rides.
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${riderId}))`;
      const active = await tx.ride.count({
        where: { riderId, status: { in: RIDER_BLOCKING_STATUSES } },
      });
      if (active)
        throw new AppException(
          'ACTIVE_RIDE_EXISTS',
          'You already have an active ride',
          HttpStatus.CONFLICT,
        );

      const [{ id }] = await tx.$queryRaw<{ id: string }[]>`
        INSERT INTO rides (rider_id, status, vehicle_type, payment_method,
                           pickup_point, pickup_address, drop_point, drop_address,
                           est_distance_m, est_duration_s, est_fare_min, est_fare_max,
                           fare_config_id, trip_otp, share_token)
        VALUES (${riderId}::uuid, 'REQUESTED', ${vehicleType}, ${dto.payment_method}::ride_payment,
                ST_GeogFromText(${toWkt(dto.pickup)}), ${dto.pickup.address.trim()},
                ST_GeogFromText(${toWkt(dto.drop)}), ${dto.drop.address.trim()},
                ${route.distance_m}, ${route.duration_s}, ${est.fare_min}, ${est.fare_max},
                ${cfg.id}::uuid, ${randomInt(0, 10_000).toString().padStart(4, '0')},
                ${randomBytes(16).toString('hex')})
        RETURNING id`;
      await this.events.record(tx, {
        rideId: id,
        from: null,
        to: 'REQUESTED',
        actor: 'rider',
        actorId: riderId,
        meta: { fare: est.fare } as Prisma.InputJsonValue,
      });
      return id;
    });

    await this.matching.start(rideId);
    const ride = await this.rides.get(rideId);
    this.publisher.status(ride);
    return presentRide(ride, 'rider');
  }

  async active(riderId: string) {
    const [ride] = await this.rides.findMany(
      { riderId, status: { in: RIDER_OPEN_STATUSES } },
      { take: 1 },
    );
    if (!ride) throw new AppException('NO_ACTIVE_RIDE', 'No active ride', HttpStatus.NOT_FOUND);
    return presentRide(ride, 'rider');
  }

  async get(riderId: string, rideId: string) {
    const ride = await this.rides.find(rideId);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException('Ride not found');
    return presentRide(ride, 'rider');
  }

  cancel(riderId: string, rideId: string, dto: CancelRideDto) {
    return this.cancellation
      .byRider(riderId, rideId, dto.reason)
      .then((r) => presentRide(r, 'rider'));
  }

  /** GET /rides — history, newest first. */
  async list(riderId: string, q: PageQuery): Promise<Page<ReturnType<typeof presentRide>>> {
    const where = { riderId };
    const [rides, total] = await Promise.all([
      this.rides.findMany(where, skipTake(q)),
      this.prisma.ride.count({ where }),
    ]);
    return { data: rides.map((r) => presentRide(r, 'rider')), page: q.page, limit: q.limit, total };
  }

  /** GET /rides/:id/receipt — fare breakdown for a completed or paid ride. */
  async receipt(riderId: string, rideId: string) {
    const ride = await this.rides.find(rideId);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException('Ride not found');
    if (ride.status !== 'COMPLETED' && ride.status !== 'PAID') {
      throw new AppException(
        'RECEIPT_NOT_READY',
        'The receipt is available once the trip is completed',
        HttpStatus.CONFLICT,
      );
    }
    const cfg = ride.fareConfigId
      ? await this.prisma.fareConfig.findUniqueOrThrow({ where: { id: ride.fareConfigId } })
      : await this.fares.current(ride.vehicleType);
    const payment = await this.prisma.payment.findUnique({
      where: { rideId },
      select: { status: true, method: true, paidAt: true },
    });
    return {
      ...buildReceipt(ride, cfg),
      payment_status: payment?.status ?? 'pending',
      paid_with: payment?.method ?? null,
      paid_at: payment?.paidAt ?? null,
    };
  }
}
