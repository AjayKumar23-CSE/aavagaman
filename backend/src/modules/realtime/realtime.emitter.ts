import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Emitter } from '@socket.io/redis-emitter';
import Redis from 'ioredis';
import { loadConfig } from '../../config/config.module';

export const RT_NAMESPACE = '/rt';

/** Socket.io adapter/emitter key, namespaced by Redis DB so test and dev never cross-talk. */
export function socketKey(redisUrl: string): string {
  const db = new URL(redisUrl).pathname.replace('/', '') || '0';
  return `socket.io-db${db}`;
}

export const userRoom = (userId: string) => `user:${userId}`;
export const ADMIN_ROOM = 'admin';

/**
 * Emits to Socket.io rooms through Redis, so the API and the worker process
 * (SPEC §17.2) reach connected clients the same way (D-022).
 */
@Injectable()
export class RealtimeEmitter implements OnModuleDestroy {
  private readonly client: Redis;
  private readonly emitter: ReturnType<Emitter['of']>;

  constructor() {
    const url = loadConfig().REDIS_URL;
    this.client = new Redis(url);
    this.emitter = new Emitter(this.client, { key: socketKey(url) }).of(RT_NAMESPACE);
  }

  toUser(userId: string, event: string, payload: unknown) {
    this.emitter.to(userRoom(userId)).emit(event, payload);
  }

  toAdmins(event: string, payload: unknown) {
    this.emitter.to(ADMIN_ROOM).emit(event, payload);
  }

  async onModuleDestroy() {
    await this.client.quit();
  }
}
