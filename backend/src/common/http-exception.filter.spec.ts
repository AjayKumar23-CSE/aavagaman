import { BadRequestException, HttpStatus, NotFoundException } from '@nestjs/common';
import { AppException } from './app.exception';
import { toErrorBody } from './http-exception.filter';

describe('toErrorBody', () => {
  it('keeps the code of an AppException', () => {
    const r = toErrorBody(
      new AppException('RIDE_NOT_CANCELLABLE', 'Ride cannot be cancelled', HttpStatus.CONFLICT),
    );
    expect(r).toEqual({
      status: 409,
      body: { error: { code: 'RIDE_NOT_CANCELLABLE', message: 'Ride cannot be cancelled' } },
    });
  });

  it('maps validation arrays to VALIDATION_FAILED', () => {
    const r = toErrorBody(new BadRequestException(['phone must be a string']));
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('VALIDATION_FAILED');
    expect(r.body.error.details).toEqual(['phone must be a string']);
  });

  it('derives a code from the status for plain HttpExceptions', () => {
    expect(toErrorBody(new NotFoundException('nope')).body.error).toEqual({
      code: 'NOT_FOUND',
      message: 'nope',
    });
  });

  it('hides internals of unknown errors', () => {
    const r = toErrorBody(new Error('db password is hunter2'));
    expect(r.status).toBe(500);
    expect(r.body.error.message).toBe('Internal server error');
  });
});
