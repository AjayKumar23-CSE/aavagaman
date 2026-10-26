import { createServer, Server } from 'node:http';

/**
 * Stand-in for api.razorpay.com: creates orders and lists an order's payments.
 * Tests mark an order captured via the control endpoint POST /__test/capture.
 */
export const FAKE_RAZORPAY_PORT = 5056;

interface FakePayment {
  id: string;
  order_id: string;
  status: string;
  method: string;
  amount: number;
}

export function startFakeRazorpay(): Promise<Server> {
  const orders = new Map<string, { id: string; amount: number; receipt: string }>();
  const payments = new Map<string, FakePayment[]>();
  // Razorpay ids are random; unique across runs so stale rows in the test DB never match.
  const run = Date.now().toString(36);
  let seq = 0;

  const server = createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      res.setHeader('content-type', 'application/json');
      const body = raw ? JSON.parse(raw) : {};
      const url = req.url ?? '';
      if (req.method === 'POST' && url === '/v1/orders') {
        if (!/^Basic /.test(req.headers.authorization ?? '')) {
          res.statusCode = 401;
          return res.end(JSON.stringify({ error: { description: 'auth' } }));
        }
        const id = `order_${run}${++seq}`;
        orders.set(id, { id, amount: body.amount, receipt: body.receipt });
        return res.end(
          JSON.stringify({
            id,
            amount: body.amount,
            currency: 'INR',
            receipt: body.receipt,
            status: 'created',
          }),
        );
      }
      const list = /^\/v1\/orders\/([^/]+)\/payments$/.exec(url);
      if (req.method === 'GET' && list) {
        const items = payments.get(list[1]) ?? [];
        return res.end(JSON.stringify({ entity: 'collection', count: items.length, items }));
      }
      if (req.method === 'POST' && url === '/__test/capture') {
        const order = orders.get(body.order_id);
        if (!order) {
          res.statusCode = 404;
          return res.end('{}');
        }
        const p: FakePayment = {
          id: body.payment_id ?? `pay_${run}${++seq}`,
          order_id: order.id,
          status: 'captured',
          method: body.method ?? 'upi',
          amount: order.amount,
        };
        payments.set(order.id, [...(payments.get(order.id) ?? []), p]);
        return res.end(JSON.stringify(p));
      }
      res.statusCode = 404;
      res.end(JSON.stringify({ error: { description: 'not found' } }));
    });
  });
  return new Promise((resolve) => server.listen(FAKE_RAZORPAY_PORT, () => resolve(server)));
}
