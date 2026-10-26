import { Body, Controller, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { PaymentsService } from './payments.service';

export class VerifyPaymentDto {
  @ApiProperty() @IsString() @Length(1, 100) razorpay_order_id: string;
  @ApiProperty() @IsString() @Length(1, 100) razorpay_payment_id: string;
  @ApiProperty() @IsString() @Length(32, 200) razorpay_signature: string;
}

@ApiTags('rider')
@ApiBearerAuth()
@Roles('rider')
@Controller('rides/:id/payment')
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Post('order')
  @HttpCode(HttpStatus.OK)
  order(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.createOrder(u.id, id);
  }

  @Post('verify')
  @HttpCode(HttpStatus.OK)
  verify(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: VerifyPaymentDto,
  ) {
    return this.payments.verify(u.id, id, dto);
  }
}
