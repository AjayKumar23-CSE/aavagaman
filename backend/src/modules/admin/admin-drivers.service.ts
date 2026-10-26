import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { DocType, Prisma, VerificationStatus } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { Page, skipTake } from '../../common/pagination';
import { PrismaService } from '../../common/prisma.service';
import { StorageService } from '../../common/storage.service';
import { presentUser } from '../users/user.presenter';
import { documentProblems, DRIVER_ACTIONS, DriverAction } from '../drivers/driver-rules';
import {
  presentDocument,
  presentDriverListItem,
  presentDriverProfile,
  presentVehicle,
} from '../drivers/driver.presenter';
import { PushService } from '../notifications/push.service';
import { ListDriversQuery, UpdateVehicleDto } from './dto/admin-drivers.dto';
import { checkLicenceNumber } from '../drivers/licence-number';

export const SIGNED_VIEW_SECONDS = 300; // SPEC §16: 5-minute signed GET URLs

const include = {
  user: true,
  vehicles: { where: { active: true } },
  documents: true,
} satisfies Prisma.DriverInclude;

const DOC_LABEL: Record<DocType, string> = {
  driving_licence: 'Driving licence',
  rc: 'RC',
  insurance: 'Insurance',
  permit: 'Permit',
  id_proof: 'ID proof',
  selfie: 'Selfie',
  fitness: 'Fitness certificate',
};

const PUSH_BY_ACTION: Record<DriverAction, { title: string; body: string }> = {
  approve: { title: 'You are approved', body: 'You can now go online and accept rides.' },
  reject: { title: 'Registration needs changes', body: 'Open the app to see what to fix.' },
  suspend: { title: 'Account paused', body: 'Account paused, contact support.' },
  reinstate: { title: 'Account reinstated', body: 'You can go online again.' },
};

