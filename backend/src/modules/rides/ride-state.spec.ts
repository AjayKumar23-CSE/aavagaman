import type { CancelActor, RideStatus } from '@prisma/client';
import { nextStatus, RIDE_TRANSITIONS, RideEvent } from './ride-state';

describe('ride state machine (SPEC §10)', () => {
  it.each(
    RIDE_TRANSITIONS.flatMap((r) => r.actors.map((a) => [r.from, r.event, a, r.to] as const)),
  )('allows %s --%s--> by %s = %s', (from, event, actor, to) => {
    expect(nextStatus(from, event, actor)).toBe(to);
  });

  const forbidden: [RideStatus, RideEvent, CancelActor][] = [
    ['REQUESTED', 'accept', 'rider'],
    ['REQUESTED', 'cancel', 'driver'],
    ['REQUESTED', 'start', 'driver'],
    ['REQUESTED', 'no_driver', 'rider'],
    ['ACCEPTED', 'start', 'driver'],
    ['ACCEPTED', 'complete', 'driver'],
    ['ACCEPTED', 'reassign', 'driver'],
    ['ARRIVED', 'arrived', 'driver'],
    ['STARTED', 'cancel', 'rider'],
    ['STARTED', 'cancel', 'driver'],
    ['STARTED', 'arrived', 'driver'],
    ['COMPLETED', 'cancel', 'admin'],
    ['COMPLETED', 'complete', 'driver'],
    ['PAID', 'pay', 'driver'],
    ['CANCELLED', 'accept', 'driver'],
    ['CANCELLED', 'cancel', 'admin'],
    ['NO_DRIVER', 'accept', 'driver'],
    ['NO_DRIVER', 'cancel', 'rider'],
  ];

  it.each(forbidden)(
    'rejects %s --%s--> by %s with 409 INVALID_TRANSITION',
    (from, event, actor) => {
      expect(() => nextStatus(from, event, actor)).toThrow(
        expect.objectContaining({ code: 'INVALID_TRANSITION', status: 409 }),
      );
    },
  );
});
