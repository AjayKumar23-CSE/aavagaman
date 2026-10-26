import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsString,
  Length,
  Max,
  Min,
} from 'class-validator';

export class LatLngDto {
  @ApiProperty({ example: 28.6315 })
  @Type(() => Number)
  @IsLatitude()
  lat: number;

  @ApiProperty({ example: 77.2167 })
  @Type(() => Number)
  @IsLongitude()
  lng: number;
}

export class PlaceDto extends LatLngDto {
  @ApiProperty({ example: 'Connaught Place, New Delhi' })
  @IsString()
  @Length(1, 300)
  address: string;
}

/** Driver GPS fix (SPEC §7.3 / §8 driver:location). */
export class DriverFixDto extends LatLngDto {
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(360) heading?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(100) speed?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) accuracy?: number;
  @ApiPropertyOptional({ description: 'epoch ms' }) @IsOptional() @IsNumber() ts?: number;
}
