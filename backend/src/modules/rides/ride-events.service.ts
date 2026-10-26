import { Injectable } from '@nestjs/common';
import { CancelActor, Prisma, RideStatus } from '@prisma/client';

/** Appends to ride_events (SPEC §10: every transition is recorded). */
@Injectable()
export class RideEventsService {
  record(
    db: Prisma.TransactionClient,
    e: {
      rideId: string;
      from: RideStatus | null;
      to: RideStatus;
      actor: CancelActor;
      actorId?: string | null;
      meta?: Prisma.InputJsonValue;
    },
  ) {
    return db.rideEvent.create({
      data: {
        rideId: e.rideId,
        fromStatus: e.from,
        toStatus: e.to,
        actor: e.actor,
        actorId: e.actorId ?? null,
        meta: e.meta,
      },
    });
  }
}
