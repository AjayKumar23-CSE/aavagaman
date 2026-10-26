import { Module } from '@nestjs/common';
import { MatchingModule } from '../matching/matching.module';
import { DriverPresenceController, NearbyDriversController } from './location.controller';
import { LocationModule } from './location.module';
import { PresenceService } from './presence.service';

@Module({
  imports: [LocationModule, MatchingModule],
  controllers: [DriverPresenceController, NearbyDriversController],
  providers: [PresenceService],
  exports: [PresenceService],
})
export class PresenceModule {}
