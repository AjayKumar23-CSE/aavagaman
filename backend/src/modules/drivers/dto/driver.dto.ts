import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsDateString,
  IsEnum,
  IsIn,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
  ValidateNested,
} from 'class-validator';
import { DocType } from '@prisma/client';
import { UPLOAD_CONTENT_TYPES } from '../driver-rules';
import { VEHICLE_TYPES, VehicleType } from '../../../common/vehicle-types';

export const FUEL_TYPES = ['petrol', 'diesel', 'cng', 'ev'] as const;

const upperNoSpace = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.replace(/[\s-]/g, '').toUpperCase() : value;

export class VehicleDto {
  @ApiProperty({ example: 'DL01AB1234' })
  @Transform(upperNoSpace)
  @Matches(/^[A-Z0-9]{6,11}$/, { message: 'reg_number must look like DL01AB1234' })
  reg_number: string;

  @ApiProperty({ example: 'Maruti Suzuki' })
  @IsString()
  @Length(1, 40)
  make: string;

  @ApiProperty({ example: 'Dzire' })
  @IsString()
  @Length(1, 40)
  model: string;

  @ApiProperty({ example: 'White' })
  @IsString()
  @Length(1, 30)
  colour: string;

  @ApiProperty({ enum: FUEL_TYPES })
  @IsIn(FUEL_TYPES)
  fuel_type: (typeof FUEL_TYPES)[number];

  @ApiPropertyOptional({ enum: VEHICLE_TYPES, default: 'sedan' })
  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicle_type?: VehicleType;
}

export class RegisterDriverDto {
  @ApiProperty({ example: 'Ravi Kumar' })
  @IsString()
  @Length(1, 80)
  name: string;

  @ApiProperty({ example: 'DL0420110012345' })
  @Transform(upperNoSpace)
  @Matches(/^[A-Z0-9]{8,20}$/, { message: 'licence_no is not a valid licence number' })
  licence_no: string;

  @ApiProperty({ example: '2031-05-31' })
  @IsDateString({ strict: true })
  licence_expiry: string;

  @ApiProperty({
    example: '1990-06-15',
    description: 'As printed on the licence; needed for the Parivahan check',
  })
  @IsDateString({ strict: true })
  date_of_birth: string;

  @ApiProperty({ type: VehicleDto })
  @ValidateNested()
  @Type(() => VehicleDto)
  vehicle: VehicleDto;
}

export class PresignDto {
  @ApiProperty({ enum: DocType })
  @IsEnum(DocType)
  doc_type: DocType;

  @ApiProperty({ enum: Object.keys(UPLOAD_CONTENT_TYPES) })
  @IsIn(Object.keys(UPLOAD_CONTENT_TYPES))
  content_type: string;
}

export class CreateDocumentDto {
  @ApiProperty({ enum: DocType })
  @IsEnum(DocType)
  doc_type: DocType;

  @ApiProperty()
  @IsString()
  @MaxLength(300)
  file_key: string;

  @ApiPropertyOptional({
    example: '2027-03-31',
    description: 'Required for licence, insurance, permit, fitness',
  })
  @IsOptional()
  @IsDateString({ strict: true })
  expiry?: string;

  @ApiPropertyOptional({
    example: '1234',
    description: 'id_proof only: last 4 digits of the ID (D-014)',
  })
  @IsOptional()
  @Matches(/^\d{4}$/)
  id_last4?: string;
}