@Injectable()
export class AdminDriversService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly audit: AuditService,
    private readonly push: PushService,
  ) {}

  async list(q: ListDriversQuery): Promise<Page<ReturnType<typeof presentDriverListItem>>> {
    const term = q.q?.trim();
    const where: Prisma.DriverWhereInput = {
      verificationStatus: q.status,
      ...(term
        ? {
            OR: [
              { user: { name: { contains: term, mode: 'insensitive' } } },
              { user: { phone: { contains: term.replace(/\s/g, '') } } },
              { licenceNo: { contains: term, mode: 'insensitive' } },
              {
                vehicles: {
                  some: {
                    active: true,
                    regNumber: { contains: term.replace(/[\s-]/g, ''), mode: 'insensitive' },
                  },
                },
              },
            ],
          }
        : {}),
    };
    const [rows, total] = await this.prisma.$transaction([
      this.prisma.driver.findMany({
        where,
        include,
        orderBy: { createdAt: 'desc' },
        ...skipTake(q),
      }),
      this.prisma.driver.count({ where }),
    ]);
    return { data: rows.map(presentDriverListItem), page: q.page, limit: q.limit, total };
  }

  private async load(driverId: string) {
    const d = await this.prisma.driver.findUnique({ where: { userId: driverId }, include });
    if (!d) throw new NotFoundException('Driver not found');
    return d;
  }

  private async viewUrl(key: string): Promise<string | null> {
    // Storage may be unconfigured in dev; the page should still render.
    return this.storage.presignGet(key, SIGNED_VIEW_SECONDS).catch(() => null);
  }

  async detail(driverId: string) {
    const d = await this.load(driverId);
    const history = [...d.documents].sort(
      (a, b) => (b.uploadedAt?.getTime() ?? 0) - (a.uploadedAt?.getTime() ?? 0),
    );
    const [documents, stats] = await Promise.all([
      Promise.all(
        history.map(async (doc) => presentDocument(doc, await this.viewUrl(doc.fileKey))),
      ),
      this.prisma.ride.groupBy({ by: ['status'], where: { driverId }, _count: true }),
    ]);
    const counts = Object.fromEntries(stats.map((s) => [s.status, s._count]));
    return {
      ...presentDriverProfile(d),
      user: presentUser(d.user),
      id_last4: d.idLast4,
      /** Offline format check; the admin confirms the licence on Parivahan (D-050). */
      licence_check: checkLicenceNumber(d.licenceNo, d.dateOfBirth),
      approved_by: d.approvedById,
      cancel_count_today: d.cancelCountToday ?? 0,
      selfie_url: d.selfieKey ? await this.viewUrl(d.selfieKey) : null,
      /** Every upload, newest first; the first of each type is the current one. */
      document_history: documents,
      stats: {
        completed_rides: (counts.COMPLETED ?? 0) + (counts.PAID ?? 0),
        cancelled_rides: counts.CANCELLED ?? 0,
        rating_avg: d.user.ratingAvg === null ? null : Number(d.user.ratingAvg),
        rating_count: d.user.ratingCount ?? 0,
      },
    };
  }

  async transition(adminId: string, driverId: string, action: DriverAction, note?: string) {
    const d = await this.load(driverId);
    const rule = DRIVER_ACTIONS[action];
    if (!(rule.from as readonly VerificationStatus[]).includes(d.verificationStatus)) {
      throw new AppException(
        'INVALID_TRANSITION',
        `Cannot ${action} a driver who is ${d.verificationStatus}`,
        HttpStatus.CONFLICT,
      );
    }
    if (action === 'approve' || action === 'reinstate') {
      const p = documentProblems(d.documents);
      const blocking = [...p.missing, ...p.unapproved, ...p.expired];
      if (blocking.length) {
        throw new AppException(
          'DOCUMENTS_INCOMPLETE',
          `Approve these documents first: ${blocking.map((t) => DOC_LABEL[t]).join(', ')}`,
          HttpStatus.UNPROCESSABLE_ENTITY,
        );
      }
      if (!d.licenceNo || !d.vehicles.length) {
        throw new AppException(
          'PROFILE_INCOMPLETE',
          'Driver has not completed registration',
          HttpStatus.UNPROCESSABLE_ENTITY,
        );
      }
    }

    const data: Prisma.DriverUpdateInput = {
      verificationStatus: rule.to,
      reviewerNote: note ?? null,
    };
    if (action === 'approve') {
      data.approvedBy = { connect: { id: adminId } };
      data.approvedAt = new Date();
    }
    if (action === 'reinstate') data.cancelCountToday = 0;

    await this.prisma.$transaction(async (tx) => {
      await tx.driver.update({ where: { userId: driverId }, data });
      await this.audit.log(
        {
          actorId: adminId,
          action: `driver.${action}`,
          entity: 'driver',
          entityId: driverId,
          before: { verification_status: d.verificationStatus, reviewer_note: d.reviewerNote },
          after: { verification_status: rule.to, reviewer_note: note ?? null },
        },
        tx,
      );
    });
    const msg = PUSH_BY_ACTION[action];
    void this.push.toUser(driverId, {
      title: msg.title,
      body: note && action !== 'approve' ? `${msg.body} ${note}` : msg.body,
      data: { type: 'driver_status', status: rule.to },
    });
    return this.detail(driverId);
  }

  async reviewDocument(
    adminId: string,
    driverId: string,
    docId: string,
    decision: 'approved' | 'rejected',
    note?: string,
  ) {
    const doc = await this.prisma.driverDocument.findFirst({ where: { id: docId, driverId } });
    if (!doc) throw new NotFoundException('Document not found');
    // Only the current upload of a type counts, so only it can be reviewed.
    const newer = await this.prisma.driverDocument.count({
      where: { driverId, docType: doc.docType, uploadedAt: { gt: doc.uploadedAt ?? new Date(0) } },
    });
    if (newer) {
      throw new AppException(
        'NOT_LATEST_DOCUMENT',
        'A newer upload of this document exists; review that one',
        HttpStatus.CONFLICT,
      );
    }

    const updated = await this.prisma.$transaction(async (tx) => {
      const u = await tx.driverDocument.update({
        where: { id: docId },
        data: { status: decision, reviewerNote: note ?? null },
      });
      await this.audit.log(
        {
          actorId: adminId,
          action: `document.${decision === 'approved' ? 'approve' : 'reject'}`,
          entity: 'driver_document',
          entityId: docId,
          before: { status: doc.status, reviewer_note: doc.reviewerNote },
          after: { status: decision, reviewer_note: note ?? null },
        },
        tx,
      );
      return u;
    });
    const label = DOC_LABEL[doc.docType];
    void this.push.toUser(driverId, {
      title: decision === 'approved' ? `${label} approved` : `${label} rejected`,
      body:
        note ??
        (decision === 'approved'
          ? 'Thanks, this document is verified.'
          : 'Please upload it again.'),
      data: { type: 'document_status', doc_type: doc.docType, status: decision },
    });
    return presentDocument(updated, await this.viewUrl(updated.fileKey));
  }

  async updateVehicle(adminId: string, driverId: string, dto: UpdateVehicleDto) {
    const d = await this.load(driverId);
    const vehicle = d.vehicles[0];
    if (!vehicle) throw new NotFoundException('Driver has no active vehicle');
    const day = (s?: string) => (s ? new Date(s + 'T00:00:00Z') : undefined);
    const updated = await this.prisma.$transaction(async (tx) => {
      const v = await tx.vehicle.update({
        where: { id: vehicle.id },
        data: {
          regNumber: dto.reg_number,
          make: dto.make,
          model: dto.model,
          colour: dto.colour,
          vehicleType: dto.vehicle_type,
          fuelType: dto.fuel_type,
          insuranceExpiry: day(dto.insurance_expiry),
          permitExpiry: day(dto.permit_expiry),
          fitnessExpiry: day(dto.fitness_expiry),
        },
      });
      await this.audit.log(
        {
          actorId: adminId,
          action: 'vehicle.update',
          entity: 'vehicle',
          entityId: vehicle.id,
          before: presentVehicle(vehicle),
          after: presentVehicle(v),
        },
        tx,
      );
      return v;
    });
    return presentVehicle(updated);
  }
}
