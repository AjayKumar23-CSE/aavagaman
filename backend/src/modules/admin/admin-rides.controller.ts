import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { CancellationService } from '../rides/cancellation.service';
import { AdminCancelDto } from '../rides/dto/trip.dto';
import { presentRide } from '../rides/ride.presenter';
import { AdminRidesService } from './admin-rides.service';
import { AdjustFareDto, ListRidesQuery, ReassignDto } from './dto/admin.dto';

@ApiTags('admin: rides')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin/rides')
export class AdminRidesController {
  constructor(
    private readonly cancellation: CancellationService,
    private readonly svc: AdminRidesService,
  ) {}

  @Get()
  list(@Query() q: ListRidesQuery) {
    return this.svc.list(q);
  }

  @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.svc.detail(id);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  async cancel(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdminCancelDto,
  ) {
    return presentRide(await this.cancellation.byAdmin(u.id, id, dto.reason), 'admin');
  }

  @Post(':id/reassign')
  @HttpCode(HttpStatus.OK)
  reassign(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReassignDto,
  ) {
    return this.svc.reassign(u.id, id, dto);
  }

  @Post(':id/adjust-fare')
  @HttpCode(HttpStatus.OK)
  adjustFare(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AdjustFareDto,
  ) {
    return this.svc.adjustFare(u.id, id, dto);
  }

  @Post(':id/mark-cash')
  @HttpCode(HttpStatus.OK)
  markCash(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.svc.markCash(u.id, id);
  }
}
