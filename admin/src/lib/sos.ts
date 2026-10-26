import { api, postJson, qs } from './api';
import type { Paginated } from './drivers';

export interface SosAlert {
  id: string;
  ride_id: string | null;
  user_id: string;
  user_name: string | null;
  user_phone: string;
  user_role: 'rider' | 'driver' | string;
  lat: number | null;
  lng: number | null;
  acknowledged_by: string | null;
  acknowledged_at: string | null;
  created_at: string;
}

export function listSos(p: { acknowledged?: boolean; page: number; limit: number }): Promise<Paginated<SosAlert>> {
  return api(`/v1/admin/sos${qs(p)}`);
}

export function ackSos(id: string): Promise<Pick<SosAlert, 'id' | 'ride_id' | 'user_id' | 'acknowledged_by' | 'acknowledged_at' | 'created_at'>> {
  return postJson(`/v1/admin/sos/${encodeURIComponent(id)}/ack`);
}

export function mapsLink(lat: number, lng: number): string {
  return `https://maps.google.com/?q=${lat},${lng}`;
}
