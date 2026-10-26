import { Controller, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { CallsService } from './calls.service';

@ApiTags('rider')
@ApiBearerAuth()
@Roles('rider')
@Controller('rides/:id/call')
export class RiderCallsController {
  constructor(private readonly calls: CallsService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Call the driver through the Aavagaman number (rings you first, then the driver)' })
  call(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.calls.request(u.id, 'rider', id);
  }
}

@ApiTags('driver')
@ApiBearerAuth()
@Roles('driver')
@Controller('driver/rides/:id/call')
export class DriverCallsController {
  constructor(private readonly calls: CallsService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Call the rider through the Aavagaman number (rings you first, then the rider)' })
  call(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.calls.request(u.id, 'driver', id);
  }
}
