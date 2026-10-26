import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Patch, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { FcmTokenDto, UpdateMeDto } from './users.dto';
import { UsersService } from './users.service';

@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  me(@CurrentUser() user: AuthUser) {
    return this.users.me(user.id);
  }

  @Patch()
  update(@CurrentUser() user: AuthUser, @Body() dto: UpdateMeDto) {
    return this.users.update(user.id, dto);
  }

  @Post('fcm-token')
  @HttpCode(HttpStatus.NO_CONTENT)
  async fcmToken(@CurrentUser() user: AuthUser, @Body() dto: FcmTokenDto) {
    await this.users.setFcmToken(user.id, dto.token);
  }

  /** Account deletion (SPEC §11 drawer, §16 anonymisation). */
  @Delete()
  @HttpCode(HttpStatus.NO_CONTENT)
  async delete(@CurrentUser() user: AuthUser) {
    await this.users.deleteAccount(user.id);
  }
}
