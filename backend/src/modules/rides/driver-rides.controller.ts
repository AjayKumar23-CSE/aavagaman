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
import { PageQuery } from '../../common/pagination';
import { RatingsService } from '../ratings/ratings.service';
import { CancellationService } from './cancellation.service';
import { DriverRidesService } from './driver-rides.service';
import { ArrivedDto, CompleteDto, DriverCancelDto, RatingDto, StartDto } from './dto/trip.dto';
import { presentRide } from './ride.presenter';
import { TripService } from './trip.service';

@ApiTags('driver')
@ApiBearerAuth()
@Roles('driver')
@Controller('driver/rides')
export class DriverRidesController {
  constructor(
    private readonly rides: DriverRidesService,
    private readonly trip: TripService,
    private readonly cancellation: CancellationService,
    private readonly ratings: RatingsService,
  ) {}

  @Get()
  list(@CurrentUser() u: AuthUser, @Query() q: PageQuery) {
    return this.rides.list(u.id, q);
  }

  @Get('active')
  active(@CurrentUser() u: AuthUser) {
    return this.rides.active(u.id);
  }

  @Post(':id/accept')
  @HttpCode(HttpStatus.OK)
  accept(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.rides.accept(u.id, id);
  }

  @Post(':id/reject')
  @HttpCode(HttpStatus.NO_CONTENT)
  async reject(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.rides.reject(u.id, id);
  }

  @Post(':id/arrived')
  @HttpCode(HttpStatus.OK)
  async arrived(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ArrivedDto,
  ) {
    return presentRide(await this.trip.arrived(u.id, id, dto), 'driver');
  }

  @Post(':id/start')
  @HttpCode(HttpStatus.OK)
  async start(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: StartDto,
  ) {
    return presentRide(await this.trip.start(u.id, id, dto), 'driver');
  }

  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  async complete(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CompleteDto,
  ) {
    return presentRide(await this.trip.complete(u.id, id, dto), 'driver');
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  async cancel(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DriverCancelDto,
  ) {
    return presentRide(await this.cancellation.byDriver(u.id, id, dto.reason), 'driver');
  }

  @Post(':id/cash-collected')
  @HttpCode(HttpStatus.OK)
  async cashCollected(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return presentRide(await this.trip.cashCollected(id, 'driver', u.id), 'driver');
  }

  @Post(':id/rating')
  rate(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RatingDto) {
    return this.ratings.rate(u.id, 'driver', id, dto.stars, dto.comment);
  }
}
