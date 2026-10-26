import { Body, Controller, HttpCode, HttpStatus, Ip, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiNoContentResponse, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Public } from '../../common/auth/decorators';
import { AuthService } from './auth.service';
import { AdminLoginDto, OtpSendDto, OtpVerifyDto, RefreshDto } from './dto/auth.dto';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('otp/send')
  @HttpCode(HttpStatus.OK)
  send(@Body() dto: OtpSendDto, @Ip() ip: string) {
    return this.auth.sendOtp(dto, ip);
  }

  @Public()
  @Post('otp/verify')
  @HttpCode(HttpStatus.OK)
  verify(@Body() dto: OtpVerifyDto) {
    return this.auth.verifyOtp(dto);
  }

  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refresh_token);
  }

  @ApiBearerAuth()
  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiNoContentResponse()
  async logout(@CurrentUser() user: AuthUser) {
    await this.auth.logout(user.id);
  }

  @Public()
  @Post('admin/login')
  @HttpCode(HttpStatus.OK)
  adminLogin(@Body() dto: AdminLoginDto) {
    return this.auth.adminLogin(dto);
  }
}
