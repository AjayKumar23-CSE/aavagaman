import type { CancelActor, RideStatus } from '@prisma/client';

export interface CancellationInput {
  status: RideStatus;
  acceptedAt: Date | null;
  arrivedAt: Date | null;
}

export interface CancellationRules {
  cancellationFee: number;
  freeCancelWindowS: number;
  noShowWaitS: number;
}

export interface CancellationOutcome {
  /** CANCELLED, or REQUESTED when a driver cancel re-queues the ride (SPEC §9.5). */
  to: 'CANCELLED' | 'REQUESTED';
  /** Fee charged to the rider on this ride. */
  fee: number;
  /** Counts towards the driver's daily cancellation limit. */
  countsAgainstDriver: boolean;
  /** No-show: driver cancelled after waiting at the pickup. */
  noShow: boolean;
}

/** SPEC §9.5 cancellation table. Throws nothing: invalid states are rejected by the state machine. */
export function cancellationOutcome(
  ride: CancellationInput,
  actor: CancelActor,
  now: Date,
  rules: CancellationRules,
): CancellationOutcome {
  const none: CancellationOutcome = {
    to: 'CANCELLED',
    fee: 0,
    countsAgainstDriver: false,
    noShow: false,
  };
  if (actor === 'admin' || actor === 'system') return none;

  if (actor === 'rider') {
    if (ride.status === 'REQUESTED') return none;
    if (ride.status === 'ACCEPTED' && ride.acceptedAt) {
      const sinceAccept = (now.getTime() - ride.acceptedAt.getTime()) / 1000;
      return sinceAccept <= rules.freeCancelWindowS
        ? none
        : { ...none, fee: rules.cancellationFee };
    }
    // ARRIVED (or ACCEPTED without a timestamp, which should not happen)
    return { ...none, fee: rules.cancellationFee };
  }

  // driver
  if (ride.status === 'ARRIVED' && ride.arrivedAt) {
    const waited = (now.getTime() - ride.arrivedAt.getTime()) / 1000;
    if (waited >= rules.noShowWaitS) {
      return {
        to: 'CANCELLED',
        fee: rules.cancellationFee,
        countsAgainstDriver: false,
        noShow: true,
      };
    }
  }
  return { to: 'REQUESTED', fee: 0, countsAgainstDriver: true, noShow: false };
}
