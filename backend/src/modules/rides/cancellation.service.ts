import { HttpStatus, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, RideStatus } from '@prisma/client';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { todayIST } from '../drivers/driver-rules';
import { FareService } from '../fare/fare.service';
import { LocationService } from '../location/location.service';
import { MatchingService } from '../matching/matching.service';
import { SYSTEM_QUEUE } from '../matching/system.processor';
import { PushService } from '../notifications/push.service';
import { cancellationOutcome, CancellationRules } from './cancellation.rules';
import { RideTransitionService } from './ride-transition.service';
import { RidePublisher } from './ride.publisher';
import { LoadedRide, RideRepository } from './ride.repository';
import { otpSmsJobId } from './trip.service';

const RIDER_CANCELLABLE: RideStatus[] = ['REQUESTED', 'ACCEPTED', 'ARRIVED'];

@Injectable()
export class CancellationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly rides: RideRepository,
    private readonly transition: RideTransitionService,
    private readonly publisher: RidePublisher,
    private readonly matching: MatchingService,
    private readonly location: LocationService,
    private readonly fares: FareService,
    private readonly push: PushService,
    private readonly audit: AuditService,
    @InjectQueue(SYSTEM_QUEUE) private readonly systemQueue: Queue,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  private async rules(ride: LoadedRide): Promise<CancellationRules> {
    const cfg = ride.fareConfigId
      ? await this.prisma.fareConfig.findUniqueOrThrow({ where: { id: ride.fareConfigId } })
      : await this.fares.current(ride.vehicleType);
    return {
      cancellationFee: Number(cfg.cancellationFee),
      freeCancelWindowS: this.config.FREE_CANCEL_WINDOW_SECONDS,
      noShowWaitS: this.config.NO_SHOW_WAIT_SECONDS,
    };
  }

  /** Housekeeping after a ride leaves a driver: jobs, Redis state, matching. */
  private async afterLeaving(before: LoadedRide, driverId: string | null) {
    if (before.status === 'REQUESTED') await this.matching.stop(before.id);
    await this.systemQueue.remove(otpSmsJobId(before.id)).catch(() => 0);
    if (driverId) await this.location.releaseFromRide(driverId, before.id);
  }

  async byRider(riderId: string, rideId: string, reason?: string) {
    const current = await this.rides.get(rideId);
    if (current.riderId !== riderId) throw new NotFoundException('Ride not found');
    if (!RIDER_CANCELLABLE.includes(current.status)) {
      throw new AppException(
        'RIDE_NOT_CANCELLABLE',
        'This ride can no longer be cancelled',
        HttpStatus.CONFLICT,
      );
    }
    const rules = await this.rules(current);
    const { ride, before } = await this.transition.apply(rideId, {
      event: 'cancel',
      actor: 'rider',
      actorId: riderId,
      check: (r) => {
        if (r.riderId !== riderId) throw new NotFoundException('Ride not found');
      },
      data: (r) => {
        const o = cancellationOutcome(r, 'rider', new Date(), rules);
        return {
          cancelledBy: 'rider',
          cancelReason: reason ?? null,
          cancelledAt: new Date(),
          cancellationFee: new Prisma.Decimal(o.fee),
        };
      },
      meta: () => ({ reason: reason ?? null }),
    });
    await this.afterLeaving(before, before.driverId);
    this.publisher.status(ride);
    return ride;
  }

  /** SPEC §9.5 driver rows: re-queue (counted) or no-show (fee to rider, not counted). */
  async byDriver(driverId: string, rideId: string, reason: string) {
    const current = await this.rides.get(rideId);
    if (current.driverId !== driverId) throw new NotFoundException('Ride not found');
    const rules = await this.rules(current);
    const outcome = cancellationOutcome(current, 'driver', new Date(), rules);

    let suspended = false;
    const { ride, before } = await this.transition.apply(rideId, {
      event: outcome.to === 'REQUESTED' ? 'driver_cancel_requeue' : 'cancel',
      actor: 'driver',
      actorId: driverId,
      check: (r) => {
        if (r.driverId !== driverId) throw new NotFoundException('Ride not found');
      },
      data: async (_r, _to, tx) => {
        if (outcome.countsAgainstDriver) suspended = await this.countCancellation(tx, driverId);
        if (outcome.to === 'REQUESTED') {
          return {
            driverId: null,
            vehicleId: null,
            acceptedAt: null,
            arrivedAt: null,
            otpAttempts: 0,
          };
        }
        return {
          cancelledBy: 'driver',
          cancelReason: reason,
          cancelledAt: new Date(),
          cancellationFee: new Prisma.Decimal(outcome.fee),
        };
      },
      meta: () => ({
        reason,
        previous_driver_id: driverId,
        no_show: outcome.noShow,
        counted: outcome.countsAgainstDriver,
      }),
    });

    await this.afterLeaving(before, driverId);
    if (outcome.to === 'REQUESTED') {
      // Matching restarts with this driver excluded (SPEC §9.5).
      await this.redis
        .multi()
        .sadd(K.offeredSet(rideId), driverId)
        .expire(K.offeredSet(rideId), 600)
        .exec();
      await this.matching.start(rideId, { keepOffered: true });
    }
    if (suspended) {
      await this.location.goOffline(driverId);
      void this.push.toUser(driverId, {
        title: 'Account paused',
        body: 'Account paused, contact support.',
        data: { type: 'driver_status', status: 'suspended' },
      });
      this.publisher.adminAlert('driver_suspended', {
        driver_id: driverId,
        ride_id: rideId,
        reason: 'cancellations',
      });
    }
    this.publisher.status(ride, { previousDriverId: driverId });
    return ride;
  }

  /** Daily counter with IST reset; returns true when the driver just got suspended. */
  private async countCancellation(
    tx: Prisma.TransactionClient,
    driverId: string,
  ): Promise<boolean> {
    const d = await tx.driver.findUniqueOrThrow({ where: { userId: driverId } });
    const today = todayIST();
    const sameDay = d.cancelCountResetAt?.getTime() === today.getTime();
    const count = (sameDay ? (d.cancelCountToday ?? 0) : 0) + 1;
    const suspend =
      count >= this.config.DRIVER_CANCEL_SUSPEND_AT && d.verificationStatus === 'approved';
    await tx.driver.update({
      where: { userId: driverId },
      data: {
        cancelCountToday: count,
        cancelCountResetAt: today,
        ...(suspend
          ? {
              verificationStatus: 'suspended',
              reviewerNote: `Auto-suspended: ${count} cancellations in a day`,
            }
          : {}),
      },
    });
    return suspend;
  }

  /** Admin cancel: any non-terminal status, reason mandatory, no fee, audited (SPEC §9.5, §10). */
  async byAdmin(adminId: string, rideId: string, reason: string) {
    const { ride, before } = await this.transition.apply(rideId, {
      event: 'cancel',
      actor: 'admin',
      actorId: adminId,
      data: () => ({
        cancelledBy: 'admin',
        cancelReason: reason,
        cancelledAt: new Date(),
        cancellationFee: new Prisma.Decimal(0),
      }),
      meta: () => ({ reason }),
    });
    await this.afterLeaving(before, before.driverId);
    await this.audit.log({
      actorId: adminId,
      action: 'ride.cancel',
      entity: 'ride',
      entityId: rideId,
      before: { status: before.status, driver_id: before.driverId },
      after: { status: ride.status, reason },
    });
    this.publisher.status(ride);
    return ride;
  }
}
