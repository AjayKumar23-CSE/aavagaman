import { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import type { Server, ServerOptions } from 'socket.io';
import { socketKey } from './realtime.emitter';

/** Socket.io with the Redis adapter: needed for worker emits, and ready for multiple api replicas. */
export class RedisIoAdapter extends IoAdapter {
  private readonly pub: Redis;
  private readonly sub: Redis;

  constructor(
    app: INestApplicationContext,
    private readonly redisUrl: string,
  ) {
    super(app);
    this.pub = new Redis(redisUrl);
    this.sub = this.pub.duplicate();
  }

  createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, options) as Server;
    server.adapter(createAdapter(this.pub, this.sub, { key: socketKey(this.redisUrl) }));
    return server;
  }

  async dispose() {
    await Promise.allSettled([this.pub.quit(), this.sub.quit()]);
  }
}
