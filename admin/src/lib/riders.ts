import { api, postJson, qs } from './api';
import type { Paginated } from './drivers';

export interface Rider {
  id: string;
  phone: string;
  name: string | null;
  email: string | null;
  role: string;
  status: 'active' | 'blocked';
  rating_avg: number;
  rating_count: number;
  created_at: string;
  rides_count: number;
}

export function listRiders(p: { q?: string; page: number; limit: number }): Promise<Paginated<Rider>> {
  return api(`/v1/admin/riders${qs(p)}`);
}

export function blockRider(id: string, reason: string): Promise<Rider> {
  return postJson(`/v1/admin/riders/${encodeURIComponent(id)}/block`, { reason });
}

export function unblockRider(id: string, note?: string): Promise<Rider> {
  return postJson(`/v1/admin/riders/${encodeURIComponent(id)}/unblock`, note ? { note } : {});
}
