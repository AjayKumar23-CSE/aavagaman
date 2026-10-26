/** Paths scrubbed from logs (SPEC §16: phone numbers and tokens never logged). */
export const LOG_REDACT_PATHS = [
  'req.headers.authorization',
  'req.headers.cookie',
  '*.phone',
  '*.token',
  '*.access_token',
  '*.refresh_token',
  '*.fcm_token',
  '*.code',
  '*.otp',
  '*.password',
];
