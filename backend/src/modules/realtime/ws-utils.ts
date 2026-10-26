import { HttpException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { AppException } from '../../common/app.exception';
import { toErrorBody } from '../../common/http-exception.filter';

export type Ack<T> =
  { ok: true; data?: T } | { ok: false; error: { code: string; message: string } };

/** Validates a WebSocket payload with the same rules as REST DTOs. */
export async function parseWs<T extends object>(cls: new () => T, payload: unknown): Promise<T> {
  const obj = plainToInstance(cls, payload ?? {});
  const errors = await validate(obj, { whitelist: true, forbidNonWhitelisted: true });
  if (errors.length) {
    const msg = errors.flatMap((e) => Object.values(e.constraints ?? {})).join('; ');
    throw new AppException('VALIDATION_FAILED', msg || 'Invalid payload', 400);
  }
  return obj;
}

/** Runs a handler and turns errors into an acknowledgement with the REST error shape. */
export async function ack<T>(fn: () => Promise<T>): Promise<Ack<T>> {
  try {
    const data = await fn();
    return data === undefined ? { ok: true } : { ok: true, data };
  } catch (err) {
    const { body } = toErrorBody(err instanceof HttpException ? err : err);
    return { ok: false, error: { code: body.error.code, message: body.error.message } };
  }
}
