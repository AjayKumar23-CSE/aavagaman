import { Global, Module } from '@nestjs/common';
import { GeofenceService } from '../geofence/geofence.service';
import { RoutingService } from './routing.service';

@Global()
@Module({
  providers: [RoutingService, GeofenceService],
  exports: [RoutingService, GeofenceService],
})
export class RoutingModule {}
