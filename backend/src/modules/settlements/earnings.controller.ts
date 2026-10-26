import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { SettlementsService } from './settlements.service';

export class EarningsQuery {
  @ApiPropertyOptional({ enum: ['today', 'week'], default: 'today' })
  @IsOptional()
  @IsIn(['today', 'week'])
  period: 'today' | 'week' = 'today';
}

@ApiTags('driver')
@ApiBearerAuth()
@Roles('driver')
@Controller('driver/earnings')
export class EarningsController {
  constructor(private readonly settlements: SettlementsService) {}

  @Get()
  earnings(@CurrentUser() u: AuthUser, @Query() q: EarningsQuery) {
    return this.settlements.earnings(u.id, q.period);
  }
}
