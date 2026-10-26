import type { UserRole } from '@prisma/client';

/** Claims carried in the access JWT and attached to `req.user`. */
export interface AuthUser {
  id: string;
  role: UserRole;
}
