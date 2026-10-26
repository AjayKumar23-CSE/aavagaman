import { Module } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';
import { CommonModule } from './common/common.module';
import { QueueModule } from './common/queue.module';
import { LOG_REDACT_PATHS } from './common/redact';
import { ConfigModule, loadConfig } from './config/config.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RideCoreModule } from './modules/rides/ride-core.module';
import { RoutingModule } from './modules/routing/routing.module';

/** Infrastructure shared by the API and the worker process. */
@Module({
  imports: [
    ConfigModule,
    LoggerModule.forRootAsync({
      useFactory: () => {
        const env = loadConfig();
        return {
          pinoHttp: {
            level: env.LOG_LEVEL,
            redact: { paths: LOG_REDACT_PATHS, censor: '[redacted]' },
            transport: env.NODE_ENV === 'development' ? { target: 'pino-pretty' } : undefined,
            autoLogging: { ignore: (req) => req.url === '/health' },
          },
        };
      },
    }),
    CommonModule,
    QueueModule,
    NotificationsModule,
    RoutingModule,
    RideCoreModule,
  ],
})
export class CoreModule {}
