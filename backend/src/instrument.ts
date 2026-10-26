// Must be imported before anything else so Sentry can instrument modules.
import * as Sentry from '@sentry/nestjs';
import { scrub } from './common/scrub';
import { loadConfig } from './config/config.module';

const env = loadConfig();
if (env.SENTRY_DSN) {
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.NODE_ENV,
    tracesSampleRate: 0,
    beforeSend(event) {
      if (event.request) {
        event.request.headers = scrub(event.request.headers);
        event.request.data = scrub(event.request.data);
        event.request.cookies = undefined;
      }
      event.extra = scrub(event.extra);
      return event;
    },
  });
}
