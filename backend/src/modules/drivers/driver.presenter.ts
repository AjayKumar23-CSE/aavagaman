import type { Driver, DriverDocument, User, Vehicle } from '@prisma/client';
import { canGoOnline, documentProblems, latestByType } from './driver-rules';
import { checkLicenceNumber } from './licence-number';
import { maskPhone } from '../../common/phone';

const date = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : null);

export function presentVehicle(v: Vehicle | null | undefined) {
  if (!v) return null;
  return {
    id: v.id,
    reg_number: v.regNumber,
    make: v.make,
    model: v.model,
    colour: v.colour,
    vehicle_type: v.vehicleType,
    fuel_type: v.fuelType,
    insurance_expiry: date(v.insuranceExpiry),
    permit_expiry: date(v.permitExpiry),
    fitness_expiry: date(v.fitnessExpiry),
  };
}

export function presentDocument(d: DriverDocument, viewUrl?: string | null) {
  return {
    id: d.id,
    doc_type: d.docType,
    status: d.status,
    reviewer_note: d.reviewerNote,
    expiry: date(d.expiry),
    uploaded_at: d.uploadedAt,
    ...(viewUrl !== undefined ? { view_url: viewUrl } : {}),
  };
}

export type DriverWithRelations = Driver & {
  user: User;
  vehicles: Vehicle[];
  documents: DriverDocument[];
};

/** Profile the driver app sees (GET /driver/me). */
export function presentDriverProfile(d: DriverWithRelations, now = new Date()) {
  const latest = [...latestByType(d.documents).values()];
  const problems = documentProblems(d.documents, now);
  return {
    user_id: d.userId,
    name: d.user.name,
    phone: d.user.phone,
    verification_status: d.verificationStatus,
    reviewer_note: d.reviewerNote,
    licence_no: d.licenceNo,
    licence_expiry: date(d.licenceExpiry),
    date_of_birth: date(d.dateOfBirth),
    approved_at: d.approvedAt,
    registered: Boolean(d.licenceNo && d.vehicles.some((v) => v.active)),
    rating_avg: d.user.ratingAvg === null ? null : Number(d.user.ratingAvg),
    vehicle: presentVehicle(d.vehicles.find((v) => v.active)),
    documents: latest.map((doc) => presentDocument(doc)),
    missing_documents: problems.missing,
    expired_documents: problems.expired,
    can_go_online:
      d.user.status === 'active' && canGoOnline(d.verificationStatus, d.documents, now),
  };
}

/** Row in the admin drivers list. */
export function presentDriverListItem(d: DriverWithRelations) {
  const latest = [...latestByType(d.documents).values()];
  return {
    user_id: d.userId,
    name: d.user.name,
    phone: d.user.phone,
    phone_masked: maskPhone(d.user.phone),
    user_status: d.user.status,
    verification_status: d.verificationStatus,
    reg_number: d.vehicles.find((v) => v.active)?.regNumber ?? null,
    pending_documents: latest.filter((x) => x.status === 'pending').length,
    /** The licence number failed the offline format check (D-050). */
    licence_flagged: Boolean(checkLicenceNumber(d.licenceNo, d.dateOfBirth)?.warnings.length),
    created_at: d.createdAt,
  };
}
