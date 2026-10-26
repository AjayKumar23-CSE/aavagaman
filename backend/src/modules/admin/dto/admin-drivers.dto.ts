import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { VEHICLE_TYPES, VehicleType } from '../../../common/vehicle-types';
import { Transform } from 'class-transformer';
import {
  IsDateString,
  IsEnum,
  IsIn,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
} from 'class-validator';
import { VerificationStatus } from '@prisma/client';
import { PageQuery } from '../../../common/pagination';
import { FUEL_TYPES } from '../../drivers/dto/driver.dto';

export class ListDriversQuery extends PageQuery {
  @ApiPropertyOptional({ enum: VerificationStatus })
  @IsOptional()
  @IsEnum(VerificationStatus)
  status?: VerificationStatus;

  @ApiPropertyOptional({ description: 'Name, phone, licence or registration number' })
  @IsOptional()
  @IsString()
  @MaxLength(60)
  q?: string;
}

export class NoteDto {
  @ApiPropertyOptional({ example: 'Photo is blurry, please re-upload' })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

/** Destructive actions carry a mandatory reason (SPEC §13). */
export class ReasonDto {
  @ApiProperty({ example: 'Insurance has lapsed' })
  @IsString()
  @Length(1, 500)
  note: string;
}

export class UpdateVehicleDto {
  @ApiPropertyOptional()
  @IsOptional()
  @Transform(({ value }) =>
    typeof value === 'string' ? value.replace(/[\s-]/g, '').toUpperCase() : value,
  )
  @Matches(/^[A-Z0-9]{6,11}$/)
  reg_number?: string;

  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 40) make?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 40) model?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 30) colour?: string;

  @ApiPropertyOptional({ enum: VEHICLE_TYPES })
  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicle_type?: VehicleType;

  @ApiPropertyOptional({ enum: FUEL_TYPES })
  @IsOptional()
  @IsIn(FUEL_TYPES)
  fuel_type?: string;

  @ApiPropertyOptional() @IsOptional() @IsDateString({ strict: true }) insurance_expiry?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString({ strict: true }) permit_expiry?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString({ strict: true }) fitness_expiry?: string;
}
