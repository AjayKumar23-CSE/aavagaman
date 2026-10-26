import { Injectable } from '@nestjs/common';
import { CancelActor, Prisma, RideStatus } from '@prisma/client';
import { PrismaService } from '../../common/prisma.service';
import { nextStatus, RideEvent } from './ride-state';
import { RideEventsService } from './ride-events.service';
import { LoadedRide, RideRepository } from './ride.repository';

type Tx = Prisma.TransactionClient;

export interface TransitionArgs {
  event: RideEvent;
  actor: CancelActor;
  actorId?: string | null;
  /** Ownership and precondition checks; runs under the row lock. */
  check?: (ride: LoadedRide) => void | Promise<void>;
  /** Columns to set alongside `status`. */
  data?: (
    ride: LoadedRide,
    to: RideStatus,
    tx: Tx,
  ) => Prisma.RideUncheckedUpdateInput | Promise<Prisma.RideUncheckedUpdateInput>;
  meta?: (ride: LoadedRide, to: RideStatus) => Prisma.InputJsonValue | undefined;
}

/** One place that performs a SPEC §10 transition: lock, validate, update, record ride_events. */
@Injectable()
export class RideTransitionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rides: RideRepository,
    private readonly events: RideEventsService,
  ) {}

  async apply(
    rideId: string,
    args: TransitionArgs,
  ): Promise<{ ride: LoadedRide; before: LoadedRide }> {
    return this.prisma.$transaction(async (tx) => {
      await this.rides.lock(rideId, tx);
      const before = await this.rides.get(rideId, tx);
      await args.check?.(before);
      const to = nextStatus(before.status, args.event, args.actor);
      const data = (await args.data?.(before, to, tx)) ?? {};
      await tx.ride.update({ where: { id: rideId }, data: { ...data, status: to } });
      await this.events.record(tx, {
        rideId,
        from: before.status,
        to,
        actor: args.actor,
        actorId: args.actorId ?? null,
        meta: args.meta?.(before, to),
      });
      return { ride: await this.rides.get(rideId, tx), before };
    });
  }
}
