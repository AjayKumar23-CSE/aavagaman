import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import type { UserRole } from '@prisma/client';
import type { AuthUser } from './auth-user';

export const IS_PUBLIC = 'isPublic';
export const ROLES = 'roles';

/** Skips the global JWT guard. */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Restricts a controller or handler to the given roles (SPEC §16). */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES, roles);

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest().user,
);
