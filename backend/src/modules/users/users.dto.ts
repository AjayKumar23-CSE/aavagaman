import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, Length, MaxLength, ValidateIf } from 'class-validator';

export class UpdateMeDto {
  @ApiPropertyOptional({ example: 'Asha Verma' })
  @IsOptional()
  @IsString()
  @Length(1, 80)
  name?: string;

  @ApiPropertyOptional({
    example: 'asha@example.com',
    nullable: true,
    description: 'null clears the email',
  })
  @IsOptional()
  @ValidateIf((o: UpdateMeDto) => o.email !== null)
  @IsEmail()
  @MaxLength(120)
  email?: string | null;
}

export class FcmTokenDto {
  @ApiProperty()
  @IsString()
  @Length(10, 4096)
  token: string;
}
