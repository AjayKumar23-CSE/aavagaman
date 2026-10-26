import { api, postJson } from './api';

export interface FareConfig {
  id: string;
  vehicle_type: string;
  base_fare: number;
  per_km: number;
  per_min: number;
  min_fare: number;
  cancellation_fee: number;
  night_multiplier: number;
  night_enabled: boolean;
  commission_pct: number;
  gst_pct: number;
  effective_from: string;
  created_by: string | null;
}

export interface FareConfigList {
  /** Sedan's current version (older shape). */
  current_id: string | null;
  /** Current version id per vehicle type (D-056). */
  current_ids: Record<string, string>;
  vehicle_types: readonly string[];
  /** Newest effective_from first. */
  data: FareConfig[];
}

export interface FareConfigInput {
  vehicle_type?: string;
  base_fare: number;
  per_km: number;
  per_min: number;
  min_fare: number;
  cancellation_fee?: number;
  night_multiplier?: number;
  night_enabled?: boolean;
  commission_pct?: number;
  gst_pct?: number;
  /** ISO instant; defaults to now on the server. */
  effective_from?: string;
}

export interface FarePreview {
  fare: number;
  fare_min: number;
  fare_max: number;
  /** Final-fare cap (estimate × 1.25, SPEC §9.3). */
  cap: number;
}

export function listFareConfigs(): Promise<FareConfigList> {
  return api('/v1/admin/fare-config');
}

export function createFareConfig(body: FareConfigInput): Promise<FareConfig> {
  return postJson('/v1/admin/fare-config', body);
}

export function previewFare(body: FareConfigInput & { distance_m: number; duration_s: number; at?: string }): Promise<FarePreview> {
  return postJson('/v1/admin/fare-config/preview', body);
}
