import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('scrubText masks phones, JWTs and bearer tokens', () {
    expect(scrubText('login failed for +919812345678'), 'login failed for ******5678');
    expect(scrubText('call 98123 45678 now'), 'call ******5678 now');
    expect(scrubText('Bearer abc.def'), 'Bearer [Filtered]');
    expect(scrubText('t=eyJhbGciOi.eyJzdWIiOi.sig-_x'), 't=[Filtered]');
    expect(scrubText('ride 12345 cost 250'), 'ride 12345 cost 250');
  });

  test('scrubValue drops sensitive keys recursively', () {
    expect(
      scrubValue({
        'phone': '+919812345678',
        'nested': {'refresh_token': 'r', 'fcm_token': 'f', 'city': 'Delhi'},
        'list': ['9812345678'],
        'code': '123456',
        'error_code': 'OTP_INVALID',
      }),
      {
        'phone': '[Filtered]',
        'nested': {'refresh_token': '[Filtered]', 'fcm_token': '[Filtered]', 'city': 'Delhi'},
        'list': ['******5678'],
        'code': '[Filtered]',
        'error_code': 'OTP_INVALID',
      },
    );
  });

  test('beforeSend strips user PII, request headers/body and breadcrumbs', () async {
    final event = SentryEvent(
      message: SentryMessage('OTP sent to +919812345678'),
      user: SentryUser(id: 'u1', username: '+919812345678', email: 'a@b.c'),
      request: SentryRequest(
        url: 'http://api/v1/auth/otp/verify',
        headers: {'Authorization': 'Bearer secret', 'Accept': 'application/json'},
        data: {'phone': '+919812345678', 'role': 'rider'},
      ),
      breadcrumbs: [
        Breadcrumb(message: 'POST phone=9812345678', data: {'access_token': 'x', 'status': 200}),
      ],
      exceptions: [SentryException(type: 'ApiException', value: 'bad phone 9812345678')],
    );

    final out = (await scrubSentryEvent(event, Hint()))!;

    expect(out.message!.formatted, 'OTP sent to ******5678');
    expect(out.user!.id, 'u1');
    expect(out.user!.username, isNull);
    expect(out.user!.email, isNull);
    expect(out.request!.headers['Authorization'], '[Filtered]');
    expect(out.request!.headers['Accept'], 'application/json');
    expect(out.request!.data, {'phone': '[Filtered]', 'role': 'rider'});
    expect(out.breadcrumbs!.single.message, 'POST phone=******5678');
    expect(out.breadcrumbs!.single.data, {'access_token': '[Filtered]', 'status': 200});
    expect(out.exceptions!.single.value, 'bad phone ******5678');
  });
}
