import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { AuthGuard } from '../../common/auth/auth.guard';
import { loadConfig } from '../../config/config.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { OtpService } from './otp.service';
import { TokenService } from './token.service';

@Module({
  imports: [
    JwtModule.registerAsync({
      global: true,
      useFactory: () => ({ secret: loadConfig().JWT_ACCESS_SECRET }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService, OtpService, TokenService, { provide: APP_GUARD, useClass: AuthGuard }],
  exports: [TokenService, AuthService],
})
export class AuthModule {}
