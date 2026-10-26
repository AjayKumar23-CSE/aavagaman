import type { User } from '@prisma/client';

/** Public JSON shape of a user (snake_case, SPEC §7). */
export function presentUser(u: User) {
  return {
    id: u.id,
    phone: u.phone,
    name: u.name,
    email: u.email,
    role: u.role,
    status: u.status,
    rating_avg: u.ratingAvg === null ? null : Number(u.ratingAvg),
    rating_count: u.ratingCount ?? 0,
    created_at: u.createdAt,
  };
}

export type UserView = ReturnType<typeof presentUser>;
