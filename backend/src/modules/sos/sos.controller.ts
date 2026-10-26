import { Body, Controller, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { SosDto } from '../rides/dto/trip.dto';
import { SosService } from './sos.service';

/** Rider or driver of the ride (D-030). */
@ApiTags('safety')
@ApiBearerAuth()
@Controller('rides')
export class SosController {
  constructor(private readonly sos: SosService) {}

  @Post(':id/sos')
  raise(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SosDto) {
    return this.sos.raise(u, id, dto);
  }
}
