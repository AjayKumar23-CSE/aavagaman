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
import { AdminRidersService } from './admin-riders.service';
import { ListRidersQuery, ReasonBodyDto } from './dto/admin.dto';
import { NoteDto } from './dto/admin-drivers.dto';

@ApiTags('admin: riders')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin/riders')
export class AdminRidersController {
  constructor(private readonly svc: AdminRidersService) {}

  @Get()
  list(@Query() q: ListRidersQuery) {
    return this.svc.list(q);
  }

  @Post(':id/block')
  @HttpCode(HttpStatus.OK)
  block(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ReasonBodyDto,
  ) {
    return this.svc.setBlocked(u.id, id, true, dto.reason);
  }

  @Post(':id/unblock')
  @HttpCode(HttpStatus.OK)
  unblock(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: NoteDto,
  ) {
    return this.svc.setBlocked(u.id, id, false, dto.note);
  }
}
