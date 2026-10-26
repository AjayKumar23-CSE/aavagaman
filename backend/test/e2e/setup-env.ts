import { existsSync, readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

// Local e2e runs read .env.test; CI provides the same variables directly.
// Assign explicitly: Jest's sandbox has its own copy of process.env.
if (existsSync('.env.test')) {
  for (const [k, v] of Object.entries(parseEnv(readFileSync('.env.test', 'utf8')))) {
    process.env[k] ??= v;
  }
}
