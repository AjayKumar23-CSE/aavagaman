import { Module } from '@nestjs/common';
import { FareModule } from '../fare/fare.module';
import { LocationModule } from '../location/location.module';
import { MatchingModule } from '../matching/matching.module';
import { PaymentsModule } from '../payments/payments.module';
import { RatingsService } from '../ratings/ratings.service';
import { ShareController } from '../share/share.controller';
import { ShareService } from '../share/share.service';
import { SosController } from '../sos/sos.controller';
import { SosService } from '../sos/sos.service';
import { CancellationService } from './cancellation.service';
import { DriverRidesController } from './driver-rides.controller';
import { DriverRidesService } from './driver-rides.service';
import { RidesController } from './rides.controller';
import { RidesService } from './rides.service';
import { TripService } from './trip.service';

@Module({
  imports: [MatchingModule, LocationModule, FareModule, PaymentsModule],
  controllers: [RidesController, DriverRidesController, SosController, ShareController],
  providers: [
    RidesService,
    DriverRidesService,
    TripService,
    CancellationService,
    RatingsService,
    SosService,
    ShareService,
  ],
  exports: [RidesService, DriverRidesService, CancellationService, TripService],
})
export class RidesModule {}
