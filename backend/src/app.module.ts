import { Module } from '@nestjs/common';
import { CoreModule } from './core.module';
import { AdminModule } from './modules/admin/admin.module';
import { AuthModule } from './modules/auth/auth.module';
import { CallsModule } from './modules/calls/calls.module';
import { DriversModule } from './modules/drivers/drivers.module';
import { FareModule } from './modules/fare/fare.module';
import { HealthModule } from './modules/health/health.module';
import { PresenceModule } from './modules/location/presence.module';
import { LegalModule } from './modules/legal/legal.module';
import { MetricsModule } from './modules/metrics/metrics.module';
import { PaymentsModule } from './modules/payments/payments.module';
import { SettlementsModule } from './modules/settlements/settlements.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { RidesModule } from './modules/rides/rides.module';
import { UsersModule } from './modules/users/users.module';

@Module({
  imports: [
    CoreModule,
    AuthModule,
    HealthModule,
    MetricsModule,
    LegalModule,
    UsersModule,
    DriversModule,
    AdminModule,
    FareModule,
    PresenceModule,
    RidesModule,
    PaymentsModule,
    CallsModule,
    SettlementsModule,
    RealtimeModule,
  ],
})
export class AppModule {}
