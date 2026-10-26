import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, OnApplicationBootstrap } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { Logger } from '@nestjs/common';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { SmsService } from '../notifications/sms.service';
import { PaymentsService } from '../payments/payments.service';
import { SettlementsService } from '../settlements/settlements.service';
import { MatchingService } from './matching.service';

export const SYSTEM_QUEUE = 'system';
export const JOB_HEARTBEAT_SWEEP = 'heartbeat-sweep';
/** SPEC §9.6: SMS the trip OTP if the rider's app is still offline after ARRIVED. */
export const JOB_OTP_SMS = 'otp-sms-fallback';
/** SPEC §15 step 5: poll Razorpay for captures the webhook missed. */
export const JOB_PAYMENT_POLL = 'payment-poll';
/** SPEC §15: Monday 06:00 IST weekly settlements. */
export const JOB_WEEKLY_SETTLEMENT = 'weekly-settlement';
/** SPEC §5: daily 03:00 IST retention — ride_tracks older than TRACK_RETENTION_DAYS. */
export const JOB_RETENTION = 'retention';

/** Repeatable housekeeping jobs (SPEC §6 heartbeat sweeper). */
@Processor(SYSTEM_QUEUE)
export class SystemProcessor extends WorkerHost implements OnApplicationBootstrap {
  private readonly logger = new Logger(SystemProcessor.name);

  constructor(
    @InjectQueue(SYSTEM_QUEUE) private readonly queue: Queue,
    private readonly matching: MatchingService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly sms: SmsService,
    private readonly payments: PaymentsService,
    private readonly settlements: SettlementsService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {
    super();
  }

  async onApplicationBootstrap() {
    await this.queue.upsertJobScheduler(
      JOB_HEARTBEAT_SWEEP,
      { every: this.config.HEARTBEAT_SWEEP_SECONDS * 1000 },
      { name: JOB_HEARTBEAT_SWEEP, opts: { removeOnComplete: true, removeOnFail: 50 } },
    );
    await this.queue.upsertJobScheduler(
      JOB_PAYMENT_POLL,
      { every: this.config.PAYMENT_POLL_INTERVAL_SECONDS * 1000 },
      { name: JOB_PAYMENT_POLL, opts: { removeOnComplete: true, removeOnFail: 50 } },
    );
    await this.queue.upsertJobScheduler(
      JOB_WEEKLY_SETTLEMENT,
      { pattern: '0 6 * * 1', tz: 'Asia/Kolkata' },
      { name: JOB_WEEKLY_SETTLEMENT, opts: { removeOnComplete: true, removeOnFail: 50 } },
    );
    await this.queue.upsertJobScheduler(
      JOB_RETENTION,
      { pattern: '0 3 * * *', tz: 'Asia/Kolkata' },
      { name: JOB_RETENTION, opts: { removeOnComplete: true, removeOnFail: 50 } },
    );
  }

  async process(job: Job) {
    switch (job.name) {
      case JOB_HEARTBEAT_SWEEP:
        return this.matching.sweepHeartbeats();
      case JOB_OTP_SMS:
        return this.otpSmsFallback((job.data as { ride_id: string }).ride_id);
      case JOB_PAYMENT_POLL:
        return this.payments.pollPending();
      case JOB_WEEKLY_SETTLEMENT:
        return this.settlements.generate();
      case JOB_RETENTION:
        return this.retention();
    }
  }

  /** Deletes old GPS tracks; OTPs expire by Redis TTL; nothing else is archived (SPEC §5). */
  async retention(days = this.config.TRACK_RETENTION_DAYS): Promise<number> {
    const cutoff = new Date(Date.now() - days * 86_400_000);
    const deleted = await this.prisma
      .$executeRaw`DELETE FROM ride_tracks WHERE recorded_at < ${cutoff}`;
    this.logger.log(`retention: deleted ${deleted} ride_tracks rows older than ${days} days`);
    return deleted;
  }

  private async otpSmsFallback(rideId: string) {
    const ride = await this.prisma.ride.findUnique({
      where: { id: rideId },
      include: { rider: true },
    });
    if (!ride || ride.status !== 'ARRIVED') return 'skipped';
    if ((await this.redis.scard(K.wsUser(ride.riderId))) > 0) return 'rider-online';
    await this.sms.sendOtp(ride.rider.phone, ride.tripOtp);
    this.logger.log(`trip OTP sent by SMS for ride ${rideId}`);
    return 'sent';
  }
}
