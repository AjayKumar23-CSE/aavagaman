import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import * as Sentry from '@sentry/nestjs';
import type { Response } from 'express';
import { AppException } from './app.exception';

const DEFAULT_CODES: Record<number, string> = {
  400: 'BAD_REQUEST',
  401: 'UNAUTHORIZED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  409: 'CONFLICT',
  413: 'PAYLOAD_TOO_LARGE',
  422: 'UNPROCESSABLE_ENTITY',
  429: 'TOO_MANY_REQUESTS',
  503: 'SERVICE_UNAVAILABLE',
};

export interface ErrorBody {
  error: { code: string; message: string; details?: unknown };
}

/** Normalises every error to `{ error: { code, message } }` (SPEC §7). */
export function toErrorBody(exception: unknown): { status: number; body: ErrorBody } {
  if (exception instanceof AppException) {
    return {
      status: exception.getStatus(),
      body: { error: { code: exception.code, message: exception.message } },
    };
  }
  if (exception instanceof HttpException) {
    const status = exception.getStatus();
    const res = exception.getResponse();
    const raw = typeof res === 'string' ? res : (res as { message?: unknown }).message;
    // ValidationPipe returns an array of messages.
    if (Array.isArray(raw)) {
      return {
        status,
        body: { error: { code: 'VALIDATION_FAILED', message: 'Validation failed', details: raw } },
      };
    }
    return {
      status,
      body: {
        error: {
          code: DEFAULT_CODES[status] ?? 'ERROR',
          message: typeof raw === 'string' ? raw : exception.message,
        },
      },
    };
  }
  return {
    status: HttpStatus.INTERNAL_SERVER_ERROR,
    body: { error: { code: 'INTERNAL_ERROR', message: 'Internal server error' } },
  };
}

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const { status, body } = toErrorBody(exception);
    if (status >= 500) {
      this.logger.error(exception);
      Sentry.captureException(exception);
    }
    host.switchToHttp().getResponse<Response>().status(status).json(body);
  }
}
