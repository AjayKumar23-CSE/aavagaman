import {
  Body,
  Controller,
  Get,
  Header,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Res,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { SettlementsService } from '../settlements/settlements.service';
import { AdminReportsService, toCsv } from './admin-reports.service';
import { AdminSosAuditService } from './admin-sos-audit.service';
import {
  AuditQuery,
  DailyReportQuery,
  GenerateSettlementsDto,
  SettleDto,
  SettlementsQuery,
  SosQuery,
} from './dto/admin.dto';

@ApiTags('admin: reports, settlements, sos, audit')
@ApiBearerAuth()
@Roles('admin')
@Controller('admin')
export class AdminMiscController {
  constructor(
    private readonly reports: AdminReportsService,
    private readonly settlements: SettlementsService,
    private readonly sosAudit: AdminSosAuditService,
  ) {}

  @Get('reports/daily')
  async daily(@Query() q: DailyReportQuery, @Res({ passthrough: true }) res: Response) {
    const rows = await this.reports.daily(q.from, q.to);
    if (q.format === 'csv') {
      res
        .type('text/csv')
        .setHeader('Content-Disposition', `attachment; filename="daily-${q.from}-to-${q.to}.csv"`);
      return toCsv(rows);
    }
    return { from: q.from, to: q.to, data: rows };
  }

  @Get('settlements')
  listSettlements(@Query() q: SettlementsQuery) {
    return this.settlements.list(q.week ? new Date(q.week + 'T12:00:00+05:30') : undefined);
  }

  @Post('settlements/generate')
  @HttpCode(HttpStatus.OK)
  generate(@Body() dto: GenerateSettlementsDto) {
    return this.settlements.generate(dto.week ? new Date(dto.week + 'T12:00:00+05:30') : undefined);
  }

  @Post('settlements/:id/settle')
  @HttpCode(HttpStatus.OK)
  settle(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SettleDto,
  ) {
    return this.settlements.settle(u.id, id, dto.reference);
  }

  @Get('sos')
  sos(@Query() q: SosQuery) {
    return this.sosAudit.listSos(q);
  }

  @Post('sos/:id/ack')
  @HttpCode(HttpStatus.OK)
  ack(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.sosAudit.ackSos(u.id, id);
  }

  @Get('audit')
  @Header('Cache-Control', 'no-store')
  audit(@Query() q: AuditQuery) {
    return this.sosAudit.listAudit(q);
  }
}
