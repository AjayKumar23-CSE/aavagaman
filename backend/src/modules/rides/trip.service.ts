import { timingSafeEqual } from 'node:crypto';
import { InjectQueue } from '@nestjs/bullmq';
import { HttpStatus, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { haversineM, LatLng } from '../../common/geo/geo';
import { PrismaService } from '../../common/prisma.service';
import { RedisService } from '../../common/redis.service';
import { estimate, finalFare } from '../fare/fare.engine';
import { FareService, toFareValues } from '../fare/fare.service';
import { LocationService } from '../location/location.service';
import { PaymentsService } from '../payments/payments.service';
import { JOB_OTP_SMS, SYSTEM_QUEUE } from '../matching/system.processor';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { RoutingService } from '../routing/routing.service';
import { RideTransitionService } from './ride-transition.service';
import { RideEventsService } from './ride-events.service';
import { RidePublisher } from './ride.publisher';
import { LoadedRide, RideRepository } from './ride.repository';
import { acceptedTrackPoints, MIN_TRACK_POINTS, trackDistanceM } from './tracks';
import { TrackFix, TracksService } from './tracks.service';

export const otpSmsJobId = (rideId: string) => `otpsms_${rideId}`;

/** Constant-time 4-digit compare (SPEC §9.6). */
export function otpMatches(given: string, expected: string): boolean {
  const a = Buffer.from(given.padEnd(4, ' ').slice(0, 4));
  const b = Buffer.from(expected.padEnd(4, ' ').slice(0, 4));
  return timingSafeEqual(a, b) && given.length === expected.length;
}

@Injectable()
export class TripService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly rides: RideRepository,
    private readonly transition: RideTransitionService,
    private readonly events: RideEventsService,
    private readonly publisher: RidePublisher,
    private readonly tracks: TracksService,
    private readonly routing: RoutingService,
    private readonly fares: FareService,
    private readonly location: LocationService,
    private readonly payments: PaymentsService,
    private readonly rt: RealtimeEmitter,
    @InjectQueue(SYSTEM_QUEUE) private readonly systemQueue: Queue,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  private own(driverId: string) {
    return (ride: LoadedRide) => {
      if (ride.driverId !== driverId) throw new NotFoundException('Ride not found');
    };
  }

  /** POST /driver/rides/:id/arrived — 422 when farther than ARRIVAL_RADIUS_M from the pickup. */
  async arrived(driverId: string, rideId: string, fix: TrackFix) {
    const { ride } = await this.transition.apply(rideId, {
      event: 'arrived',
      actor: 'driver',
      actorId: driverId,
      check: (r) => {
        this.own(driverId)(r);
        const d = Math.round(
          haversineM(fix, { lat: r.coords.pickup_lat, lng: r.coords.pickup_lng }),
        );
        if (d > this.config.ARRIVAL_RADIUS_M) {
          throw new AppException(
            'TOO_FAR_FROM_PICKUP',
            `You are ${d} m from the pickup; get within ${this.config.ARRIVAL_RADIUS_M} m`,
            HttpStatus.UNPROCESSABLE_ENTITY,
          );
        }
      },
      data: () => ({ arrivedAt: new Date() }),
      meta: () => ({ lat: fix.lat, lng: fix.lng }),
    });
    await this.tracks.record(rideId, fix);
    // SPEC §9.6: OTP by SMS only if the rider's app stays offline after ARRIVED.
    await this.systemQueue.add(
      JOB_OTP_SMS,
      { ride_id: rideId },
      {
        jobId: otpSmsJobId(rideId),
        delay: this.config.OTP_SMS_FALLBACK_SECONDS * 1000,
        removeOnComplete: true,
        removeOnFail: 50,
      },
    );
    this.publisher.status(ride);
    return ride;
  }

  /** POST /driver/rides/:id/start — 401 on a wrong OTP; locked after OTP_START_MAX_ATTEMPTS. */
  async start(driverId: string, rideId: string, dto: TrackFix & { otp: string }) {
    const max = this.config.OTP_START_MAX_ATTEMPTS;
    const outcome = await this.prisma.$transaction(async (tx) => {
      await this.rides.lock(rideId, tx);
      const ride = await this.rides.get(rideId, tx);
      this.own(driverId)(ride);
      if (ride.status !== 'ARRIVED') {
        throw new AppException(
          'INVALID_TRANSITION',
          `Cannot start a ${ride.status} ride`,
          HttpStatus.CONFLICT,
        );
      }
      if (ride.otpAttempts >= max) return { kind: 'locked' as const, attempts: ride.otpAttempts };
      if (!otpMatches(dto.otp, ride.tripOtp)) {
        const attempts = ride.otpAttempts + 1;
        await tx.ride.update({ where: { id: rideId }, data: { otpAttempts: attempts } });
        const flagged = attempts >= max;
        await this.events.record(tx, {
          rideId,
          from: 'ARRIVED',
          to: 'ARRIVED',
          actor: 'driver',
          actorId: driverId,
          meta: { type: 'otp_failed', attempts, flagged },
        });
        return { kind: 'wrong' as const, attempts, flagged };
      }
      const now = new Date();
      await tx.ride.update({ where: { id: rideId }, data: { status: 'STARTED', startedAt: now } });
      await this.events.record(tx, {
        rideId,
        from: 'ARRIVED',
        to: 'STARTED',
        actor: 'driver',
        actorId: driverId,
      });
      return { kind: 'started' as const, ride: await this.rides.get(rideId, tx) };
    });

    if (outcome.kind === 'locked') {
      throw new AppException(
        'OTP_LOCKED',
        'Too many wrong OTP attempts. Ask the rider to cancel, or cancel the ride.',
        HttpStatus.UNAUTHORIZED,
      );
    }
    if (outcome.kind === 'wrong') {
      if (outcome.flagged) {
        this.publisher.adminAlert('otp_failed', {
          ride_id: rideId,
          driver_id: driverId,
          attempts: outcome.attempts,
        });
      }
      const left = max - outcome.attempts;
      throw new AppException(
        'OTP_INVALID',
        left > 0
          ? `Wrong OTP. ${left} attempt${left === 1 ? '' : 's'} left.`
          : 'Wrong OTP. No attempts left.',
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.systemQueue.remove(otpSmsJobId(rideId)).catch(() => 0);
    await this.tracks.record(rideId, dto);
    this.publisher.status(outcome.ride);
    return outcome.ride;
  }

  /** Actual distance per SPEC §9.3, with the OSRM fallback when the track is too thin. */
  private async actualDistance(
    ride: LoadedRide,
    startedAt: Date,
    endFix: LatLng,
    endAt: Date,
  ): Promise<number> {
    const points = await this.tracks.between(ride.id, startedAt, endAt);
    points.push({ ...endFix, recordedAt: endAt, accuracyM: null });
    const accepted = acceptedTrackPoints(points);
    if (accepted.length >= MIN_TRACK_POINTS) return trackDistanceM(accepted);
    const from = accepted[0] ?? { lat: ride.coords.pickup_lat, lng: ride.coords.pickup_lng };
    try {
      return (await this.routing.route(from, endFix)).distance_m;
    } catch {
      return Math.round(haversineM(from, endFix));
    }
  }

  /** POST /driver/rides/:id/complete — final fare, pending cancellation fees as a line item. */
  async complete(driverId: string, rideId: string, fix: TrackFix) {
    const current = await this.rides.get(rideId);
    this.own(driverId)(current);
    if (current.status !== 'STARTED' || !current.startedAt) {
      throw new AppException(
        'INVALID_TRANSITION',
        `Cannot complete a ${current.status} ride`,
        HttpStatus.CONFLICT,
      );
    }
    const now = new Date();
    const startedAt = current.startedAt;
    const cfg = current.fareConfigId
      ? await this.prisma.fareConfig.findUniqueOrThrow({ where: { id: current.fareConfigId } })
      : await this.fares.current(current.vehicleType);
    const values = toFareValues(cfg);
    const distanceM = await this.actualDistance(current, startedAt, fix, now);
    const durationS = Math.max(0, Math.round((now.getTime() - startedAt.getTime()) / 1000));
    const est = estimate(
      current.estDistanceM ?? 0,
      current.estDurationS ?? 0,
      values,
      current.requestedAt ?? startedAt,
    );
    // No destination changes in the MVP, so the 125% cap always applies.
    const fare = finalFare(distanceM, durationS, values, est, false, startedAt);

    const { ride } = await this.transition.apply(rideId, {
      event: 'complete',
      actor: 'driver',
      actorId: driverId,
      check: this.own(driverId),
      data: async (r, _to, tx) => {
        // SPEC §9.5: fees from earlier cancellations ride along on the next completed trip.
        const pending = await tx.ride.findMany({
          where: {
            riderId: r.riderId,
            status: 'CANCELLED',
            cancellationFee: { gt: 0 },
            feeAppliedToRideId: null,
          },
          select: { id: true, cancellationFee: true },
        });
        const fee = pending.reduce((sum, p) => sum + Number(p.cancellationFee ?? 0), 0);
        if (pending.length) {
          await tx.ride.updateMany({
            where: { id: { in: pending.map((p) => p.id) } },
            data: { feeAppliedToRideId: rideId },
          });
        }
        return {
          completedAt: now,
          actualDistanceM: distanceM,
          actualDurationS: durationS,
          finalFare: new Prisma.Decimal(fare),
          cancellationFee: new Prisma.Decimal(fee),
        };
      },
      meta: () => ({ estimate_fare: est.fare, cap: est.fare * 1.25, track_based: true }),
    });
    await this.tracks.record(rideId, fix, now);
    this.publisher.status(ride);
    return ride;
  }

  /**
   * Cash collected (SPEC §15): by the driver (`POST /driver/rides/:id/cash-collected`) or an
   * admin (`POST /admin/rides/:id/mark-cash`) → payment paid, ride PAID, driver idle.
   */
  async cashCollected(rideId: string, actor: 'driver' | 'admin', actorId: string) {
    const { ride } = await this.transition.apply(rideId, {
      event: 'pay',
      actor,
      actorId,
      check: async (r) => {
        if (actor === 'driver') this.own(actorId)(r);
        await this.payments.assertCashAllowed(rideId);
      },
      data: async (r, _to, tx) => {
        const amount = Number(r.finalFare ?? 0) + Number(r.cancellationFee ?? 0);
        const now = new Date();
        await tx.payment.upsert({
          where: { rideId },
          create: { rideId, method: 'cash', amount, status: 'paid', paidAt: now },
          update: { method: 'cash', amount, status: 'paid', paidAt: now },
        });
        return { paidAt: now };
      },
    });
    if (ride.driverId) await this.location.releaseFromRide(ride.driverId, rideId);
    const payload = { ride_id: rideId, status: 'paid', method: 'cash' };
    this.rt.toUser(ride.riderId, 'payment:status', payload);
    if (ride.driverId) this.rt.toUser(ride.driverId, 'payment:status', payload);
    this.publisher.status(ride);
    return ride;
  }
}
