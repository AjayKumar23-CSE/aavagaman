import { InjectQueue } from '@nestjs/bullmq';
import { HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { K } from '../../common/redis-keys';
import { RedisService } from '../../common/redis.service';
import { LocationService, NearbyDriver } from '../location/location.service';
import { PushService } from '../notifications/push.service';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { nextStatus } from '../rides/ride-state';
import { RideEventsService } from '../rides/ride-events.service';
import { RidePublisher } from '../rides/ride.publisher';
import { RideRepository } from '../rides/ride.repository';

export const MATCHING_QUEUE = 'matching';
export const JOB_MATCH = 'match-ride';
export const JOB_OFFER_TIMEOUT = 'offer-timeout';

/** SPEC §9.4 retry delays. */
export const EXPAND_RETRY_DELAY_MS = 3000;
export const RETRY_DELAY_MS = 5000;
/** The open-offer hash outlives the round a little (SPEC §6: 25 s). */
const OFFER_TTL_S = 25;
const OFFERED_SET_TTL_S = 600;
const CANDIDATE_COUNT = 10;

export interface MatchJob {
  ride_id: string;
  attempt: number;
  radius_km: number;
  deadline: number; // epoch ms
}

/** Ends one round of offers (D-055); `round` is the match attempt that sent it. */
export interface OfferTimeoutJob {
  ride_id: string;
  round: number;
}

// BullMQ forbids ":" in custom job ids (D-023).
export const matchJobId = (rideId: string, attempt: number) => `match_${rideId}_${attempt}`;
export const offerJobId = (rideId: string, round: number) => `offer_${rideId}_${round}`;

type RideRow = NonNullable<Awaited<ReturnType<RideRepository['find']>>>;
type LoseResponse = 'rejected' | 'timeout' | 'withdrawn';

const offerInvalid = () =>
  new AppException('OFFER_NOT_VALID', 'This ride is no longer available', HttpStatus.CONFLICT);

/**
 * Broadcast matching (D-055). Each round offers the ride to the nearest
 * OFFER_BATCH_SIZE free drivers at the same time, and a driver may hold offers
 * from several rides. The first accept wins under the ride row lock; the other
 * offers of that round are withdrawn, and so are the winner's offers from
 * other rides. A round ends when everyone has answered or when it times out,
 * and the next round asks drivers who have not been offered this ride yet.
 */
@Injectable()
export class MatchingService {
  private readonly logger = new Logger(MatchingService.name);

  constructor(
    @InjectQueue(MATCHING_QUEUE) private readonly queue: Queue,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly location: LocationService,
    private readonly rides: RideRepository,
    private readonly events: RideEventsService,
    private readonly publisher: RidePublisher,
    private readonly rt: RealtimeEmitter,
    private readonly push: PushService,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  // ---------------------------------------------------------------- enqueue

  private async enqueueMatch(job: MatchJob, delayMs = 0) {
    const id = matchJobId(job.ride_id, job.attempt);
    await this.redis
      .multi()
      .hset(K.match(job.ride_id), {
        attempt: job.attempt,
        radius_km: job.radius_km,
        deadline: job.deadline,
        job_id: id,
      })
      .expire(K.match(job.ride_id), OFFERED_SET_TTL_S)
      .exec();
    await this.queue.add(JOB_MATCH, job, {
      jobId: id,
      delay: delayMs,
      removeOnComplete: true,
      removeOnFail: 100,
    });
  }

  /** onRideRequested (SPEC §9.4). Also used when a driver cancel re-queues a ride. */
  async start(rideId: string, opts: { keepOffered?: boolean } = {}) {
    if (!opts.keepOffered) {
      await this.redis.del(K.offeredSet(rideId));
    } else {
      // Re-queue after a driver cancel: drivers who merely lost a round (withdrawn) may be
      // asked again; everyone who answered or cancelled this ride stays excluded.
      const rows = await this.prisma.rideOffer.findMany({
        where: { rideId },
        select: { driverId: true, response: true },
      });
      const keep = new Set(rows.filter((r) => r.response !== 'withdrawn').map((r) => r.driverId));
      const drop = (await this.redis.smembers(K.offeredSet(rideId))).filter((d) => !keep.has(d));
      if (drop.length) await this.redis.srem(K.offeredSet(rideId), ...drop);
    }
    const prev = await this.redis.hget(K.match(rideId), 'attempt');
    // Rounds sent before this (re)start do not count towards MAX_OFFER_ROUNDS_PER_RIDE.
    await this.redis.hset(K.match(rideId), { rounds: 0 });
    await this.enqueueMatch({
      ride_id: rideId,
      attempt: Number(prev ?? 0) + 1,
      radius_km: this.config.DEFAULT_SEARCH_RADIUS_KM,
      deadline: Date.now() + this.config.MATCHING_DEADLINE_SECONDS * 1000,
    });
  }

  /** Next round with the stored parameters (after a timeout or when everyone answered). */
  private async continueMatching(rideId: string) {
    const m = await this.redis.hgetall(K.match(rideId));
    await this.enqueueMatch({
      ride_id: rideId,
      attempt: Number(m.attempt ?? 1) + 1,
      radius_km: Number(m.radius_km ?? this.config.DEFAULT_SEARCH_RADIUS_KM),
      deadline: Number(m.deadline ?? Date.now()),
    });
  }

  /** Rider/admin cancel during REQUESTED: drop pending jobs and withdraw every open offer. */
  async stop(rideId: string) {
    const m = await this.redis.hgetall(K.match(rideId));
    if (m.job_id) await this.queue.remove(m.job_id).catch(() => 0);
    if (m.attempt) await this.queue.remove(offerJobId(rideId, Number(m.attempt))).catch(() => 0);
    await this.closeRound(rideId, 'withdrawn');
    await this.redis.del(K.match(rideId));
  }

  // ---------------------------------------------------------------- open offers

  /** Records a response on an open offer; false if that offer was not open. Caller holds the ride lock. */
  private async closeOffer(
    tx: Prisma.TransactionClient,
    rideId: string,
    driverId: string,
    response: 'accepted' | LoseResponse,
  ): Promise<boolean> {
    const { count } = await tx.rideOffer.updateMany({
      where: { rideId, driverId, response: null },
      data: { response, respondedAt: new Date() },
    });
    return count > 0;
  }

  /** Forgets one driver's offer for a ride; the driver is idle again once they hold no other offer. */
  private async detach(rideId: string, driverId: string, notify: boolean) {
    await this.redis
      .multi()
      .hdel(K.offers(rideId), driverId)
      .srem(K.driverOffers(driverId), rideId)
      .exec();
    if ((await this.redis.scard(K.driverOffers(driverId))) === 0) {
      await this.location.casState(driverId, 'offered', 'idle');
    }
    if (notify) this.rt.toUser(driverId, 'ride:offer:expired', { ride_id: rideId });
  }

  /** Closes every still-open offer of the ride's round (except one driver) and tells those drivers. */
  private async closeRound(
    rideId: string,
    response: 'timeout' | 'withdrawn',
    except?: string,
  ): Promise<string[]> {
    const drivers = Object.keys(await this.redis.hgetall(K.offers(rideId))).filter(
      (d) => d !== except,
    );
    if (drivers.length) {
      await this.prisma.$transaction(async (tx) => {
        await this.rides.lock(rideId, tx);
        await tx.rideOffer.updateMany({
          where: { rideId, driverId: { in: drivers }, response: null },
          data: { response, respondedAt: new Date() },
        });
      });
    }
    await this.redis.del(K.offers(rideId));
    for (const d of drivers) await this.detach(rideId, d, true);
    return drivers;
  }

  /** One driver answers (or loses) one open offer; the round ends early once nobody is left. */
  private async respond(driverId: string, rideId: string, response: LoseResponse) {
    const closed = await this.prisma.$transaction(async (tx) => {
      await this.rides.lock(rideId, tx);
      if (!(await this.redis.hexists(K.offers(rideId), driverId))) return false;
      return this.closeOffer(tx, rideId, driverId, response);
    });
    if (!closed) return false;
    await this.detach(rideId, driverId, response !== 'rejected');
    if ((await this.redis.hlen(K.offers(rideId))) === 0) await this.endRoundEarly(rideId);
    return true;
  }

  private async endRoundEarly(rideId: string) {
    const attempt = await this.redis.hget(K.match(rideId), 'attempt');
    if (attempt) await this.queue.remove(offerJobId(rideId, Number(attempt))).catch(() => 0);
    const ride = await this.rides.find(rideId);
    if (ride?.status === 'REQUESTED') await this.continueMatching(rideId);
  }

  /** Every open offer a driver holds is closed: they took another ride, went offline or vanished. */
  async withdrawFrom(driverId: string, response: LoseResponse) {
    for (const rideId of await this.redis.smembers(K.driverOffers(driverId))) {
      await this.respond(driverId, rideId, response);
    }
  }

  private offerPayload(ride: RideRow, distanceM: number | null, expiresAt: string) {
    return {
      ride_id: ride.id,
      pickup: {
        lat: ride.coords.pickup_lat,
        lng: ride.coords.pickup_lng,
        address: ride.pickupAddress,
      },
      drop_address: ride.dropAddress,
      distance_to_pickup_m: distanceM,
      est_fare_min: Number(ride.estFareMin),
      est_fare_max: Number(ride.estFareMax),
      expires_at: expiresAt,
    };
  }

  // ---------------------------------------------------------------- jobs

  private async markNoDriver(rideId: string) {
    const ride = await this.prisma.$transaction(async (tx) => {
      const row = await this.rides.lock(rideId, tx);
      if (row.status !== 'REQUESTED') return null;
      const to = nextStatus('REQUESTED', 'no_driver', 'system');
      await tx.ride.update({ where: { id: rideId }, data: { status: to } });
      await this.events.record(tx, { rideId, from: 'REQUESTED', to, actor: 'system' });
      return this.rides.get(rideId, tx);
    });
    if (!ride) return;
    await this.redis.del(K.match(rideId));
    this.publisher.noDriver(ride);
  }

  /** match-ride job (SPEC §9.4, D-055): sends one round of offers. Returns the drivers asked. */
  async runMatch(job: MatchJob): Promise<string[]> {
    const ride = await this.rides.find(job.ride_id);
    if (!ride || ride.status !== 'REQUESTED') return [];
    if (Date.now() > job.deadline) {
      await this.markNoDriver(ride.id);
      return [];
    }
    const rounds = Number((await this.redis.hget(K.match(ride.id), 'rounds')) ?? 0);
    if (rounds >= this.config.MAX_OFFER_ROUNDS_PER_RIDE) {
      await this.markNoDriver(ride.id);
      return [];
    }

    const pickup = { lat: ride.coords.pickup_lat, lng: ride.coords.pickup_lng };
    const nearby = await this.location.nearby(
      pickup.lat,
      pickup.lng,
      job.radius_km,
      CANDIDATE_COUNT,
    );
    const offered = new Set(await this.redis.smembers(K.offeredSet(ride.id)));

    const batch: NearbyDriver[] = [];
    for (const c of nearby) {
      if (batch.length >= this.config.OFFER_BATCH_SIZE) break;
      if (offered.has(c.driverId)) continue;
      if ((await this.redis.get(K.vehicleType(c.driverId))) !== ride.vehicleType) continue;
      const state = await this.location.getState(c.driverId);
      if (state !== 'idle' && state !== 'offered') continue; // on a trip or gone
      batch.push(c);
    }

    if (!batch.length) {
      const expand =
        job.attempt === 1 && job.radius_km < this.config.DEFAULT_SEARCH_RADIUS_RETRY_KM;
      await this.enqueueMatch(
        {
          ...job,
          attempt: job.attempt + 1,
          radius_km: expand ? this.config.DEFAULT_SEARCH_RADIUS_RETRY_KM : job.radius_km,
        },
        expand ? EXPAND_RETRY_DELAY_MS : RETRY_DELAY_MS,
      );
      return [];
    }

    const expiresAt = new Date(
      Date.now() + this.config.OFFER_TIMEOUT_SECONDS * 1000,
    ).toISOString();
    const multi = this.redis.multi();
    for (const c of batch) {
      multi
        .hset(K.offers(ride.id), c.driverId, expiresAt)
        .sadd(K.driverOffers(c.driverId), ride.id)
        .expire(K.driverOffers(c.driverId), OFFERED_SET_TTL_S)
        .sadd(K.offeredSet(ride.id), c.driverId);
    }
    multi
      .expire(K.offers(ride.id), OFFER_TTL_S)
      .expire(K.offeredSet(ride.id), OFFERED_SET_TTL_S)
      .hincrby(K.match(ride.id), 'rounds', 1);
    await multi.exec();
    await this.prisma.rideOffer.createMany({
      data: batch.map((c) => ({
        rideId: ride.id,
        driverId: c.driverId,
        distanceToPickupM: c.distanceM,
      })),
    });
    await this.queue.add(
      JOB_OFFER_TIMEOUT,
      { ride_id: ride.id, round: job.attempt } satisfies OfferTimeoutJob,
      {
        jobId: offerJobId(ride.id, job.attempt),
        delay: this.config.OFFER_TIMEOUT_SECONDS * 1000,
        removeOnComplete: true,
        removeOnFail: 100,
      },
    );

    for (const c of batch) {
      // "offered" only colours the admin live map; it never blocks further offers.
      await this.location.casState(c.driverId, 'idle', 'offered');
      this.rt.toUser(c.driverId, 'ride:offer', this.offerPayload(ride, c.distanceM, expiresAt));
      void this.push.toUser(c.driverId, {
        title: 'New ride request',
        body: `${ride.pickupAddress} · ${(c.distanceM / 1000).toFixed(1)} km away`,
        highPriority: true,
        data: { type: 'ride_offer', ride_id: ride.id, expires_at: expiresAt },
      });
    }
    return batch.map((c) => c.driverId);
  }

  /** offer-timeout job: the round ran out; whoever is still undecided timed out. */
  async runOfferTimeout(job: OfferTimeoutJob) {
    const { ride_id: rideId, round } = job;
    // A later attempt means the round already ended (everyone answered, accept, or cancel).
    if (Number(await this.redis.hget(K.match(rideId), 'attempt')) !== round) return;
    const ride = await this.rides.find(rideId);
    if (!ride || ride.status !== 'REQUESTED') return;
    await this.closeRound(rideId, 'timeout');
    await this.continueMatching(rideId);
  }

  // ---------------------------------------------------------------- driver actions

  /** SPEC §9.4 accept: one transaction, ride row locked; exactly one driver wins. */
  async accept(driverId: string, rideId: string) {
    const vehicle = await this.prisma.vehicle.findFirst({ where: { driverId, active: true } });
    let ride;
    try {
      ride = await this.prisma.$transaction(async (tx) => {
        const row = await this.rides.lock(rideId, tx);
        if (row.status !== 'REQUESTED' || !(await this.redis.hexists(K.offers(rideId), driverId))) {
          throw offerInvalid();
        }
        if (!(await this.closeOffer(tx, rideId, driverId, 'accepted'))) throw offerInvalid();
        const to = nextStatus('REQUESTED', 'accept', 'driver');
        await tx.ride.update({
          where: { id: rideId },
          data: { status: to, driverId, vehicleId: vehicle?.id ?? null, acceptedAt: new Date() },
        });
        await this.events.record(tx, {
          rideId,
          from: 'REQUESTED',
          to,
          actor: 'driver',
          actorId: driverId,
        });
        return this.rides.get(rideId, tx);
      });
    } catch (err) {
      // one_active_ride_per_driver: this driver already holds another active ride.
      if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
        throw new AppException(
          'DRIVER_BUSY',
          'Finish your current ride first',
          HttpStatus.CONFLICT,
        );
      }
      throw err;
    }

    await this.location.setState(driverId, 'on_trip');
    await this.redis.set(K.driverRide(driverId), rideId);
    const attempt = await this.redis.hget(K.match(rideId), 'attempt');
    if (attempt) await this.queue.remove(offerJobId(rideId, Number(attempt))).catch(() => 0);
    await this.closeRound(rideId, 'withdrawn', driverId); // the others lose this round
    await this.redis.multi().srem(K.driverOffers(driverId), rideId).del(K.match(rideId)).exec();
    await this.withdrawFrom(driverId, 'withdrawn'); // and the winner drops any other open offer
    this.publisher.status(ride);
    return ride;
  }

  async reject(driverId: string, rideId: string) {
    if (!(await this.respond(driverId, rideId, 'rejected'))) throw offerInvalid();
  }

  /** Every open offer a driver holds (re-sent on socket reconnect). */
  async pendingOffersFor(driverId: string) {
    const out: ReturnType<MatchingService['offerPayload']>[] = [];
    for (const rideId of await this.redis.smembers(K.driverOffers(driverId))) {
      const expiresAt = await this.redis.hget(K.offers(rideId), driverId);
      if (!expiresAt) {
        await this.redis.srem(K.driverOffers(driverId), rideId); // round already over
        continue;
      }
      const ride = await this.rides.find(rideId);
      if (!ride || ride.status !== 'REQUESTED') continue;
      const o = await this.prisma.rideOffer.findFirst({
        where: { rideId, driverId, response: null },
      });
      out.push(this.offerPayload(ride, o?.distanceToPickupM ?? null, expiresAt));
    }
    return out;
  }

  /** Heartbeat sweeper (SPEC §6): vanished drivers go offline and their open offers time out. */
  async sweepHeartbeats(): Promise<string[]> {
    const stale = await this.location.staleDrivers();
    for (const driverId of stale) {
      await this.location.goOffline(driverId);
      await this.withdrawFrom(driverId, 'timeout').catch((e: Error) =>
        this.logger.warn(`sweeper ${driverId}: ${e.message}`),
      );
    }
    if (stale.length)
      this.logger.log(`heartbeat sweeper: ${stale.length} driver(s) marked offline`);
    return stale;
  }
}
