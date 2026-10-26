import { randomUUID } from 'node:crypto';
import { HttpStatus, Inject, Injectable, Logger } from '@nestjs/common';
import type { CallStatus } from '@prisma/client';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { AppException } from '../../common/app.exception';
import { STUB_CALLER_ID } from '../rides/ride.presenter';

export interface ConnectInput {
  /** Rung first (the person who tapped Call). */
  from: string;
  /** Rung once `from` answers. */
  to: string;
  maxSeconds: number;
}

export interface ConnectResult {
  providerCallId: string;
  status: CallStatus;
}

/** Places a two-leg bridged call that shows the virtual number to both parties. */
export interface CallProvider {
  readonly name: 'stub' | 'exotel';
  /** The number both parties see (and can call back). */
  readonly displayNumber: string;
  connect(input: ConnectInput): Promise<ConnectResult>;
}

export const CALL_PROVIDER = Symbol('CALL_PROVIDER');

/** Exotel `Status` values → ours. */
export function mapExotelStatus(status: string | undefined): CallStatus {
  switch ((status ?? '').toLowerCase()) {
    case 'queued':
    case 'initiated':
      return 'initiated';
    case 'ringing':
      return 'ringing';
    case 'in-progress':
    case 'in_progress':
      return 'in_progress';
    case 'completed':
      return 'completed';
    case 'no-answer':
    case 'no_answer':
      return 'no_answer';
    case 'busy':
      return 'busy';
    default:
      return 'failed';
  }
}

/** The provider refused or could not be reached; [detail] is its own message, kept for support. */
export class CallProviderError extends AppException {
  constructor(readonly detail: string) {
    super('CALL_FAILED', 'Could not place the call', HttpStatus.BAD_GATEWAY);
  }
}

export const TERMINAL_CALL_STATUSES: readonly CallStatus[] = ['completed', 'no_answer', 'busy', 'failed'];

/** Dev/test stand-in: records the call, rings nobody. */
export class StubCallProvider implements CallProvider {
  readonly name = 'stub' as const;
  private readonly logger = new Logger('StubCallProvider');

  constructor(readonly displayNumber: string) {}

  async connect(input: ConnectInput): Promise<ConnectResult> {
    this.logger.log(`stub call ${input.from} → ${input.to} via ${this.displayNumber}`);
    return { providerCallId: `stub_${randomUUID()}`, status: 'initiated' };
  }
}

interface ExotelConnectResponse {
  Call?: { Sid?: string; Status?: string };
  RestException?: { Message?: string };
}

/**
 * Exotel Connect API (click-to-call): rings `From`, then dials `To` and bridges them;
 * `CallerId` (the ExoPhone) is what both phones display.
 * https://developer.exotel.com/api/make-a-call-api
 */
export class ExotelCallProvider implements CallProvider {
  readonly name = 'exotel' as const;
  private readonly logger = new Logger('ExotelCallProvider');

  constructor(
    private readonly creds: { sid: string; key: string; token: string; subdomain: string },
    readonly displayNumber: string,
    private readonly statusCallback?: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  /** Request URL and form body, exposed for tests. */
  request(input: ConnectInput): { url: string; body: URLSearchParams; headers: Record<string, string> } {
    const { sid, key, token, subdomain } = this.creds;
    const body = new URLSearchParams({
      From: input.from,
      To: input.to,
      CallerId: this.displayNumber,
      CallType: 'trans',
      TimeLimit: String(input.maxSeconds),
      TimeOut: '30',
      Record: 'false',
    });
    if (this.statusCallback) {
      body.set('StatusCallback', this.statusCallback);
      // Exotel accepts only multipart/form-data (its default) or application/json here;
      // JSON is what our body parser reads.
      body.set('StatusCallbackEvents[]', 'terminal');
      body.set('StatusCallbackContentType', 'application/json');
    }
    return {
      url: `https://${subdomain}/v1/Accounts/${encodeURIComponent(sid)}/Calls/connect.json`,
      body,
      headers: {
        Authorization: `Basic ${Buffer.from(`${key}:${token}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
      },
    };
  }

  async connect(input: ConnectInput): Promise<ConnectResult> {
    const { url, body, headers } = this.request(input);
    let res: Response;
    try {
      res = await this.fetchFn(url, { method: 'POST', headers, body, signal: AbortSignal.timeout(10_000) });
    } catch (e) {
      this.logger.error(`exotel unreachable: ${String(e)}`);
      throw new CallProviderError(`Exotel unreachable: ${String(e)}`);
    }
    const json = (await res.json().catch(() => ({}))) as ExotelConnectResponse;
    if (!res.ok || !json.Call?.Sid) {
      const reason = json.RestException?.Message ?? 'no call id returned';
      this.logger.error(`exotel ${res.status}: ${reason}`);
      throw new CallProviderError(`Exotel ${res.status}: ${reason}`);
    }
    return { providerCallId: json.Call.Sid, status: mapExotelStatus(json.Call.Status) };
  }
}

/** Picks the provider from the environment; `none` → null (apps fall back to the dialer). */
@Injectable()
export class CallProviderFactory {
  constructor(@Inject(APP_CONFIG) private readonly config: Env) {}

  create(): CallProvider | null {
    const c = this.config;
    switch (c.CALL_PROVIDER) {
      case 'none':
        return null;
      case 'stub':
        return new StubCallProvider(c.EXOTEL_CALLER_ID ?? STUB_CALLER_ID);
      case 'exotel': {
        if (!c.EXOTEL_SID || !c.EXOTEL_API_KEY || !c.EXOTEL_API_TOKEN || !c.EXOTEL_CALLER_ID) {
          throw new Error('CALL_PROVIDER=exotel needs EXOTEL_SID, EXOTEL_API_KEY, EXOTEL_API_TOKEN and EXOTEL_CALLER_ID');
        }
        const callback = c.CALL_STATUS_CALLBACK_URL
          ? c.CALL_STATUS_SECRET
            ? `${c.CALL_STATUS_CALLBACK_URL}${c.CALL_STATUS_CALLBACK_URL.includes('?') ? '&' : '?'}token=${encodeURIComponent(c.CALL_STATUS_SECRET)}`
            : c.CALL_STATUS_CALLBACK_URL
          : undefined;
        return new ExotelCallProvider(
          { sid: c.EXOTEL_SID, key: c.EXOTEL_API_KEY, token: c.EXOTEL_API_TOKEN, subdomain: c.EXOTEL_SUBDOMAIN },
          c.EXOTEL_CALLER_ID,
          callback,
        );
      }
    }
  }
}
