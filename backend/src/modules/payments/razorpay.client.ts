import { createHmac, timingSafeEqual } from 'node:crypto';
import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';

export interface RazorpayOrder {
  id: string;
  amount: number;
  currency: string;
  receipt?: string;
  status: string;
}

export interface RazorpayPayment {
  id: string;
  order_id?: string;
  status: 'created' | 'authorized' | 'captured' | 'refunded' | 'failed';
  method?: string;
  amount: number;
}

const hmacHex = (secret: string, data: string | Buffer) =>
  createHmac('sha256', secret).update(data).digest('hex');

/** Constant-time compare of two hex digests. */
export function digestsMatch(expectedHex: string, givenHex: string): boolean {
  const a = Buffer.from(expectedHex, 'hex');
  const b = Buffer.from(givenHex, 'hex');
  return a.length === b.length && a.length > 0 && timingSafeEqual(a, b);
}

/** SPEC §15 step 3: HMAC SHA256 of `order_id|payment_id` with the key secret. */
export function verifyCheckoutSignature(
  keySecret: string,
  orderId: string,
  paymentId: string,
  signature: string,
): boolean {
  return digestsMatch(hmacHex(keySecret, `${orderId}|${paymentId}`), signature);
}

/** SPEC §7.5: `X-Razorpay-Signature` is HMAC SHA256 of the raw body with the webhook secret. */
export function verifyWebhookSignature(
  webhookSecret: string,
  rawBody: Buffer,
  signature: string,
): boolean {
  return digestsMatch(hmacHex(webhookSecret, rawBody), signature);
}

/** Minimal Razorpay Orders API client (basic auth, fetch). */
@Injectable()
export class RazorpayClient {
  readonly keyId?: string;
  private readonly keySecret?: string;
  readonly webhookSecret?: string;
  private readonly baseUrl: string;

  constructor(@Inject(APP_CONFIG) config: Env) {
    this.keyId = config.RAZORPAY_KEY_ID;
    this.keySecret = config.RAZORPAY_KEY_SECRET;
    this.webhookSecret = config.RAZORPAY_WEBHOOK_SECRET;
    this.baseUrl = config.RAZORPAY_BASE_URL.replace(/\/$/, '');
  }

  get configured() {
    return Boolean(this.keyId && this.keySecret);
  }

  private creds() {
    if (!this.keyId || !this.keySecret) {
      throw new AppException(
        'PAYMENTS_UNAVAILABLE',
        'Online payments are not configured',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return { keyId: this.keyId, keySecret: this.keySecret };
  }

  private async call<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
    const { keyId, keySecret } = this.creds();
    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        authorization: 'Basic ' + Buffer.from(`${keyId}:${keySecret}`).toString('base64'),
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new AppException(
        'PAYMENT_GATEWAY_ERROR',
        `Payment gateway error (${res.status}) ${text.slice(0, 200)}`,
        HttpStatus.BAD_GATEWAY,
      );
    }
    return (await res.json()) as T;
  }

  createOrder(amountPaise: number, receipt: string, notes: Record<string, string>) {
    return this.call<RazorpayOrder>('POST', '/v1/orders', {
      amount: amountPaise,
      currency: 'INR',
      receipt,
      notes,
    });
  }

  async orderPayments(orderId: string): Promise<RazorpayPayment[]> {
    const res = await this.call<{ items: RazorpayPayment[] }>(
      'GET',
      `/v1/orders/${encodeURIComponent(orderId)}/payments`,
    );
    return res.items ?? [];
  }

  verifyCheckout(orderId: string, paymentId: string, signature: string) {
    return verifyCheckoutSignature(this.creds().keySecret, orderId, paymentId, signature);
  }

  verifyWebhook(rawBody: Buffer, signature: string) {
    if (!this.webhookSecret) return false;
    return verifyWebhookSignature(this.webhookSecret, rawBody, signature);
  }
}
