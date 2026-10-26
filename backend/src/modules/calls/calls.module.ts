import { Module } from '@nestjs/common';
import { CALL_PROVIDER, CallProviderFactory } from './call.provider';
import { CallWebhooksController } from './call-webhooks.controller';
import { DriverCallsController, RiderCallsController } from './calls.controller';
import { CallsService } from './calls.service';

/** Masked calling (D-058): rider ↔ driver calls bridged through the Aavagaman number. */
@Module({
  controllers: [RiderCallsController, DriverCallsController, CallWebhooksController],
  providers: [
    CallProviderFactory,
    { provide: CALL_PROVIDER, useFactory: (f: CallProviderFactory) => f.create(), inject: [CallProviderFactory] },
    CallsService,
  ],
  exports: [CallsService],
})
export class CallsModule {}
