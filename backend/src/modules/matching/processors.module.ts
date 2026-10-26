import { Module } from '@nestjs/common';
import { PaymentsModule } from '../payments/payments.module';
import { SettlementsModule } from '../settlements/settlements.module';
import { MatchingModule } from './matching.module';
import { MatchingProcessor } from './matching.processor';
import { SystemProcessor } from './system.processor';

/** BullMQ consumers. Loaded by the worker process only (and by e2e tests). */
@Module({
  imports: [MatchingModule, PaymentsModule, SettlementsModule],
  providers: [MatchingProcessor, SystemProcessor],
})
export class ProcessorsModule {}
