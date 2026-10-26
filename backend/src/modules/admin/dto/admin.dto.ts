import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { VEHICLE_TYPES, VehicleType } from '../../../common/vehicle-types';
import { Transform, Type } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  MaxLength,
  Min,
} from 'class-validator';
import { RideStatus } from '@prisma/client';
import { PageQuery } from '../../../common/pagination';

const toBool = ({ value }: { value: unknown }) =>
  value === 'true' ? true : value === 'false' ? false : value;

export class ListRidesQuery extends PageQuery {
  @ApiPropertyOptional({ enum: RideStatus }) @IsOptional() @IsEnum(RideStatus) status?: RideStatus;
  @ApiPropertyOptional({ description: 'requested_at ≥ (ISO)' })
  @IsOptional()
  @IsDateString()
  from?: string;
  @ApiPropertyOptional({ description: 'requested_at < (ISO)' })
  @IsOptional()
  @IsDateString()
  to?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() driver_id?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() rider_id?: string;
}

export class ReassignDto {
  @ApiProperty() @IsUUID() driver_id: string;
}

export class AdjustFareDto {
  @ApiProperty({ example: 180 }) @Type(() => Number) @IsNumber() @Min(0) final_fare: number;
  @ApiProperty({ example: 'Meter dispute resolved in rider favour' })
  @IsString()
  @Length(1, 300)
  reason: string;
}

export class ListRidersQuery extends PageQuery {
  @ApiPropertyOptional({ description: 'Name, phone or email' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  q?: string;
}

export class ReasonBodyDto {
  @ApiProperty() @IsString() @Length(1, 300) reason: string;
}

export class FareConfigDto {
  @ApiPropertyOptional({ enum: VEHICLE_TYPES, default: 'sedan' })
  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicle_type?: VehicleType;
  @ApiProperty({ example: 50 }) @Type(() => Number) @IsNumber() @Min(0) base_fare: number;
  @ApiProperty({ example: 12 }) @Type(() => Number) @IsNumber() @Min(0) per_km: number;
  @ApiProperty({ example: 1.5 }) @Type(() => Number) @IsNumber() @Min(0) per_min: number;
  @ApiProperty({ example: 80 }) @Type(() => Number) @IsNumber() @Min(0) min_fare: number;
  @ApiPropertyOptional({ example: 30, default: 30 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  cancellation_fee?: number;
  @ApiPropertyOptional({ example: 1.25, default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  night_multiplier?: number;
  @ApiPropertyOptional({ default: false }) @IsOptional() @IsBoolean() night_enabled?: boolean;
  @ApiPropertyOptional({ example: 15, default: 15 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  commission_pct?: number;
  @ApiPropertyOptional({ example: 5, default: 5 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  gst_pct?: number;
  @ApiPropertyOptional({ description: 'ISO time; default now' })
  @IsOptional()
  @IsDateString()
  effective_from?: string;
}

export class FarePreviewDto extends FareConfigDto {
  @ApiProperty({ example: 10000 }) @Type(() => Number) @IsInt() @Min(0) distance_m: number;
  @ApiProperty({ example: 1800 }) @Type(() => Number) @IsInt() @Min(0) duration_s: number;
  @ApiPropertyOptional({ description: 'ISO time used for the night check; default now' })
  @IsOptional()
  @IsDateString()
  at?: string;
}

export class ServiceAreaDto {
  @ApiProperty({ example: 'Delhi NCR' }) @IsString() @Length(1, 60) name: string;
  @ApiProperty({ description: 'GeoJSON Polygon' }) @IsObject() polygon: {
    type: string;
    coordinates: unknown;
  };
  @ApiPropertyOptional({ default: true }) @IsOptional() @IsBoolean() active?: boolean;
}

export class ServiceAreaPatchDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 60) name?: string;
  @ApiPropertyOptional() @IsOptional() @IsObject() polygon?: { type: string; coordinates: unknown };
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}

export class DailyReportQuery {
  @ApiProperty({ example: '2026-09-01', description: 'IST day, inclusive' })
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  from: string;
  @ApiProperty({ example: '2026-09-30', description: 'IST day, inclusive' })
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  to: string;
  @ApiPropertyOptional({ enum: ['json', 'csv'] }) @IsOptional() @IsIn(['json', 'csv']) format?:
    'json' | 'csv';
}

export class SettlementsQuery {
  @ApiPropertyOptional({ example: '2026-09-21', description: 'Any date in the Mon–Sun week' })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  week?: string;
}

export class GenerateSettlementsDto {
  @ApiPropertyOptional({
    example: '2026-09-21',
    description: 'Any date in the week; default last week',
  })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  week?: string;
}

export class SettleDto {
  @ApiProperty({ example: 'NEFT UTR 1234567890' }) @IsString() @Length(1, 120) reference: string;
}

export class SosQuery extends PageQuery {
  @ApiPropertyOptional({ type: Boolean })
  @IsOptional()
  @Transform(toBool)
  @IsBoolean()
  acknowledged?: boolean;
}

export class AuditQuery extends PageQuery {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(40) entity?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() entity_id?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() actor_id?: string;
}
