import { ExotelCallProvider, mapExotelStatus, StubCallProvider } from './call.provider';

describe('mapExotelStatus', () => {
  it('maps Exotel statuses, unknown → failed', () => {
    expect(mapExotelStatus('queued')).toBe('initiated');
    expect(mapExotelStatus('ringing')).toBe('ringing');
    expect(mapExotelStatus('in-progress')).toBe('in_progress');
    expect(mapExotelStatus('completed')).toBe('completed');
    expect(mapExotelStatus('no-answer')).toBe('no_answer');
    expect(mapExotelStatus('busy')).toBe('busy');
    expect(mapExotelStatus('failed')).toBe('failed');
    expect(mapExotelStatus(undefined)).toBe('failed');
  });
});

describe('ExotelCallProvider', () => {
  const creds = { sid: 'acct', key: 'k', token: 't', subdomain: 'api.in.exotel.com' };

  it('builds the Connect request: caller first, ExoPhone as caller id, basic auth', () => {
    const p = new ExotelCallProvider(creds, '+911140001234', 'https://api.example.com/v1/webhooks/calls/exotel?token=s');
    const { url, body, headers } = p.request({ from: '+919811000001', to: '+919811000002', maxSeconds: 600 });
    expect(url).toBe('https://api.in.exotel.com/v1/Accounts/acct/Calls/connect.json');
    expect(body.get('From')).toBe('+919811000001');
    expect(body.get('To')).toBe('+919811000002');
    expect(body.get('CallerId')).toBe('+911140001234');
    expect(body.get('TimeLimit')).toBe('600');
    expect(body.get('Record')).toBe('false');
    expect(body.get('StatusCallback')).toBe('https://api.example.com/v1/webhooks/calls/exotel?token=s');
    expect(body.get('StatusCallbackEvents[]')).toBe('terminal');
    // Exotel rejects anything but multipart/form-data or application/json (400 "Invalid StatusCallbackContentType").
    expect(body.get('StatusCallbackContentType')).toBe('application/json');
    expect(headers.Authorization).toBe(`Basic ${Buffer.from('k:t').toString('base64')}`);
  });

  it('returns the call sid and status on success', async () => {
    const fetchFn = jest.fn(async () => new Response(JSON.stringify({ Call: { Sid: 'abc', Status: 'in-progress' } }), { status: 200 }));
    const p = new ExotelCallProvider(creds, '+911140001234', undefined, fetchFn as unknown as typeof fetch);
    await expect(p.connect({ from: '+91a', to: '+91b', maxSeconds: 60 })).resolves.toEqual({ providerCallId: 'abc', status: 'in_progress' });
    expect(fetchFn).toHaveBeenCalledTimes(1);
  });

  it('turns provider errors into CALL_FAILED (502)', async () => {
    const fetchFn = jest.fn(async () => new Response(JSON.stringify({ RestException: { Message: 'Invalid number' } }), { status: 400 }));
    const p = new ExotelCallProvider(creds, '+911140001234', undefined, fetchFn as unknown as typeof fetch);
    await expect(p.connect({ from: '+91a', to: '+91b', maxSeconds: 60 })).rejects.toMatchObject({
      code: 'CALL_FAILED',
      detail: 'Exotel 400: Invalid number',
    });
    const down = new ExotelCallProvider(creds, '+911140001234', undefined, (async () => { throw new Error('ECONNREFUSED'); }) as unknown as typeof fetch);
    await expect(down.connect({ from: '+91a', to: '+91b', maxSeconds: 60 })).rejects.toMatchObject({ code: 'CALL_FAILED' });
  });
});

describe('StubCallProvider', () => {
  it('records a call without ringing anyone', async () => {
    const p = new StubCallProvider('+911140000000');
    const r = await p.connect({ from: '+91a', to: '+91b', maxSeconds: 60 });
    expect(r.providerCallId).toMatch(/^stub_/);
    expect(r.status).toBe('initiated');
  });
});
