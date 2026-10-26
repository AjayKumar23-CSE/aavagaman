import { HttpException, HttpStatus } from '@nestjs/common';

/** Domain error carrying a stable machine-readable code (SPEC §7 error shape). */
export class AppException extends HttpException {
  constructor(
    public readonly code: string,
    message: string,
    status: HttpStatus,
  ) {
    super({ code, message }, status);
  }
}
