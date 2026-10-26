/** Vehicle classes a rider can choose between (D-056). Order is the display order. */
export const VEHICLE_TYPES = ['bike', 'auto', 'mini', 'sedan'] as const;
export type VehicleType = (typeof VEHICLE_TYPES)[number];

/** Passenger seats per class, shown on the rider's confirm screen. */
export const VEHICLE_SEATS: Record<VehicleType, number> = { bike: 1, auto: 3, mini: 4, sedan: 4 };

/** Used when a client sends no vehicle_type (older app builds). */
export const DEFAULT_VEHICLE_TYPE: VehicleType = 'sedan';
