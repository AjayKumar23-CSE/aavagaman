import { z } from 'zod';

// Empty strings in .env mean "not set".
const optional = z.preprocess((v) => (v === '' ? undefined : v), z.string().optional());
const required = z.preprocess((v) => (v === '' ? undefined : v), z.string().min(1));
const int = (def: number) => z.coerce.number().int().positive().default(def);

export const envSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: int(3000),
    API_BASE_URL: required,
    // Browser origins allowed to call the API and the /rt socket (CORS); comma-separated for several.
    ADMIN_ORIGIN: required
      .transform((v) => v.split(',').map((o) => o.trim()).filter(Boolean))
      .refine((v) => v.length > 0, { message: 'must list at least one origin' }),
    ENABLE_DOCS: z
      .preprocess((v) => (v === '' ? undefined : v), z.enum(['true', 'false']).default('false'))
      .transform((v) => v === 'true'),

    DATABASE_URL: required,
    REDIS_URL: required,

    JWT_ACCESS_SECRET: required,
    JWT_REFRESH_SECRET: required,
    JWT_ACCESS_TTL: z.string().default('15m'),
    JWT_REFRESH_TTL: z.string().default('90d'),

    OTP_TTL_SECONDS: int(300),
    OTP_MAX_ATTEMPTS: int(3),
    OTP_DEV_BYPASS_CODE: optional,
    OTP_PEPPER: required,

    MSG91_AUTH_KEY: optional,
    MSG91_TEMPLATE_ID: optional,
    MSG91_SENDER_ID: optional,
    MSG91_ALERT_TEMPLATE_ID: optional,

    FCM_SERVICE_ACCOUNT_JSON_BASE64: optional,

    GOOGLE_MAPS_SERVER_KEY: optional,
    OSRM_BASE_URL: required,

    RAZORPAY_KEY_ID: optional,
    RAZORPAY_KEY_SECRET: optional,
    RAZORPAY_WEBHOOK_SECRET: optional,
    RAZORPAY_BASE_URL: z.string().url().default('https://api.razorpay.com'),
    PAYMENT_CASH_FALLBACK_SECONDS: int(300),
    PAYMENT_POLL_INTERVAL_SECONDS: int(60),
    PAYMENT_POLL_MAX_HOURS: int(24),

    // Masked calling (D-058): `none` = apps open the phone dialer with the real number after
    // ARRIVED (SPEC §16); `exotel` bridges both parties through EXOTEL_CALLER_ID and never
    // reveals a number; `stub` behaves like a provider without placing calls (dev/test).
    CALL_PROVIDER: z
      .preprocess((v) => (v === '' ? undefined : v), z.enum(['none', 'stub', 'exotel']).default('none'))
      .pipe(z.enum(['none', 'stub', 'exotel'])),
    EXOTEL_SID: optional,
    EXOTEL_API_KEY: optional,
    EXOTEL_API_TOKEN: optional,
    /** api.exotel.com (Singapore) or api.in.exotel.com (Mumbai), as shown in the Exotel dashboard. */
    EXOTEL_SUBDOMAIN: z.string().min(1).default('api.exotel.com'),
    /** The ExoPhone (virtual number, E.164) both parties see. */
    EXOTEL_CALLER_ID: optional,
    /** Public URL Exotel posts call outcomes to, e.g. https://api.example.com/v1/webhooks/calls/exotel */
    CALL_STATUS_CALLBACK_URL: optional,
    /** When set, the callback must carry `?token=<this>`; keep it secret. */
    CALL_STATUS_SECRET: optional,
    CALL_MAX_SECONDS: int(600),
    /** A caller may bridge once per ride within this window (abuse guard). */
    CALL_MIN_INTERVAL_SECONDS: int(15),

    /** Empty for Amazon S3; the R2 (or other S3-compatible) URL otherwise. */
    S3_ENDPOINT: optional,
    /** The bucket's region for Amazon S3 (e.g. ap-south-1); R2 uses `auto`. */
    S3_REGION: z.string().min(1).default('auto'),
    S3_BUCKET: optional,
    S3_ACCESS_KEY_ID: optional,
    S3_SECRET_ACCESS_KEY: optional,
    S3_PUBLIC_BASE_URL: optional,

    SENTRY_DSN: optional,
    /** Bearer token for GET /metrics; endpoint disabled when unset. */
    METRICS_TOKEN: optional,
    TRACK_RETENTION_DAYS: int(30),
    LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),

    DEFAULT_SEARCH_RADIUS_KM: int(3),
    DEFAULT_SEARCH_RADIUS_RETRY_KM: int(5),
    OFFER_TIMEOUT_SECONDS: int(20),
    // Broadcast matching (D-055): drivers asked at once per round, rounds before NO_DRIVER.
    OFFER_BATCH_SIZE: int(5),
    MAX_OFFER_ROUNDS_PER_RIDE: int(3),
    MATCHING_DEADLINE_SECONDS: int(120),
    DRIVER_HEARTBEAT_TTL_SECONDS: int(15),
    HEARTBEAT_SWEEP_SECONDS: int(10),
    // Trip rules (SPEC §7.3, §9.5, §9.6)
    ARRIVAL_RADIUS_M: int(300),
    FREE_CANCEL_WINDOW_SECONDS: int(120),
    NO_SHOW_WAIT_SECONDS: int(300),
    DRIVER_CANCEL_SUSPEND_AT: int(3),
    OTP_START_MAX_ATTEMPTS: int(3),
    OTP_SMS_FALLBACK_SECONDS: int(60),
  })
  // The OTP bypass must never be active in production.
  .refine((e) => !(e.NODE_ENV === 'production' && e.OTP_DEV_BYPASS_CODE), {
    message: 'OTP_DEV_BYPASS_CODE must be empty when NODE_ENV=production',
    path: ['OTP_DEV_BYPASS_CODE'],
  })
  // Without MSG91 in production, OTPs would silently never be delivered.
  .refine((e) => e.NODE_ENV !== 'production' || (e.MSG91_AUTH_KEY && e.MSG91_TEMPLATE_ID), {
    message: 'MSG91_AUTH_KEY and MSG91_TEMPLATE_ID are required when NODE_ENV=production',
    path: ['MSG91_AUTH_KEY'],
  });

export type Env = z.infer<typeof envSchema>;

export function validateEnv(raw: NodeJS.ProcessEnv): Env {
  const result = envSchema.safeParse(raw);
  if (!result.success) {
    const lines = result.error.issues.map(
      (i) => `  - ${i.path.join('.') || '(root)'}: ${i.message}`,
    );
    throw new Error(`Invalid environment configuration:\n${lines.join('\n')}`);
  }
  return result.data;
}
