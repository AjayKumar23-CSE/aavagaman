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
import { CancelRideDto, CreateRideDto } from './dto/ride.dto';
import { RatingDto } from './dto/trip.dto';
import { RidesService } from './rides.service';

@ApiTags('rider')
@ApiBearerAuth()
@Roles('rider')
@Controller('rides')
export class RidesController {
  constructor(
    private readonly rides: RidesService,
    private readonly ratings: RatingsService,
  ) {}

  @Post()
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateRideDto) {
    return this.rides.create(u.id, dto);
  }

  @Get()
  list(@CurrentUser() u: AuthUser, @Query() q: PageQuery) {
    return this.rides.list(u.id, q);
  }

  @Get('active')
  active(@CurrentUser() u: AuthUser) {
    return this.rides.active(u.id);
  }

  @Get(':id')
  get(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.rides.get(u.id, id);
  }

  @Get(':id/receipt')
  receipt(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.rides.receipt(u.id, id);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CancelRideDto,
  ) {
    return this.rides.cancel(u.id, id, dto);
  }

  @Post(':id/rating')
  rate(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RatingDto) {
    return this.ratings.rate(u.id, 'rider', id, dto.stars, dto.comment);
  }
}
