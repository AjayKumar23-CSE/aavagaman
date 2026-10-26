import { Global, Inject, Module, OnModuleInit } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { RideEventsService } from './ride-events.service';
import { RideTransitionService } from './ride-transition.service';
import { RidePublisher } from './ride.publisher';
import { callingPolicyFor, configureCalling } from './ride.presenter';
import { RideRepository } from './ride.repository';
import { TracksService } from './tracks.service';

/** Ride persistence and fan-out shared by the API and the worker. */
@Global()
@Module({
  providers: [
    RideRepository,
    RidePublisher,
    RideEventsService,
    RideTransitionService,
    TracksService,
    RealtimeEmitter,
  ],
  exports: [
    RideRepository,
    RidePublisher,
    RideEventsService,
    RideTransitionService,
    TracksService,
    RealtimeEmitter,
  ],
})
export class RideCoreModule implements OnModuleInit {
  constructor(@Inject(APP_CONFIG) private readonly env: Env) {}

  /** Both the API and the worker build ride payloads, so the phone-masking rule (D-058) is set here. */
  onModuleInit() {
    configureCalling(callingPolicyFor(this.env));
  }
}
