import { api, postJson } from './api';

export type VerificationStatus = 'pending' | 'approved' | 'rejected' | 'suspended';
export type DocStatus = 'pending' | 'approved' | 'rejected';
export type FuelType = 'petrol' | 'diesel' | 'cng' | 'ev';
export type DocType = 'driving_licence' | 'rc' | 'insurance' | 'permit' | 'id_proof' | 'selfie' | 'fitness';

export const VERIFICATION_STATUSES: VerificationStatus[] = ['pending', 'approved', 'rejected', 'suspended'];
export const FUEL_TYPES: FuelType[] = ['petrol', 'diesel', 'cng', 'ev'];

/** Display order; every type except fitness is mandatory. */
export const DOC_TYPES: DocType[] = ['driving_licence', 'rc', 'insurance', 'permit', 'id_proof', 'selfie', 'fitness'];
export const MANDATORY_DOC_TYPES: DocType[] = DOC_TYPES.filter((t) => t !== 'fitness');

export const DOC_LABEL: Record<DocType, string> = {
  driving_licence: 'Driving licence',
  rc: 'RC',
  insurance: 'Insurance',
  permit: 'Permit',
  id_proof: 'ID proof',
  selfie: 'Selfie',
  fitness: 'Fitness certificate',
};

export interface DriverListItem {
  user_id: string;
  name: string | null;
  phone: string;
  phone_masked: string;
  user_status: string;
  verification_status: VerificationStatus;
  reg_number: string | null;
  pending_documents: number;
  /** The licence number failed the offline format check. */
  licence_flagged: boolean;
  created_at: string;
}

/** Offline licence-number format check (backend D-050). */
export interface LicenceCheck {
  standard: boolean;
  state_code: string | null;
  state: string | null;
  rto_code: string | null;
  issue_year: number | null;
  warnings: string[];
}

export interface Paginated<T> {
  data: T[];
  page: number;
  limit: number;
  total: number;
}

/** Vehicle classes (D-056), display order. */
export const VEHICLE_TYPES = ['bike', 'auto', 'mini', 'sedan'] as const;
export type VehicleTypeId = (typeof VEHICLE_TYPES)[number];

export interface Vehicle {
  id: string;
  reg_number: string;
  make: string;
  model: string;
  colour: string;
  vehicle_type: string;
  fuel_type: FuelType;
  insurance_expiry: string | null;
  permit_expiry: string | null;
  fitness_expiry: string | null;
}

export interface DriverDocument {
  id: string;
  doc_type: DocType;
  status: DocStatus;
  reviewer_note: string | null;
  expiry: string | null;
  uploaded_at: string;
}

export interface DocumentHistoryItem extends DriverDocument {
  view_url: string | null;
}

export interface DriverDetail {
  user_id: string;
  name: string | null;
  phone: string;
  verification_status: VerificationStatus;
  reviewer_note: string | null;
  licence_no: string | null;
  licence_expiry: string | null;
  /** YYYY-MM-DD; null for drivers who registered before it was asked. */
  date_of_birth: string | null;
  approved_at: string | null;
  registered: boolean;
  rating_avg: number;
  vehicle: Vehicle | null;
  documents: DriverDocument[];
  missing_documents: DocType[];
  expired_documents: DocType[];
  can_go_online: boolean;
  user: {
    id: string;
    phone: string;
    name: string | null;
    email: string | null;
    role: string;
    status: string;
    rating_avg: number;
    rating_count: number;
    created_at: string;
  };
  id_last4: string | null;
  licence_check: LicenceCheck | null;
  approved_by: string | null;
  cancel_count_today: number;
  selfie_url: string | null;
  document_history: DocumentHistoryItem[];
  stats: { completed_rides: number; cancelled_rides: number; rating_avg: number; rating_count: number };
}

export interface DriverListParams {
  status?: VerificationStatus;
  q?: string;
  page: number;
  limit: number;
}

export function listDrivers(p: DriverListParams): Promise<Paginated<DriverListItem>> {
  const qs = new URLSearchParams({ page: String(p.page), limit: String(p.limit) });
  if (p.status) qs.set('status', p.status);
  if (p.q) qs.set('q', p.q);
  return api(`/v1/admin/drivers?${qs.toString()}`);
}

export function getDriver(id: string): Promise<DriverDetail> {
  return api(`/v1/admin/drivers/${encodeURIComponent(id)}`);
}

export type DriverAction = 'approve' | 'reject' | 'suspend' | 'reinstate';

export function driverAction(id: string, action: DriverAction, note?: string): Promise<DriverDetail> {
  return postJson(`/v1/admin/drivers/${encodeURIComponent(id)}/${action}`, note ? { note } : {});
}

export function reviewDocument(
  driverId: string,
  docId: string,
  decision: 'approve' | 'reject',
  note?: string,
): Promise<DocumentHistoryItem> {
  return postJson(
    `/v1/admin/drivers/${encodeURIComponent(driverId)}/documents/${encodeURIComponent(docId)}/${decision}`,
    note ? { note } : {},
  );
}

export type VehiclePatch = Partial<
  Pick<Vehicle, 'reg_number' | 'make' | 'model' | 'colour' | 'fuel_type' | 'vehicle_type'> & {
    insurance_expiry: string;
    permit_expiry: string;
    fitness_expiry: string;
  }
>;

export function updateVehicle(driverId: string, patch: VehiclePatch): Promise<Vehicle> {
  return api(`/v1/admin/drivers/${encodeURIComponent(driverId)}/vehicle`, {
    method: 'PATCH',
    body: JSON.stringify(patch),
  });
}
