import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Length, Matches, Max, MaxLength, Min } from 'class-validator';
import { DriverFixDto, LatLngDto } from '../../../common/geo/geo.dto';

export class ArrivedDto extends DriverFixDto {}
export class CompleteDto extends DriverFixDto {}

export class StartDto extends DriverFixDto {
  @ApiProperty({ example: '4821' })
  @Matches(/^\d{4}$/, { message: 'otp must be 4 digits' })
  otp: string;
}

export class DriverCancelDto {
  @ApiProperty({ example: 'Vehicle breakdown' })
  @IsString()
  @Length(1, 300)
  reason: string;
}

export class AdminCancelDto extends DriverCancelDto {}

export class RatingDto {
  @ApiProperty({ minimum: 1, maximum: 5 })
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(5)
  stars: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(300)
  comment?: string;
}

export class SosDto extends LatLngDto {}
