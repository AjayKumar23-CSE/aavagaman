import { Body, Controller, Headers, HttpCode, HttpStatus, Logger, Post, Req } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { AppException } from '../../common/app.exception';
import { Public } from '../../common/auth/decorators';
import { PaymentsService } from './payments.service';
import { RazorpayClient, RazorpayPayment } from './razorpay.client';

interface RazorpayWebhook {
  event: string;
  payload?: { payment?: { entity?: RazorpayPayment } };
}

@ApiTags('webhooks')
@Public()
@Controller('webhooks')
export class WebhooksController {
  private readonly logger = new Logger(WebhooksController.name);

  constructor(
    private readonly payments: PaymentsService,
    private readonly razorpay: RazorpayClient,
  ) {}

  /** SPEC §7.5: verify X-Razorpay-Signature over the raw body; idempotent on gateway_payment_id. */
  @Post('razorpay')
  @HttpCode(HttpStatus.OK)
  async razorpayHook(
    @Req() req: Request & { rawBody?: Buffer },
    @Headers('x-razorpay-signature') signature = '',
    @Body() body: RazorpayWebhook,
  ) {
    if (!req.rawBody || !this.razorpay.verifyWebhook(req.rawBody, signature)) {
      throw new AppException(
        'SIGNATURE_INVALID',
        'Webhook signature invalid',
        HttpStatus.BAD_REQUEST,
      );
    }
    const entity = body.payload?.payment?.entity;
    const result = entity ? await this.payments.handleWebhook(body.event, entity) : 'no-payment';
    this.logger.log(`razorpay ${body.event}: ${result}`);
    return { ok: true, result };
  }
}
