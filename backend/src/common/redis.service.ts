import { Inject, Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { APP_CONFIG } from '../config/config.module';
import type { Env } from '../config/env.schema';

@Injectable()
export class RedisService extends Redis implements OnModuleDestroy {
  constructor(@Inject(APP_CONFIG) config: Env) {
    // maxRetriesPerRequest: null is required by BullMQ, which will share this URL.
    super(config.REDIS_URL, { maxRetriesPerRequest: null });
  }

  async onModuleDestroy() {
    await this.quit();
  }
}
