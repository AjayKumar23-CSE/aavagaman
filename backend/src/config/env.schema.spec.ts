import { validateEnv } from './env.schema';

const base = {
  API_BASE_URL: 'http://localhost:3000',
  ADMIN_ORIGIN: 'http://localhost:5173',
  DATABASE_URL: 'postgresql://ride:ride@localhost:5432/ride',
  REDIS_URL: 'redis://localhost:6379',
  JWT_ACCESS_SECRET: 'a',
  JWT_REFRESH_SECRET: 'b',
  OTP_PEPPER: 'p',
  OSRM_BASE_URL: 'http://localhost:5000',
};

describe('validateEnv', () => {
  it('accepts a minimal config and applies defaults', () => {
    const env = validateEnv(base);
    expect(env.PORT).toBe(3000);
    expect(env.OFFER_TIMEOUT_SECONDS).toBe(20);
    expect(env.OFFER_BATCH_SIZE).toBe(5);
    expect(env.MAX_OFFER_ROUNDS_PER_RIDE).toBe(3);
    expect(env.ENABLE_DOCS).toBe(false);
  });

  it('treats empty strings as missing and names every missing variable', () => {
    expect(() => validateEnv({ ...base, DATABASE_URL: '', REDIS_URL: undefined })).toThrow(
      /DATABASE_URL[\s\S]*REDIS_URL/,
    );
  });

  it('splits ADMIN_ORIGIN into a list of origins', () => {
    expect(validateEnv(base).ADMIN_ORIGIN).toEqual(['http://localhost:5173']);
    expect(
      validateEnv({ ...base, ADMIN_ORIGIN: 'https://admin.example.com, http://localhost:5173' })
        .ADMIN_ORIGIN,
    ).toEqual(['https://admin.example.com', 'http://localhost:5173']);
    expect(() => validateEnv({ ...base, ADMIN_ORIGIN: ' , ' })).toThrow(/ADMIN_ORIGIN/);
  });

  it('coerces numeric variables', () => {
    expect(validateEnv({ ...base, PORT: '8080' }).PORT).toBe(8080);
    expect(() => validateEnv({ ...base, PORT: 'abc' })).toThrow(/PORT/);
  });

  it('requires MSG91 in production', () => {
    expect(() => validateEnv({ ...base, NODE_ENV: 'production' })).toThrow(/MSG91_AUTH_KEY/);
    expect(
      validateEnv({ ...base, NODE_ENV: 'production', MSG91_AUTH_KEY: 'k', MSG91_TEMPLATE_ID: 't' })
        .NODE_ENV,
    ).toBe('production');
  });

  it('rejects the OTP bypass in production', () => {
    expect(() =>
      validateEnv({ ...base, NODE_ENV: 'production', OTP_DEV_BYPASS_CODE: '123456' }),
    ).toThrow(/OTP_DEV_BYPASS_CODE/);
    expect(
      validateEnv({ ...base, NODE_ENV: 'development', OTP_DEV_BYPASS_CODE: '123456' })
        .OTP_DEV_BYPASS_CODE,
    ).toBe('123456');
  });
});
