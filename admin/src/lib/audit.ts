import { api, qs } from './api';
import type { Paginated } from './drivers';

export interface AuditEntry {
  id: number;
  actor_id: string | null;
  actor_name: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  before: unknown;
  after: unknown;
  at: string;
}

/** Entities the backend writes to the audit log (used as filter suggestions; free text is allowed). */
export const AUDIT_ENTITIES = [
  'driver',
  'driver_document',
  'ride',
  'user',
  'fare_config',
  'service_area',
  'sos_alert',
  'driver_settlement',
];

export function listAudit(p: {
  entity?: string;
  entity_id?: string;
  actor_id?: string;
  page: number;
  limit: number;
}): Promise<Paginated<AuditEntry>> {
  return api(`/v1/admin/audit${qs(p)}`);
}
