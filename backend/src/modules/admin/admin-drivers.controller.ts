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
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { AdminDriversService } from './admin-drivers.service';
import { ListDriversQuery, NoteDto, ReasonDto, UpdateVehicleDto } from './dto/admin-drivers.dto';

@ApiTags('admin: drivers')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin/drivers')
export class AdminDriversController {
  constructor(private readonly svc: AdminDriversService) {}

  @Get()
  list(@Query() q: ListDriversQuery) {
    return this.svc.list(q);
  }

  @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.svc.detail(id);
  }

  @Post(':id/approve')
  @HttpCode(HttpStatus.OK)
  approve(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() b: NoteDto) {
    return this.svc.transition(u.id, id, 'approve', b.note);
  }

  @Post(':id/reject')
  @HttpCode(HttpStatus.OK)
  reject(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() b: ReasonDto) {
    return this.svc.transition(u.id, id, 'reject', b.note);
  }

  @Post(':id/suspend')
  @HttpCode(HttpStatus.OK)
  suspend(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() b: ReasonDto,
  ) {
    return this.svc.transition(u.id, id, 'suspend', b.note);
  }

  @Post(':id/reinstate')
  @HttpCode(HttpStatus.OK)
  reinstate(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() b: NoteDto,
  ) {
    return this.svc.transition(u.id, id, 'reinstate', b.note);
  }

  @Post(':id/documents/:docId/approve')
  @HttpCode(HttpStatus.OK)
  approveDoc(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('docId', ParseUUIDPipe) docId: string,
    @Body() b: NoteDto,
  ) {
    return this.svc.reviewDocument(u.id, id, docId, 'approved', b.note);
  }

  @Post(':id/documents/:docId/reject')
  @HttpCode(HttpStatus.OK)
  rejectDoc(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('docId', ParseUUIDPipe) docId: string,
    @Body() b: ReasonDto,
  ) {
    return this.svc.reviewDocument(u.id, id, docId, 'rejected', b.note);
  }

  @Patch(':id/vehicle')
  updateVehicle(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateVehicleDto,
  ) {
    return this.svc.updateVehicle(u.id, id, dto);
  }
}
