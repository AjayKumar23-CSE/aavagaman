import { Module } from '@nestjs/common';
import { LocationModule } from '../location/location.module';
import { MatchingService } from './matching.service';

@Module({
  imports: [LocationModule],
  providers: [MatchingService],
  exports: [MatchingService],
})
export class MatchingModule {}
