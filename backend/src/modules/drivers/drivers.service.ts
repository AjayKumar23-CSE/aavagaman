import { randomUUID } from 'node:crypto';
import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { DEFAULT_VEHICLE_TYPE } from '../../common/vehicle-types';
import { PrismaService } from '../../common/prisma.service';
import { StorageService } from '../../common/storage.service';
import {
  EXPIRING_DOCS,
  hasTurned,
  isExpired,
  MIN_DRIVER_AGE,
  UPLOAD_CONTENT_TYPES,
} from './driver-rules';
import { presentDocument, presentDriverProfile } from './driver.presenter';
import { CreateDocumentDto, PresignDto, RegisterDriverDto } from './dto/driver.dto';

export const PRESIGN_PUT_SECONDS = 600; // SPEC §7.3: 10 min

const withRelations = {
  user: true,
  vehicles: { where: { active: true } },
  documents: true,
} satisfies Prisma.DriverInclude;

const asDate = (s: string) => new Date(s + 'T00:00:00Z');

@Injectable()
export class DriversService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  /** Drivers are created at OTP verify; this also self-heals a missing row. */
  private async load(userId: string) {
    const driver = await this.prisma.driver.upsert({
      where: { userId },
      create: { userId },
      update: {},
      include: withRelations,
    });
    return driver;
  }

  async me(userId: string) {
    return presentDriverProfile(await this.load(userId));
  }

  async register(userId: string, dto: RegisterDriverDto) {
    const driver = await this.load(userId);
    if (driver.verificationStatus === 'approved' || driver.verificationStatus === 'suspended') {
      throw new AppException(
        'ALREADY_REGISTERED',
        'Your profile is already approved. Contact support to change it.',
        HttpStatus.CONFLICT,
      );
    }
    const licenceExpiry = asDate(dto.licence_expiry);
    if (isExpired(licenceExpiry)) {
      throw new AppException(
        'LICENCE_EXPIRED',
        'Your driving licence has expired',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const dateOfBirth = asDate(dto.date_of_birth);
    if (!hasTurned(dateOfBirth, MIN_DRIVER_AGE)) {
      throw new AppException(
        'DATE_OF_BIRTH_INVALID',
        `You must be at least ${MIN_DRIVER_AGE} years old to drive`,
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }

    const v = dto.vehicle;
    const vehicleData = {
      regNumber: v.reg_number,
      make: v.make.trim(),
      model: v.model.trim(),
      colour: v.colour.trim(),
      fuelType: v.fuel_type,
      vehicleType: v.vehicle_type ?? DEFAULT_VEHICLE_TYPE,
    };
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data: { name: dto.name.trim() } });
      await tx.driver.update({
        where: { userId },
        data: {
          licenceNo: dto.licence_no,
          licenceExpiry,
          dateOfBirth,
          // Re-submitting after a rejection puts the driver back in the review queue.
          verificationStatus: 'pending',
        },
      });
      const active = driver.vehicles[0];
      if (active) await tx.vehicle.update({ where: { id: active.id }, data: vehicleData });
      else await tx.vehicle.create({ data: { ...vehicleData, driverId: userId } });
    });
    return this.me(userId);
  }

  async presign(userId: string, dto: PresignDto) {
    const ext = UPLOAD_CONTENT_TYPES[dto.content_type];
    const file_key = `drivers/${userId}/${dto.doc_type}/${randomUUID()}.${ext}`;
    const upload_url = await this.storage.presignPut(
      file_key,
      dto.content_type,
      PRESIGN_PUT_SECONDS,
    );
    return { upload_url, file_key, expires_in: PRESIGN_PUT_SECONDS };
  }

  async addDocument(userId: string, dto: CreateDocumentDto) {
    const driver = await this.load(userId);
    if (!dto.file_key.startsWith(`drivers/${userId}/${dto.doc_type}/`)) {
      throw new AppException(
        'INVALID_FILE_KEY',
        'file_key does not belong to this upload',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const expiry = dto.expiry ? asDate(dto.expiry) : null;
    if (EXPIRING_DOCS.includes(dto.doc_type) && !expiry) {
      throw new AppException(
        'EXPIRY_REQUIRED',
        `${dto.doc_type} needs an expiry date`,
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    if (isExpired(expiry)) {
      throw new AppException(
        'DOCUMENT_EXPIRED',
        'This document has already expired',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    if (dto.doc_type === 'id_proof' && !dto.id_last4) {
      throw new AppException(
        'ID_LAST4_REQUIRED',
        'Enter the last 4 digits of your ID',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }

    const vehicle = driver.vehicles[0];
    const doc = await this.prisma.$transaction(async (tx) => {
      const created = await tx.driverDocument.create({
        data: { driverId: userId, docType: dto.doc_type, fileKey: dto.file_key, expiry },
      });

      // Keep the denormalised columns in sync (SPEC §5 drivers / vehicles).
      const driverData: Prisma.DriverUpdateInput = {};
      if (dto.doc_type === 'selfie') driverData.selfieKey = dto.file_key;
      if (dto.doc_type === 'id_proof') driverData.idLast4 = dto.id_last4;
      if (dto.doc_type === 'driving_licence') driverData.licenceExpiry = expiry;
      if (driver.verificationStatus === 'rejected') driverData.verificationStatus = 'pending';
      if (Object.keys(driverData).length)
        await tx.driver.update({ where: { userId }, data: driverData });

      const vehicleField = {
        insurance: 'insuranceExpiry',
        permit: 'permitExpiry',
        fitness: 'fitnessExpiry',
      }[dto.doc_type as string];
      if (vehicle && vehicleField) {
        await tx.vehicle.update({ where: { id: vehicle.id }, data: { [vehicleField]: expiry } });
      }
      return created;
    });
    return presentDocument(doc);
  }

  async assertExists(userId: string) {
    const d = await this.prisma.driver.findUnique({ where: { userId }, select: { userId: true } });
    if (!d) throw new NotFoundException('Driver not found');
  }
}
