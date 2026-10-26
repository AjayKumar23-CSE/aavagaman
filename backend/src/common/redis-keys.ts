/** Redis key layout (SPEC §6). */
export const K = {
  geo: 'drivers:geo',
  hb: (driverId: string) => `driver:${driverId}:hb`,
  state: (driverId: string) => `driver:${driverId}:state`,
  loc: (driverId: string) => `driver:${driverId}:loc`,
  /** Vehicle type of the driver's active vehicle, cached at go-online. */
  vehicleType: (driverId: string) => `driver:${driverId}:vt`,
  /** Rides the driver holds open offers for (mirrors ride:{id}:offers; D-055). */
  driverOffers: (driverId: string) => `driver:${driverId}:offers`,
  /** Active ride of an on_trip driver, for fast location fan-out. */
  driverRide: (driverId: string) => `driver:${driverId}:ride`,
  /** Open offers of the current round: driver_id → expires_at (D-055). */
  offers: (rideId: string) => `ride:${rideId}:offers`,
  offeredSet: (rideId: string) => `ride:${rideId}:offered_set`,
  /** Matching parameters: deadline, radius, attempt, current job id. */
  match: (rideId: string) => `ride:${rideId}:match`,
  eta: (rideId: string) => `ride:${rideId}:eta`,
  /** Set once the "driver is nearby" push went out (SPEC §14). */
  nearbyPushed: (rideId: string) => `ride:${rideId}:nearby_pushed`,
  wsUser: (userId: string) => `ws:user:${userId}`,
} as const;

/** `offered` = holds at least one open offer; it never blocks further offers (D-055). */
export type DriverState = 'idle' | 'offered' | 'on_trip' | 'offline';
