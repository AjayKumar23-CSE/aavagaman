import { api, postJson, qs } from './api';

export interface Settlement {
  id: string;
  driver_id: string;
  driver_name: string | null;
  driver_phone: string;
  /** YYYY-MM-DD, Monday. */
  period_start: string;
  /** YYYY-MM-DD, Sunday. */
  period_end: string;
  rides_count: number;
  gross_fares: number;
  commission: number;
  cash_collected: number;
  online_collected: number;
  /** Positive: platform pays the driver; negative: the driver owes the platform (SPEC §15). */
  amount_payable: number;
  settled_at: string | null;
  reference: string | null;
  settled_by: string | null;
}

/** `week` is any YYYY-MM-DD inside the Mon–Sun week; omit for every week. */
export function listSettlements(week?: string): Promise<Settlement[]> {
  return api(`/v1/admin/settlements${qs({ week })}`);
}

export function generateSettlements(
  week?: string,
): Promise<{ period_start: string; period_end: string; settlements: Omit<Settlement, 'driver_name' | 'driver_phone'>[] }> {
  return postJson('/v1/admin/settlements/generate', week ? { week } : {});
}

export function settleSettlement(id: string, reference: string): Promise<Settlement> {
  return postJson(`/v1/admin/settlements/${encodeURIComponent(id)}/settle`, { reference });
}
