import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { AppException } from '../../common/app.exception';
import { AuditService } from '../../common/audit.service';
import { PrismaService } from '../../common/prisma.service';
import { estimate } from '../fare/fare.engine';
import { DEFAULT_VEHICLE_TYPE, VEHICLE_TYPES } from '../../common/vehicle-types';
import {
  FareConfigDto,
  FarePreviewDto,
  ServiceAreaDto,
  ServiceAreaPatchDto,
} from './dto/admin.dto';

export function presentFareConfig(c: Prisma.FareConfigGetPayload<object>) {
  return {
    id: c.id,
    vehicle_type: c.vehicleType,
    base_fare: Number(c.baseFare),
    per_km: Number(c.perKm),
    per_min: Number(c.perMin),
    min_fare: Number(c.minFare),
    cancellation_fee: Number(c.cancellationFee),
    night_multiplier: Number(c.nightMultiplier),
    night_enabled: c.nightEnabled,
    commission_pct: Number(c.commissionPct),
    gst_pct: Number(c.gstPct),
    effective_from: c.effectiveFrom,
    created_by: c.createdById,
  };
}

interface AreaRow {
  id: string;
  name: string;
  active: boolean | null;
  created_at: Date | null;
  geojson: string;
}

const toFeature = (r: AreaRow) => ({
  type: 'Feature' as const,
  id: r.id,
  properties: { id: r.id, name: r.name, active: r.active ?? true, created_at: r.created_at },
  geometry: JSON.parse(r.geojson) as { type: string; coordinates: unknown },
});

@Injectable()
export class AdminConfigService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  // ---- fare config (SPEC §7.4 GET/POST /admin/fare-config)

  async listFareConfigs() {
    const rows = await this.prisma.fareConfig.findMany({ orderBy: { effectiveFrom: 'desc' } });
    const now = new Date();
    // Newest effective version per vehicle class (D-056); current_id keeps the sedan one for older clients.
    const currentIds: Record<string, string> = {};
    for (const r of rows) {
      if (r.effectiveFrom <= now && !currentIds[r.vehicleType]) currentIds[r.vehicleType] = r.id;
    }
    return {
      current_id: currentIds[DEFAULT_VEHICLE_TYPE] ?? null,
      current_ids: currentIds,
      vehicle_types: VEHICLE_TYPES,
      data: rows.map(presentFareConfig),
    };
  }

  async createFareConfig(adminId: string, dto: FareConfigDto) {
    const created = await this.prisma.fareConfig.create({
      data: {
        vehicleType: dto.vehicle_type ?? DEFAULT_VEHICLE_TYPE,
        baseFare: dto.base_fare,
        perKm: dto.per_km,
        perMin: dto.per_min,
        minFare: dto.min_fare,
        cancellationFee: dto.cancellation_fee ?? 30,
        nightMultiplier: dto.night_multiplier ?? 1,
        nightEnabled: dto.night_enabled ?? false,
        commissionPct: dto.commission_pct ?? 15,
        gstPct: dto.gst_pct ?? 5,
        effectiveFrom: dto.effective_from ? new Date(dto.effective_from) : new Date(),
        createdById: adminId,
      },
    });
    await this.audit.log({
      actorId: adminId,
      action: 'fare_config.create',
      entity: 'fare_config',
      entityId: created.id,
      after: presentFareConfig(created),
    });
    return presentFareConfig(created);
  }

  /** Preview calculator for the admin form (SPEC §13); pure, nothing stored. */
  preview(dto: FarePreviewDto) {
    const cfg = {
      baseFare: dto.base_fare,
      perKm: dto.per_km,
      perMin: dto.per_min,
      minFare: dto.min_fare,
      nightMultiplier: dto.night_multiplier ?? 1,
      nightEnabled: dto.night_enabled ?? false,
      gstPct: dto.gst_pct ?? 5,
      commissionPct: dto.commission_pct ?? 15,
    };
    const e = estimate(dto.distance_m, dto.duration_s, cfg, dto.at ? new Date(dto.at) : new Date());
    return {
      fare: Math.round(e.fare * 100) / 100,
      fare_min: e.fare_min,
      fare_max: e.fare_max,
      cap: Math.round(e.fare * 1.25),
    };
  }

  // ---- service areas (SPEC §7.4 GET/POST/PATCH /admin/service-areas)

  async listAreas() {
    const rows = await this.prisma.$queryRaw<AreaRow[]>`
      SELECT id, name, active, created_at, ST_AsGeoJSON(polygon::geometry) AS geojson
      FROM service_areas ORDER BY created_at`;
    return { type: 'FeatureCollection' as const, features: rows.map(toFeature) };
  }

  private async validatePolygon(polygon: { type: string; coordinates: unknown }) {
    if (polygon?.type !== 'Polygon') {
      throw new AppException(
        'INVALID_POLYGON',
        'polygon must be a GeoJSON Polygon',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    const json = JSON.stringify(polygon);
    const [row] = await this.prisma.$queryRaw<{ valid: boolean; reason: string }[]>`
      SELECT ST_IsValid(ST_GeomFromGeoJSON(${json})) AS valid, ST_IsValidReason(ST_GeomFromGeoJSON(${json})) AS reason`;
    if (!row.valid)
      throw new AppException(
        'INVALID_POLYGON',
        `Polygon is not valid: ${row.reason}`,
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    return json;
  }

  async createArea(adminId: string, dto: ServiceAreaDto) {
    const json = await this.validatePolygon(dto.polygon);
    const [row] = await this.prisma.$queryRaw<AreaRow[]>`
      INSERT INTO service_areas (name, polygon, active)
      VALUES (${dto.name.trim()}, ST_GeomFromGeoJSON(${json})::geography, ${dto.active ?? true})
      RETURNING id, name, active, created_at, ST_AsGeoJSON(polygon::geometry) AS geojson`;
    await this.audit.log({
      actorId: adminId,
      action: 'service_area.create',
      entity: 'service_area',
      entityId: row.id,
      after: { name: row.name, active: row.active },
    });
    return toFeature(row);
  }

  async patchArea(adminId: string, id: string, dto: ServiceAreaPatchDto) {
    const [before] = await this.prisma.$queryRaw<AreaRow[]>`
      SELECT id, name, active, created_at, ST_AsGeoJSON(polygon::geometry) AS geojson FROM service_areas WHERE id = ${id}::uuid`;
    if (!before) throw new NotFoundException('Service area not found');
    const json = dto.polygon ? await this.validatePolygon(dto.polygon) : null;
    const [row] = await this.prisma.$queryRaw<AreaRow[]>`
      UPDATE service_areas SET
        name = COALESCE(${dto.name?.trim() ?? null}, name),
        active = COALESCE(${dto.active ?? null}::boolean, active),
        polygon = COALESCE(ST_GeomFromGeoJSON(${json})::geography, polygon)
      WHERE id = ${id}::uuid
      RETURNING id, name, active, created_at, ST_AsGeoJSON(polygon::geometry) AS geojson`;
    await this.audit.log({
      actorId: adminId,
      action: 'service_area.update',
      entity: 'service_area',
      entityId: id,
      before: { name: before.name, active: before.active, polygon_changed: false },
      after: { name: row.name, active: row.active, polygon_changed: Boolean(json) },
    });
    return toFeature(row);
  }
}
