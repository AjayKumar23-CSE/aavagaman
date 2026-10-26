import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { Page, skipTake } from '../../common/pagination';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { LocationService } from '../location/location.service';
import { presentPayment } from '../payments/payment.presenter';
import { CallsService } from '../calls/calls.service';
import { RideTransitionService } from '../rides/ride-transition.service';
import { presentRide } from '../rides/ride.presenter';
import { RidePublisher } from '../rides/ride.publisher';
import { RideRepository } from '../rides/ride.repository';
import { TracksService } from '../rides/tracks.service';
import { TripService } from '../rides/trip.service';
import { AdjustFareDto, ListRidesQuery, ReassignDto } from './dto/admin.dto';

const ADJUSTABLE = ['COMPLETED', 'PAID', 'CANCELLED'] as const;

@Injectable()
export class AdminRidesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly rides: RideRepository,
    private readonly tracks: TracksService,
    private readonly transition: RideTransitionService,
    private readonly publisher: RidePublisher,
    private readonly location: LocationService,
    private readonly trip: TripService,
    private readonly calls: CallsService,
    private readonly audit: AuditService,
  ) {}

  async list(q: ListRidesQuery): Promise<Page<ReturnType<typeof presentRide>>> {
    const where: Prisma.RideWhereInput = {
      status: q.status,
      driverId: q.driver_id,
      riderId: q.rider_id,
      ...(q.from || q.to
        ? {
            requestedAt: {
              gte: q.from ? new Date(q.from) : undefined,
              lt: q.to ? new Date(q.to) : undefined,
            },
          }
        : {}),
    };
    const [rows, total] = await Promise.all([
      this.rides.findMany(where, skipTake(q)),
      this.prisma.ride.count({ where }),
    ]);
    return { data: rows.map((r) => presentRide(r, 'admin')), page: q.page, limit: q.limit, total };
  }

  /** SPEC §7.4: ride + events + track (GeoJSON) + offers + payment. */
  async detail(rideId: string) {
    const ride = await this.rides.find(rideId);
    if (!ride) throw new NotFoundException('Ride not found');
    const [events, offers, payment, track, calls] = await Promise.all([
      this.prisma.rideEvent.findMany({ where: { rideId }, orderBy: { id: 'asc' } }),
      this.prisma.rideOffer.findMany({
        where: { rideId },
        include: { driver: { include: { user: { select: { name: true } } } } },
        orderBy: { offeredAt: 'asc' },
      }),
      this.prisma.payment.findUnique({ where: { rideId } }),
      this.tracks.geojson(rideId),
      this.calls.listForRide(rideId),
    ]);
    return {
      ride: presentRide(ride, 'admin'),
      events: events.map((e) => ({
        id: Number(e.id),
        from_status: e.fromStatus,
        to_status: e.toStatus,
        actor: e.actor,
        actor_id: e.actorId,
        meta: e.meta,
        at: e.createdAt,
      })),
      offers: offers.map((o) => ({
        id: o.id,
        driver_id: o.driverId,
        driver_name: o.driver.user.name,
        distance_to_pickup_m: o.distanceToPickupM,
        offered_at: o.offeredAt,
        responded_at: o.respondedAt,
        response: o.response,
      })),
      payment: payment ? presentPayment(payment) : null,
      track,
      calls,
    };
  }

  /** SPEC §7.4 reassign (ACCEPTED/ARRIVED only) to an online, idle, approved driver. */
  async reassign(adminId: string, rideId: string, dto: ReassignDto) {
    const target = await this.prisma.driver.findUnique({
      where: { userId: dto.driver_id },
      include: { user: true, vehicles: { where: { active: true } } },
    });
    if (
      !target ||
      target.verificationStatus !== 'approved' ||
      target.user.status !== 'active' ||
      !target.vehicles.length
    ) {
      throw new AppException(
        'DRIVER_NOT_ELIGIBLE',
        'That driver is not approved or has no active vehicle',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    if ((await this.location.getState(dto.driver_id)) !== 'idle') {
      throw new AppException(
        'DRIVER_NOT_IDLE',
        'That driver is not online and idle',
        HttpStatus.CONFLICT,
      );
    }
    const { ride, before } = await this.transition.apply(rideId, {
      event: 'reassign',
      actor: 'admin',
      actorId: adminId,
      check: (r) => {
        if (r.driverId === dto.driver_id)
          throw new AppException(
            'SAME_DRIVER',
            'The ride is already with that driver',
            HttpStatus.CONFLICT,
          );
      },
      data: async (_r, _to, tx) => {
        await tx.rideOffer.create({
          data: { rideId, driverId: dto.driver_id, response: 'accepted', respondedAt: new Date() },
        });
        return {
          driverId: dto.driver_id,
          vehicleId: target.vehicles[0].id,
          acceptedAt: new Date(),
          arrivedAt: null,
          otpAttempts: 0,
        };
      },
      meta: () => ({ previous_driver_id: null, reassigned_by: adminId }),
    });
    if (before.driverId) await this.location.releaseFromRide(before.driverId, rideId);
    await this.location.setState(dto.driver_id, 'on_trip');
    await this.redis
      .multi()
      .set(K.driverRide(dto.driver_id), rideId)
      .sadd(K.offeredSet(rideId), dto.driver_id)
      .exec();
    await this.audit.log({
      actorId: adminId,
      action: 'ride.reassign',
      entity: 'ride',
      entityId: rideId,
      before: { driver_id: before.driverId, status: before.status },
      after: { driver_id: dto.driver_id, status: ride.status },
    });
    this.publisher.status(ride, { previousDriverId: before.driverId });
    return presentRide(ride, 'admin');
  }

  /** SPEC §7.4 adjust-fare (logged). Pending online payments pick up the new amount. */
  async adjustFare(adminId: string, rideId: string, dto: AdjustFareDto) {
    const ride = await this.rides.find(rideId);
    if (!ride) throw new NotFoundException('Ride not found');
    if (!(ADJUSTABLE as readonly string[]).includes(ride.status)) {
      throw new AppException(
        'FARE_NOT_ADJUSTABLE',
        `Fare can be adjusted on ${ADJUSTABLE.join(', ')} rides only`,
        HttpStatus.CONFLICT,
      );
    }
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.ride.update({
        where: { id: rideId },
        data: { finalFare: new Prisma.Decimal(dto.final_fare) },
      });
      const payment = await tx.payment.findUnique({ where: { rideId } });
      if (payment && payment.status !== 'paid') {
        await tx.payment.update({
          where: { rideId },
          data: { amount: new Prisma.Decimal(dto.final_fare + Number(ride.cancellationFee ?? 0)) },
        });
      }
      await tx.rideEvent.create({
        data: {
          rideId,
          fromStatus: ride.status,
          toStatus: ride.status,
          actor: 'admin',
          actorId: adminId,
          meta: {
            type: 'fare_adjusted',
            from: Number(ride.finalFare ?? 0),
            to: dto.final_fare,
            reason: dto.reason,
          },
        },
      });
      return this.rides.get(rideId, tx);
    });
    await this.audit.log({
      actorId: adminId,
      action: 'ride.adjust_fare',
      entity: 'ride',
      entityId: rideId,
      before: { final_fare: Number(ride.finalFare ?? 0) },
      after: { final_fare: dto.final_fare, reason: dto.reason },
    });
    this.publisher.status(updated);
    return presentRide(updated, 'admin');
  }

  async markCash(adminId: string, rideId: string) {
    const ride = await this.trip.cashCollected(rideId, 'admin', adminId);
    await this.audit.log({
      actorId: adminId,
      action: 'ride.mark_cash',
      entity: 'ride',
      entityId: rideId,
      after: {
        status: ride.status,
        amount: Number(ride.finalFare ?? 0) + Number(ride.cancellationFee ?? 0),
      },
    });
    return presentRide(ride, 'admin');
  }
}
