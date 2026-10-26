import type { IncomingMessage } from 'node:http';
import { RequestMethod, ValidationPipe } from '@nestjs/common';
import { NestExpressApplication } from '@nestjs/platform-express';
import express from 'express';
import helmet from 'helmet';
import { HttpExceptionFilter } from './common/http-exception.filter';
import { RedisIoAdapter } from './modules/realtime/redis-io.adapter';
import type { Env } from './config/env.schema';

/** HTTP pipeline shared by main.ts and the e2e tests, so tests exercise the real setup. */
export function configureApp(app: NestExpressApplication, env: Env) {
  // Keep the raw bytes: Razorpay webhook signatures are computed over the exact body (SPEC §15).
  app.use(
    express.json({
      limit: '1mb',
      verify: (req: IncomingMessage & { rawBody?: Buffer }, _res, buf) => {
        req.rawBody = buf;
      },
    }),
  );
  // Exotel posts call outcomes form-encoded (D-058).
  app.use(express.urlencoded({ extended: false, limit: '100kb' }));
  // Behind Caddy on the Docker network: trust private-range proxies for req.ip.
  app.set('trust proxy', 'loopback, uniquelocal');
  app.use(helmet());
  app.enableCors({ origin: env.ADMIN_ORIGIN, credentials: true });
  app.setGlobalPrefix('v1', {
    exclude: [
      { path: 'health', method: RequestMethod.GET },
      { path: 'metrics', method: RequestMethod.GET },
    ],
  });
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useWebSocketAdapter(new RedisIoAdapter(app, env.REDIS_URL));
  app.enableShutdownHooks();
  return app;
}
