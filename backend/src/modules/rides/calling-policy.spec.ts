import { callingPolicyFor, STUB_CALLER_ID } from './ride.presenter';

describe('callingPolicyFor', () => {
  it('none → dialer mode (SPEC §16); stub/exotel → masked with the bridge number', () => {
    expect(callingPolicyFor({ CALL_PROVIDER: 'none', EXOTEL_CALLER_ID: '+911140001234' })).toEqual({ masked: false });
    expect(callingPolicyFor({ CALL_PROVIDER: 'exotel', EXOTEL_CALLER_ID: '+911140001234' })).toEqual({ masked: true, via: '+911140001234' });
    expect(callingPolicyFor({ CALL_PROVIDER: 'stub' })).toEqual({ masked: true, via: STUB_CALLER_ID });
  });
});
