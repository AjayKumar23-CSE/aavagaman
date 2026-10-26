import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
  ValidateNested,
} from 'class-validator';

const LOGIN_ROLES = ['rider', 'driver'] as const;
export type LoginRole = (typeof LOGIN_ROLES)[number];

export class OtpSendDto {
  @ApiProperty({ example: '+919812345678' })
  @IsString()
  @MaxLength(20)
  phone: string;

  @ApiProperty({ enum: LOGIN_ROLES })
  @IsIn(LOGIN_ROLES)
  role: LoginRole;
}

export class DeviceDto {
  @ApiProperty({ example: 'android' })
  @IsString()
  @MaxLength(20)
  platform: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(4096)
  fcm_token?: string;

  @ApiPropertyOptional({ example: '0.1.0+1' })
  @IsOptional()
  @IsString()
  @MaxLength(40)
  app_version?: string;
}

export class OtpVerifyDto extends OtpSendDto {
  @ApiProperty({ example: '123456' })
  @Matches(/^\d{4,8}$/, { message: 'code must be numeric' })
  code: string;

  @ApiPropertyOptional({ type: DeviceDto })
  @IsOptional()
  @ValidateNested()
  @Type(() => DeviceDto)
  device?: DeviceDto;
}

export class RefreshDto {
  @ApiProperty()
  @IsString()
  @Length(10, 200)
  refresh_token: string;
}

export class AdminLoginDto {
  @ApiProperty({ example: 'admin@example.com' })
  @IsEmail()
  @MaxLength(120)
  email: string;

  @ApiProperty()
  @IsString()
  @Length(1, 200)
  password: string;
}
