import { Module } from '@nestjs/common';
import { EarningsController } from './earnings.controller';
import { SettlementsService } from './settlements.service';

@Module({
  controllers: [EarningsController],
  providers: [SettlementsService],
  exports: [SettlementsService],
})
export class SettlementsModule {}
