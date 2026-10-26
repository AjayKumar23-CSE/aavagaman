import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { AdminConfigService } from './admin-config.service';
import {
  FareConfigDto,
  FarePreviewDto,
  ServiceAreaDto,
  ServiceAreaPatchDto,
} from './dto/admin.dto';

@ApiTags('admin: config')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin')
export class AdminConfigController {
  constructor(private readonly svc: AdminConfigService) {}

  @Get('fare-config')
  listFareConfigs() {
    return this.svc.listFareConfigs();
  }

  @Post('fare-config')
  createFareConfig(@CurrentUser() u: AuthUser, @Body() dto: FareConfigDto) {
    return this.svc.createFareConfig(u.id, dto);
  }

  @Post('fare-config/preview')
  @HttpCode(HttpStatus.OK)
  preview(@Body() dto: FarePreviewDto) {
    return this.svc.preview(dto);
  }

  @Get('service-areas')
  listAreas() {
    return this.svc.listAreas();
  }

  @Post('service-areas')
  createArea(@CurrentUser() u: AuthUser, @Body() dto: ServiceAreaDto) {
    return this.svc.createArea(u.id, dto);
  }

  @Patch('service-areas/:id')
  patchArea(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ServiceAreaPatchDto,
  ) {
    return this.svc.patchArea(u.id, id, dto);
  }
}
