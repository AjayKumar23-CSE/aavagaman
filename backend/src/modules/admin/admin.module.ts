import { Module } from '@nestjs/common';
import { CallsModule } from '../calls/calls.module';
import { AuthModule } from '../auth/auth.module';
import { LocationModule } from '../location/location.module';
import { RidesModule } from '../rides/rides.module';
import { SettlementsModule } from '../settlements/settlements.module';
import { AdminConfigController } from './admin-config.controller';
import { AdminConfigService } from './admin-config.service';
import { AdminDashboardController } from './admin-dashboard.controller';
import { AdminDriversController } from './admin-drivers.controller';
import { AdminDriversService } from './admin-drivers.service';
import { AdminMiscController } from './admin-misc.controller';
import { AdminReportsService } from './admin-reports.service';
import { AdminRidersController } from './admin-riders.controller';
import { AdminRidersService } from './admin-riders.service';
import { AdminRidesController } from './admin-rides.controller';
import { AdminRidesService } from './admin-rides.service';
import { AdminSettingsController } from './admin-settings.controller';
import { AdminSosAuditService } from './admin-sos-audit.service';
import { LiveService } from './live.service';

@Module({
  imports: [CallsModule, AuthModule, LocationModule, RidesModule, SettlementsModule],
  controllers: [
    AdminDriversController,
    AdminRidesController,
    AdminRidersController,
    AdminDashboardController,
    AdminConfigController,
    AdminMiscController,
    AdminSettingsController,
  ],
  providers: [
    AdminDriversService,
    AdminRidesService,
    AdminRidersService,
    AdminConfigService,
    AdminReportsService,
    AdminSosAuditService,
    LiveService,
  ],
  exports: [LiveService],
})
export class AdminModule {}
