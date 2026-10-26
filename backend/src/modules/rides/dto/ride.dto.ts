import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsIn, IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
import { PlaceDto } from '../../../common/geo/geo.dto';
import { VEHICLE_TYPES, VehicleType } from '../../../common/vehicle-types';

export class CreateRideDto {
  @ApiProperty({ type: PlaceDto }) @ValidateNested() @Type(() => PlaceDto) pickup: PlaceDto;
  @ApiProperty({ type: PlaceDto }) @ValidateNested() @Type(() => PlaceDto) drop: PlaceDto;

  @ApiProperty() @IsUUID() fare_config_id: string;

  @ApiPropertyOptional({ enum: VEHICLE_TYPES, default: 'sedan', description: 'Must match the fare config (D-056)' })
  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicle_type?: VehicleType;

  @ApiProperty({ enum: ['cash', 'online'] })
  @IsIn(['cash', 'online'])
  payment_method: 'cash' | 'online';
}

export class CancelRideDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) reason?: string;
}
