import { Controller, Get, Res } from '@nestjs/common';
import { ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { Public } from '../../common/auth/decorators';
import { HealthService } from './health.service';

@ApiTags('system')
@Public()
@Controller('health')
export class HealthController {
  constructor(private readonly health: HealthService) {}

  @Get()
  @ApiOkResponse({
    description: '{status:"ok", db:true, redis:true, osrm:true}; 503 if db or redis is down',
  })
  async get(@Res({ passthrough: true }) res: Response) {
    const report = await this.health.check();
    if (report.status !== 'ok') res.status(503);
    return report;
  }
}
