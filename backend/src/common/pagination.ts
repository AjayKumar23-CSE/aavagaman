import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';

/** `?page=&limit=` on every list endpoint (SPEC §7; limit max 100). */
export class PageQuery {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @ApiPropertyOptional({ default: 20, minimum: 1, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit = 20;
}

export interface Page<T> {
  data: T[];
  page: number;
  limit: number;
  total: number;
}

export const skipTake = (q: PageQuery) => ({ skip: (q.page - 1) * q.limit, take: q.limit });
