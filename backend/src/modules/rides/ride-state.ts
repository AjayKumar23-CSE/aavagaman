import { HttpStatus } from '@nestjs/common';
import type { CancelActor, RideStatus } from '@prisma/client';
import { AppException } from '../../common/app.exception';

export type RideEvent =
  | 'accept'
  | 'no_driver'
  | 'cancel'
  | 'arrived'
  | 'reassign'
  | 'start'
  | 'complete'
  | 'pay'
  | 'driver_cancel_requeue';

interface Rule {
  from: RideStatus;
  event: RideEvent;
  to: RideStatus;
  actors: CancelActor[];
}

/**
 * SPEC §10. `driver_cancel_requeue` is the "back to REQUESTED on driver cancel"
 * branch of ACCEPTED/cancel (and ARRIVED before the 300 s no-show window, §9.5).
 * Payment is performed by the system for webhooks (§10 "webhook").
 */
export const RIDE_TRANSITIONS: readonly Rule[] = [
  { from: 'REQUESTED', event: 'accept', to: 'ACCEPTED', actors: ['driver'] },
  { from: 'REQUESTED', event: 'no_driver', to: 'NO_DRIVER', actors: ['system'] },
  { from: 'REQUESTED', event: 'cancel', to: 'CANCELLED', actors: ['rider', 'admin'] },
  { from: 'ACCEPTED', event: 'arrived', to: 'ARRIVED', actors: ['driver'] },
  { from: 'ACCEPTED', event: 'cancel', to: 'CANCELLED', actors: ['rider', 'driver', 'admin'] },
  { from: 'ACCEPTED', event: 'driver_cancel_requeue', to: 'REQUESTED', actors: ['driver'] },
  { from: 'ACCEPTED', event: 'reassign', to: 'ACCEPTED', actors: ['admin'] },
  { from: 'ARRIVED', event: 'start', to: 'STARTED', actors: ['driver'] },
  { from: 'ARRIVED', event: 'cancel', to: 'CANCELLED', actors: ['rider', 'driver', 'admin'] },
  { from: 'ARRIVED', event: 'driver_cancel_requeue', to: 'REQUESTED', actors: ['driver'] },
  { from: 'ARRIVED', event: 'reassign', to: 'ACCEPTED', actors: ['admin'] },
  { from: 'STARTED', event: 'complete', to: 'COMPLETED', actors: ['driver'] },
  { from: 'STARTED', event: 'cancel', to: 'CANCELLED', actors: ['admin'] },
  { from: 'COMPLETED', event: 'pay', to: 'PAID', actors: ['driver', 'admin', 'system', 'rider'] },
];

/** Returns the target status or throws 409 INVALID_TRANSITION. */
export function nextStatus(from: RideStatus, event: RideEvent, actor: CancelActor): RideStatus {
  const rule = RIDE_TRANSITIONS.find((r) => r.from === from && r.event === event);
  if (!rule || !rule.actors.includes(actor)) {
    throw new AppException(
      'INVALID_TRANSITION',
      `Cannot ${event.replace(/_/g, ' ')} a ${from} ride as ${actor}`,
      HttpStatus.CONFLICT,
    );
  }
  return rule.to;
}

export const ACTIVE_STATUSES: readonly RideStatus[] = [
  'REQUESTED',
  'ACCEPTED',
  'ARRIVED',
  'STARTED',
];
/** A driver is assigned and the trip is not over. */
export const DRIVER_ACTIVE_STATUSES: readonly RideStatus[] = ['ACCEPTED', 'ARRIVED', 'STARTED'];
