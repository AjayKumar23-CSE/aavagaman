import type { Payment } from '@prisma/client';

export function presentPayment(p: Payment) {
  return {
    id: p.id,
    ride_id: p.rideId,
    method: p.method,
    amount: Number(p.amount),
    status: p.status,
    gateway_order_id: p.gatewayOrderId,
    gateway_payment_id: p.gatewayPaymentId,
    paid_at: p.paidAt,
    created_at: p.createdAt,
  };
}
