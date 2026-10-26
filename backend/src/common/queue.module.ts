import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import type { ConnectionOptions } from 'bullmq';
import { loadConfig } from '../config/config.module';
import { MATCHING_QUEUE } from '../modules/matching/matching.service';
import { SYSTEM_QUEUE } from '../modules/matching/system.processor';

/** BullMQ owns (and closes) connections it creates from options, unlike a passed-in client. */
export function redisOptions(url: string): ConnectionOptions {
  const u = new URL(url);
  return {
    host: u.hostname,
    port: Number(u.port || 6379),
    db: Number(u.pathname.replace('/', '') || 0),
    username: u.username || undefined,
    password: u.password ? decodeURIComponent(u.password) : undefined,
    tls: u.protocol === 'rediss:' ? {} : undefined,
    maxRetriesPerRequest: null,
  };
}

/** BullMQ connection + producer queues, available in both processes. */
@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      useFactory: () => ({ connection: redisOptions(loadConfig().REDIS_URL) }),
    }),
    BullModule.registerQueue({ name: MATCHING_QUEUE }, { name: SYSTEM_QUEUE }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
