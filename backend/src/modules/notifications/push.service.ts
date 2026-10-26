import { Inject, Injectable, Logger } from '@nestjs/common';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, Messaging } from 'firebase-admin/messaging';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { PrismaService } from '../../common/prisma.service';

export interface PushMessage {
  title: string;
  body: string;
  /** String-only data payload, read by the app when backgrounded. */
  data?: Record<string, string>;
  /** High-priority data message that wakes the app (ride offers, SPEC §14). */
  highPriority?: boolean;
}

const STALE_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** FCM pushes (SPEC §14). Never throws: a failed push must not fail the request. */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private readonly messaging?: Messaging;

  constructor(
    @Inject(APP_CONFIG) config: Env,
    private readonly prisma: PrismaService,
  ) {
    if (config.FCM_SERVICE_ACCOUNT_JSON_BASE64) {
      const account = JSON.parse(
        Buffer.from(config.FCM_SERVICE_ACCOUNT_JSON_BASE64, 'base64').toString('utf8'),
      );
      const app = getApps()[0] ?? initializeApp({ credential: cert(account) });
      this.messaging = getMessaging(app);
    }
  }

  async toUser(userId: string, msg: PushMessage): Promise<void> {
    try {
      const user = await this.prisma.user.findUnique({
        where: { id: userId },
        select: { fcmToken: true },
      });
      if (!user?.fcmToken) return;
      if (!this.messaging) {
        this.logger.debug(`push (FCM not configured) → ${userId}: ${msg.title}`);
        return;
      }
      await this.messaging.send({
        token: user.fcmToken,
        notification: { title: msg.title, body: msg.body },
        data: msg.data,
        android: {
          priority: msg.highPriority ? 'high' : 'normal',
          notification: { channelId: 'rides' },
        },
      });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code && STALE_TOKEN_CODES.has(code)) {
        await this.prisma.user
          .update({ where: { id: userId }, data: { fcmToken: null } })
          .catch(() => {});
        return;
      }
      this.logger.warn(`push to ${userId} failed: ${(err as Error).message}`);
    }
  }
}
