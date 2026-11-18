import type { IncomingMessage } from 'node:http';
import path from 'node:path';
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
  // Optional: the built admin panel under /admin (D-060). Mounted before helmet because the
  // panel's page loads map tiles and document previews from other hosts, which the API's CSP
  // forbids; API responses keep their headers.
  if (env.ADMIN_STATIC_DIR) {
    const dir = path.resolve(env.ADMIN_STATIC_DIR);
    app.use('/admin', express.static(dir));
    app.use(/^\/admin(\/.*)?$/, (_req: express.Request, res: express.Response) =>
      res.sendFile(path.join(dir, 'index.html')),
    );
  }
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
