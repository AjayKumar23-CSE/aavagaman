import { HttpStatus, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { CancelActor, PaymentMethod, Prisma } from '@prisma/client';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { PrismaService } from '../../common/prisma.service';
import { LocationService } from '../location/location.service';
import { RealtimeEmitter } from '../realtime/realtime.emitter';
import { RideTransitionService } from '../rides/ride-transition.service';
import { RidePublisher } from '../rides/ride.publisher';
import { RideRepository } from '../rides/ride.repository';
import { presentPayment } from './payment.presenter';
import { RazorpayClient, RazorpayPayment } from './razorpay.client';

/** Razorpay `method` → payments.method (SPEC §5 enum has no netbanking/emi; those count as card). */
export function toPaymentMethod(method?: string): PaymentMethod {
  switch (method) {
    case 'upi':
      return 'upi';
    case 'wallet':
      return 'wallet';
    default:
      return 'card';
  }
}

export const amountDue = (r: {
  finalFare: Prisma.Decimal | null;
  cancellationFee: Prisma.Decimal | null;
}) => Number(r.finalFare ?? 0) + Number(r.cancellationFee ?? 0);

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly razorpay: RazorpayClient,
    private readonly rides: RideRepository,
    private readonly transition: RideTransitionService,
    private readonly publisher: RidePublisher,
    private readonly location: LocationService,
    private readonly rt: RealtimeEmitter,
    @Inject(APP_CONFIG) private readonly config: Env,
  ) {}

  /** SPEC §15 step 1: POST /rides/:id/payment/order. */
  async createOrder(riderId: string, rideId: string) {
    const ride = await this.rides.find(rideId);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException('Ride not found');
    if (ride.status !== 'COMPLETED') {
      throw new AppException(
        'RIDE_NOT_PAYABLE',
        ride.status === 'PAID' ? 'This ride is already paid' : 'The trip is not completed yet',
        HttpStatus.CONFLICT,
      );
    }
    const amount = amountDue(ride);
    const paise = Math.round(amount * 100);
    const existing = await this.prisma.payment.findUnique({ where: { rideId } });
    if (existing?.status === 'paid')
      throw new AppException('ALREADY_PAID', 'This ride is already paid', HttpStatus.CONFLICT);
    if (
      existing?.gatewayOrderId &&
      Number(existing.amount) === amount &&
      existing.status === 'pending'
    ) {
      return {
        razorpay_order_id: existing.gatewayOrderId,
        amount: paise,
        currency: 'INR',
        key_id: this.razorpay.keyId,
      };
    }
    const order = await this.razorpay.createOrder(paise, rideId, { ride_id: rideId });
    await this.prisma.payment.upsert({
      where: { rideId },
      // Provisional method; the webhook/verify step records what the rider actually used.
      create: { rideId, method: 'upi', amount, status: 'pending', gatewayOrderId: order.id },
      update: {
        method: 'upi',
        amount,
        status: 'pending',
        gatewayOrderId: order.id,
        gatewayPaymentId: null,
        gatewaySignature: null,
      },
    });
    return {
      razorpay_order_id: order.id,
      amount: paise,
      currency: 'INR',
      key_id: this.razorpay.keyId,
    };
  }

  /** SPEC §15 step 3: POST /rides/:id/payment/verify. */
  async verify(
    riderId: string,
    rideId: string,
    dto: { razorpay_order_id: string; razorpay_payment_id: string; razorpay_signature: string },
  ) {
    const ride = await this.rides.find(rideId);
    if (!ride || ride.riderId !== riderId) throw new NotFoundException('Ride not found');
    const payment = await this.prisma.payment.findUnique({ where: { rideId } });
    if (!payment || payment.gatewayOrderId !== dto.razorpay_order_id) {
      throw new AppException(
        'ORDER_MISMATCH',
        'This payment does not belong to the ride',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }
    if (
      !this.razorpay.verifyCheckout(
        dto.razorpay_order_id,
        dto.razorpay_payment_id,
        dto.razorpay_signature,
      )
    ) {
      throw new AppException(
        'SIGNATURE_INVALID',
        'Payment could not be verified',
        HttpStatus.BAD_REQUEST,
      );
    }
    return presentPayment(
      await this.markPaid(
        rideId,
        { paymentId: dto.razorpay_payment_id, signature: dto.razorpay_signature },
        'rider',
        riderId,
      ),
    );
  }

  /**
   * Idempotent on gateway_payment_id (SPEC §7.5). Marks the payment paid and moves a
   * COMPLETED ride to PAID; a ride already PAID (e.g. cash meanwhile) gets an admin alert.
   */
  async markPaid(
    rideId: string,
    gw: { paymentId: string; signature?: string; method?: string },
    actor: CancelActor,
    actorId?: string | null,
  ) {
    const current = await this.prisma.payment.findUnique({ where: { rideId } });
    if (!current) throw new NotFoundException('Payment not found');
    if (current.status === 'paid') {
      if (current.gatewayPaymentId !== gw.paymentId) {
        this.logger.warn(
          `ride ${rideId}: second capture ${gw.paymentId} ignored (already paid by ${current.gatewayPaymentId ?? 'cash'})`,
        );
        this.publisher.adminAlert('double_payment', {
          ride_id: rideId,
          gateway_payment_id: gw.paymentId,
        });
      }
      return current;
    }

    const ride = await this.rides.get(rideId);
    const data: Prisma.PaymentUpdateInput = {
      status: 'paid',
      paidAt: new Date(),
      gatewayPaymentId: gw.paymentId,
      ...(gw.signature ? { gatewaySignature: gw.signature } : {}),
      ...(gw.method ? { method: toPaymentMethod(gw.method) } : {}),
    };
    let updated;
    if (ride.status === 'COMPLETED') {
      const { ride: paidRide } = await this.transition.apply(rideId, {
        event: 'pay',
        actor,
        actorId,
        data: async (_r, _to, tx) => {
          updated = await tx.payment.update({ where: { rideId }, data });
          return { paidAt: new Date() };
        },
        meta: () => ({ gateway_payment_id: gw.paymentId }),
      });
      if (paidRide.driverId) await this.location.releaseFromRide(paidRide.driverId, rideId);
      this.publisher.status(paidRide);
      this.emitStatus(paidRide.riderId, paidRide.driverId, rideId, 'paid', updated!.method);
      return updated!;
    }
    updated = await this.prisma.payment.update({ where: { rideId }, data });
    this.publisher.adminAlert('payment_after_close', {
      ride_id: rideId,
      ride_status: ride.status,
      gateway_payment_id: gw.paymentId,
    });
    return updated;
  }

  private emitStatus(
    riderId: string,
    driverId: string | null,
    rideId: string,
    status: string,
    method: PaymentMethod,
  ) {
    const payload = { ride_id: rideId, status, method };
    this.rt.toUser(riderId, 'payment:status', payload);
    if (driverId) this.rt.toUser(driverId, 'payment:status', payload);
  }

  async markFailed(rideId: string, gw: { paymentId?: string; method?: string }) {
    const current = await this.prisma.payment.findUnique({ where: { rideId } });
    if (!current || current.status !== 'pending') return current;
    const updated = await this.prisma.payment.update({
      where: { rideId },
      data: {
        status: 'failed',
        gatewayPaymentId: gw.paymentId ?? current.gatewayPaymentId,
        ...(gw.method ? { method: toPaymentMethod(gw.method) } : {}),
      },
    });
    const ride = await this.prisma.ride.findUnique({
      where: { id: rideId },
      select: { riderId: true, driverId: true },
    });
    if (ride) this.emitStatus(ride.riderId, ride.driverId, rideId, 'failed', updated.method);
    return updated;
  }

  /** SPEC §15 step 4: webhook events. Returns what happened, for logging. */
  async handleWebhook(event: string, payment: RazorpayPayment): Promise<string> {
    if (!payment.order_id) return 'no-order';
    const row = await this.prisma.payment.findFirst({
      where: { gatewayOrderId: payment.order_id },
      orderBy: { createdAt: 'desc' },
    });
    if (!row) return 'unknown-order';
    if (event === 'payment.captured') {
      await this.markPaid(row.rideId, { paymentId: payment.id, method: payment.method }, 'system');
      return 'captured';
    }
    if (event === 'payment.failed') {
      await this.markFailed(row.rideId, { paymentId: payment.id, method: payment.method });
      return 'failed';
    }
    return 'ignored';
  }

  /** SPEC §15 step 5: catch captures the webhook missed. */
  async pollPending(): Promise<number> {
    if (!this.razorpay.configured) return 0;
    const now = Date.now();
    const pending = await this.prisma.payment.findMany({
      where: {
        status: 'pending',
        gatewayOrderId: { not: null },
        createdAt: {
          lte: new Date(now - this.config.PAYMENT_CASH_FALLBACK_SECONDS * 1000),
          gte: new Date(now - this.config.PAYMENT_POLL_MAX_HOURS * 3_600_000),
        },
      },
      take: 50,
    });
    let captured = 0;
    for (const p of pending) {
      try {
        const payments = await this.razorpay.orderPayments(p.gatewayOrderId!);
        const hit = payments.find((x) => x.status === 'captured');
        if (hit) {
          await this.markPaid(p.rideId, { paymentId: hit.id, method: hit.method }, 'system');
          captured++;
        }
      } catch (err) {
        this.logger.warn(`poll ${p.gatewayOrderId}: ${(err as Error).message}`);
      }
    }
    return captured;
  }

  /** Cash may be marked unless a *fresh* online attempt is still pending (SPEC §15 step 5). */
  async assertCashAllowed(rideId: string) {
    const p = await this.prisma.payment.findUnique({ where: { rideId } });
    if (!p) return;
    if (p.status === 'paid')
      throw new AppException('ALREADY_PAID', 'This ride is already paid', HttpStatus.CONFLICT);
    const age = Date.now() - (p.createdAt?.getTime() ?? 0);
    if (
      p.status === 'pending' &&
      p.gatewayOrderId &&
      age < this.config.PAYMENT_CASH_FALLBACK_SECONDS * 1000
    ) {
      throw new AppException(
        'PAYMENT_PENDING',
        'An online payment is in progress. Wait a few minutes before collecting cash.',
        HttpStatus.CONFLICT,
      );
    }
  }
}
