import { randomBytes } from 'node:crypto';
import { Controller, Get, Headers, Inject, Param, Res } from '@nestjs/common';
import { ApiOkResponse, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { Public } from '../../common/auth/decorators';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { sharePageHtml } from './share.page';
import { ShareService } from './share.service';

/**
 * GET /v1/share/:token — public. Browsers (Accept: text/html) get the tracking page,
 * which polls the same URL for JSON (SPEC §7.2, §20 Phase 3 "endpoint and page"; D-029).
 */
@ApiTags('public')
@Public()
@Controller('share')
export class ShareController {
  constructor(
    private readonly share: ShareService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  @Get(':token')
  @ApiOkResponse({
    description: '{status, driver_name, vehicle, current_location, eta_s, pickup, drop}',
  })
  async view(@Param('token') token: string, @Headers('accept') accept = '', @Res() res: Response) {
    if (/\btext\/html\b/.test(accept) && !/\bapplication\/json\b/.test(accept)) {
      const nonce = randomBytes(16).toString('base64');
      res
        .setHeader(
          'Content-Security-Policy',
          `default-src 'self'; script-src 'nonce-${nonce}' https://unpkg.com; style-src 'self' 'unsafe-inline' https://unpkg.com; ` +
            `img-src 'self' data: https://*.tile.openstreetmap.org https://unpkg.com; connect-src 'self'`,
        )
        .type('html')
        .send(
          sharePageHtml(`${this.config.API_BASE_URL}/v1/share/${encodeURIComponent(token)}`, nonce),
        );
      return;
    }
    res.json(await this.share.view(token));
  }
}
