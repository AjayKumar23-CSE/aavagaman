import { Module } from '@nestjs/common';
import { LocationModule } from '../location/location.module';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { RazorpayClient } from './razorpay.client';
import { WebhooksController } from './webhooks.controller';

@Module({
  imports: [LocationModule],
  controllers: [PaymentsController, WebhooksController],
  providers: [PaymentsService, RazorpayClient],
  exports: [PaymentsService, RazorpayClient],
})
export class PaymentsModule {}
