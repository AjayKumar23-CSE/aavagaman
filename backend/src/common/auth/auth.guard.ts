import { CanActivate, ExecutionContext, HttpStatus, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { UserRole } from '@prisma/client';
import { AppException } from '../app.exception';
import type { AuthUser } from './auth-user';
import { IS_PUBLIC, ROLES } from './decorators';

interface AccessClaims {
  sub: string;
  role: UserRole;
  typ: 'access';
}

/** Global guard: verifies the bearer access token, then enforces @Roles. */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    // WebSocket clients authenticate once at the handshake (RealtimeGateway).
    if (ctx.getType() !== 'http') return true;
    const targets = [ctx.getHandler(), ctx.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token)
      throw new AppException('UNAUTHORIZED', 'Missing access token', HttpStatus.UNAUTHORIZED);

    let claims: AccessClaims;
    try {
      claims = await this.jwt.verifyAsync<AccessClaims>(token);
    } catch {
      throw new AppException(
        'TOKEN_INVALID',
        'Access token invalid or expired',
        HttpStatus.UNAUTHORIZED,
      );
    }
    if (claims.typ !== 'access') {
      throw new AppException(
        'TOKEN_INVALID',
        'Access token invalid or expired',
        HttpStatus.UNAUTHORIZED,
      );
    }
    const user: AuthUser = { id: claims.sub, role: claims.role };
    req.user = user;

    const roles = this.reflector.getAllAndOverride<UserRole[] | undefined>(ROLES, targets);
    if (roles && !roles.includes(user.role)) {
      throw new AppException('FORBIDDEN', 'Not allowed for this role', HttpStatus.FORBIDDEN);
    }
    return true;
  }
}
