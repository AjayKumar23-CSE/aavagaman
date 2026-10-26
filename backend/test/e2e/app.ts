import { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { io, Socket } from 'socket.io-client';
import { AppModule } from '../../src/app.module';
import { configureApp } from '../../src/app.setup';
import { RedisService } from '../../src/common/redis.service';
import { loadConfig } from '../../src/config/config.module';
import { ProcessorsModule } from '../../src/modules/matching/processors.module';

/**
 * Boots the real HTTP pipeline. `worker: true` also runs the BullMQ processors
 * in-process and listens on a port so Socket.io clients can connect.
 */
export async function createTestApp(opts: { worker?: boolean } = {}) {
  const moduleRef = await Test.createTestingModule({
    imports: opts.worker ? [AppModule, ProcessorsModule] : [AppModule],
  }).compile();
  // Clean slate (rate limits, OTPs, GEO set, queues) before anything boots.
  await moduleRef.get(RedisService).flushdb();
  const app = moduleRef.createNestApplication<NestExpressApplication>({ bodyParser: false });
  configureApp(app, loadConfig());
  if (opts.worker) await app.listen(0, '127.0.0.1');
  else await app.init();
  return app;
}

export const api = (app: NestExpressApplication) => request(app.getHttpServer());

export async function connectSocket(app: NestExpressApplication, token: string): Promise<Socket> {
  const url = await app.getUrl();
  const socket = io(`${url.replace('[::1]', '127.0.0.1')}/rt`, {
    auth: { token },
    transports: ['websocket'],
    forceNew: true,
  });
  await new Promise<void>((resolve, reject) => {
    socket.once('connect', () => resolve());
    socket.once('connect_error', reject);
  });
  return socket;
}

/** Resolves with the next `event` payload matching `pred`, or rejects after `ms`. */
export function next<T = Record<string, unknown>>(
  socket: Socket,
  event: string,
  ms = 8000,
  pred: (p: T) => boolean = () => true,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(event, handler);
      reject(new Error(`timed out waiting for ${event}`));
    }, ms);
    const handler = (p: T) => {
      if (!pred(p)) return;
      clearTimeout(timer);
      socket.off(event, handler);
      resolve(p);
    };
    socket.on(event, handler);
  });
}

/** Random valid Indian mobile so reruns never collide. */
export const randomPhone = () => '+919' + String(Math.floor(Math.random() * 1e9)).padStart(9, '0');

export const randomIp = () =>
  `10.${1 + Math.floor(Math.random() * 200)}.${Math.floor(Math.random() * 255)}.${1 + Math.floor(Math.random() * 250)}`;

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
