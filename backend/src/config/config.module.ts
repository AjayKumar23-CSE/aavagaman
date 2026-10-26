import { existsSync, readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';
import { Global, Module } from '@nestjs/common';
import { Env, validateEnv } from './env.schema';

export const APP_CONFIG = Symbol('APP_CONFIG');

let cached: Env | undefined;

/**
 * Loads .env (if present) into *this* process.env without overriding variables
 * that are already set, then validates once. Deliberately not `process.loadEnvFile`:
 * that writes to the host environment, which leaks across Jest sandboxes (D-025).
 */
export function loadConfig(): Env {
  if (!cached) {
    if (existsSync('.env')) {
      for (const [k, v] of Object.entries(parseEnv(readFileSync('.env', 'utf8')))) {
        process.env[k] ??= v;
      }
    }
    cached = validateEnv(process.env);
  }
  return cached;
}

@Global()
@Module({
  providers: [{ provide: APP_CONFIG, useFactory: loadConfig }],
  exports: [APP_CONFIG],
})
export class ConfigModule {}
