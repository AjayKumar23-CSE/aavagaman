import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsString, Length, Matches } from 'class-validator';
import { AuditService } from '../../common/audit.service';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { AuthService } from '../auth/auth.service';

export class ChangePasswordDto {
  @ApiProperty() @IsString() @Length(1, 200) current_password: string;

  @ApiProperty({ minLength: 10, description: 'At least 10 characters with a letter and a digit' })
  @IsString()
  @Length(10, 200)
  @Matches(/^(?=.*[A-Za-z])(?=.*\d).+$/, {
    message: 'new_password needs at least one letter and one digit',
  })
  new_password: string;
}

/** SPEC §13 Settings page (D-044). */
@ApiTags('admin: settings')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin/settings')
export class AdminSettingsController {
  constructor(
    private readonly auth: AuthService,
    private readonly audit: AuditService,
  ) {}

  /** Changes the signed-in admin's password; other sessions are signed out; returns a fresh token pair. */
  @Post('password')
  @HttpCode(HttpStatus.OK)
  async changePassword(@CurrentUser() u: AuthUser, @Body() dto: ChangePasswordDto) {
    const tokens = await this.auth.changeAdminPassword(
      u.id,
      dto.current_password,
      dto.new_password,
    );
    await this.audit.log({
      actorId: u.id,
      action: 'admin.password_change',
      entity: 'user',
      entityId: u.id,
    });
    return tokens;
  }
}
