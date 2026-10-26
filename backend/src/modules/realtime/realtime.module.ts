import { Module } from '@nestjs/common';
import { AdminModule } from '../admin/admin.module';
import { MatchingModule } from '../matching/matching.module';
import { PresenceModule } from '../location/presence.module';
import { RidesModule } from '../rides/rides.module';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [PresenceModule, MatchingModule, RidesModule, AdminModule],
  providers: [RealtimeGateway],
})
export class RealtimeModule {}
