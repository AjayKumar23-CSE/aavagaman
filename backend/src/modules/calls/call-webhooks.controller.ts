import { Body, Controller, HttpCode, HttpStatus, Inject, Logger, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { timingSafeEqual } from 'node:crypto';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { Public } from '../../common/auth/decorators';
import { mapExotelStatus } from './call.provider';
import { CallsService } from './calls.service';

/** Exotel posts these (form-encoded) when the call ends. Field names per their StatusCallback docs. */
interface ExotelStatusBody {
  CallSid?: string;
  Status?: string;
  ConversationDuration?: string | number;
  Duration?: string | number;
}

const same = (a: string, b: string) => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

@ApiTags('webhooks')
@Public()
@Controller('webhooks/calls')
export class CallWebhooksController {
  private readonly logger = new Logger(CallWebhooksController.name);

  constructor(
    private readonly calls: CallsService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  @Post('exotel')
  @HttpCode(HttpStatus.OK)
  async exotel(@Query('token') token: string | undefined, @Body() body: ExotelStatusBody) {
    const secret = this.config.CALL_STATUS_SECRET;
    if (secret && !same(token ?? '', secret)) {
      throw new AppException('SIGNATURE_INVALID', 'Bad callback token', HttpStatus.UNAUTHORIZED);
    }
    if (!body?.CallSid) return { ok: true, result: 'ignored' };
    const raw = body.ConversationDuration ?? body.Duration;
    const duration = raw === undefined || raw === '' ? undefined : Number(raw);
    const known = await this.calls.recordStatus(
      body.CallSid,
      mapExotelStatus(body.Status),
      Number.isFinite(duration) ? duration : undefined,
    );
    this.logger.log(`exotel ${body.CallSid} ${body.Status}: ${known ? 'recorded' : 'unknown call'}`);
    return { ok: true, result: known ? 'recorded' : 'unknown' };
  }
}
