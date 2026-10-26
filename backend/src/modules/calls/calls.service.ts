import { HttpStatus, Inject, Injectable, Logger, NotFoundException, Optional } from '@nestjs/common';
import type { CallStatus, RideStatus } from '@prisma/client';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { RideRepository } from '../rides/ride.repository';
import { CALL_PROVIDER, CallProvider, CallProviderError, TERMINAL_CALL_STATUSES } from './call.provider';
import { presentCall } from './call.presenter';

/** Rider and driver may call each other while a trip is live (D-058). */
export const CALLABLE_STATUSES: readonly RideStatus[] = ['ACCEPTED', 'ARRIVED', 'STARTED'];

export const isCallable = (status: RideStatus) => CALLABLE_STATUSES.includes(status);

/** True when a recent call by the same caller is still too fresh (abuse guard). */
export function tooSoon(last: { createdAt: Date } | null, now: Date, intervalSeconds: number): boolean {
  if (!last) return false;
  return now.getTime() - last.createdAt.getTime() < intervalSeconds * 1000;
}

@Injectable()
export class CallsService {
  private readonly logger = new Logger(CallsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly rides: RideRepository,
    @Inject(APP_CONFIG) private readonly config: Env,
    @Optional() @Inject(CALL_PROVIDER) private readonly provider: CallProvider | null,
  ) {}

  /** Masked calling is on when a provider is configured. */
  get enabled() {
    return this.provider !== null;
  }

  get displayNumber(): string | null {
    return this.provider?.displayNumber ?? null;
  }

  /** POST /rides/:id/call (rider) and /driver/rides/:id/call (driver). */
  async request(userId: string, role: 'rider' | 'driver', rideId: string) {
    const provider = this.provider;
    if (!provider) {
      throw new AppException('CALLS_UNAVAILABLE', 'In-app calling is not set up', HttpStatus.SERVICE_UNAVAILABLE);
    }
    const ride = await this.rides.find(rideId);
    const mine = ride && (role === 'rider' ? ride.riderId === userId : ride.driver?.userId === userId);
    if (!ride || !mine) throw new NotFoundException('Ride not found');
    if (!isCallable(ride.status) || !ride.driver) {
      throw new AppException('RIDE_NOT_CALLABLE', 'You can call once a driver is on the way', HttpStatus.CONFLICT);
    }
    const caller = role === 'rider' ? ride.rider : ride.driver.user;
    const callee = role === 'rider' ? ride.driver.user : ride.rider;

    const last = await this.prisma.rideCall.findFirst({
      where: { rideId, callerId: caller.id },
      orderBy: { createdAt: 'desc' },
    });
    if (tooSoon(last, new Date(), this.config.CALL_MIN_INTERVAL_SECONDS)) {
      throw new AppException('CALL_TOO_SOON', 'Please wait a moment before calling again', HttpStatus.TOO_MANY_REQUESTS);
    }

    const call = await this.prisma.rideCall.create({
      data: { rideId, callerId: caller.id, calleeId: callee.id, provider: provider.name },
    });
    try {
      const result = await provider.connect({
        from: caller.phone,
        to: callee.phone,
        maxSeconds: this.config.CALL_MAX_SECONDS,
      });
      const updated = await this.prisma.rideCall.update({
        where: { id: call.id },
        data: { providerCallId: result.providerCallId, status: result.status },
      });
      this.logger.log(`call ${call.id} ${role} → ${role === 'rider' ? 'driver' : 'rider'} on ride ${rideId}`);
      return presentCall(updated, provider.displayNumber);
    } catch (e) {
      const reason = (e instanceof CallProviderError ? e.detail : String(e)).slice(0, 300);
      await this.prisma.rideCall.update({
        where: { id: call.id },
        data: { status: 'failed', endedAt: new Date(), failureReason: reason },
      });
      this.logger.warn(`call ${call.id} on ride ${rideId} failed: ${reason}`);
      throw e;
    }
  }

  /** Provider status callback: final outcome and talk time. Unknown ids are ignored. */
  async recordStatus(providerCallId: string, status: CallStatus, durationS?: number): Promise<boolean> {
    const call = await this.prisma.rideCall.findFirst({ where: { providerCallId } });
    if (!call) return false;
    await this.prisma.rideCall.update({
      where: { id: call.id },
      data: {
        status,
        ...(durationS !== undefined ? { durationS } : {}),
        ...(TERMINAL_CALL_STATUSES.includes(status) ? { endedAt: new Date() } : {}),
      },
    });
    return true;
  }

  /** Admin ride detail. */
  async listForRide(rideId: string) {
    const via = this.displayNumber ?? '';
    const calls = await this.prisma.rideCall.findMany({ where: { rideId }, orderBy: { createdAt: 'asc' } });
    return calls.map((c) => presentCall(c, via));
  }
}
