import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { DriverFixDto, LatLngDto } from '../../common/geo/geo.dto';
import { PresenceService } from './presence.service';

@ApiTags('driver')
@ApiBearerAuth()
@Roles('driver')
@Controller('driver')
export class DriverPresenceController {
  constructor(private readonly presence: PresenceService) {}

  @Post('online')
  @HttpCode(HttpStatus.NO_CONTENT)
  async online(@CurrentUser() u: AuthUser, @Body() dto: LatLngDto) {
    await this.presence.online(u.id, dto);
  }

  @Post('offline')
  @HttpCode(HttpStatus.NO_CONTENT)
  async offline(@CurrentUser() u: AuthUser) {
    await this.presence.offline(u.id);
  }

  /** REST fallback for driver:location (SPEC §7.3). */
  @Post('location')
  @HttpCode(HttpStatus.NO_CONTENT)
  async location(@CurrentUser() u: AuthUser, @Body() dto: DriverFixDto) {
    await this.presence.ingest(u.id, dto);
  }
}

@ApiTags('rider')
@ApiBearerAuth()
@Roles('rider')
@Controller('drivers')
export class NearbyDriversController {
  constructor(private readonly presence: PresenceService) {}

  @Get('nearby')
  nearby(@Query() q: LatLngDto) {
    return this.presence.nearbyForRider(q.lat, q.lng);
  }
}
