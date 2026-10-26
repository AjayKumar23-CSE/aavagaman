import type { Server } from 'node:http';

export default async function globalTeardown() {
  const g = globalThis as { __osrm?: Server; __razorpay?: Server };
  for (const server of [g.__osrm, g.__razorpay]) {
    await new Promise((resolve) => (server ? server.close(resolve) : resolve(undefined)));
  }
}
