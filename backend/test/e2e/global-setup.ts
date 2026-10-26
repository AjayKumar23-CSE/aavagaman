import { startFakeOsrm } from './fake-osrm';
import { startFakeRazorpay } from './fake-razorpay';

export default async function globalSetup() {
  const g = globalThis as { __osrm?: unknown; __razorpay?: unknown };
  g.__osrm = await startFakeOsrm();
  g.__razorpay = await startFakeRazorpay();
}
