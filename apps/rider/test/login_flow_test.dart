import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/router.dart';

import 'helpers.dart';

Future<void> enterPhone(WidgetTester tester, String phone) async {
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), phone);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Phone → OTP → Name → Home for a first-time rider', (tester) async {
    final auth = FakeAuthApi();
    final me = FakeMeApi(rider());
    await tester.pumpWidget(testApp(auth: auth, me: me));

    await enterPhone(tester, '9800000002');

    expect(auth.sent, ['+919800000002']);
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Sent by SMS to +91 98000 00002'), findsOneWidget);
    expect(find.text('Resend code in 0:30'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();

    expect(auth.verified.single.code, '123456');
    expect(auth.verified.single.device.toJson(), {'platform': 'android', 'app_version': '0.1.0+1'});
    // name == null → Name screen.
    expect(find.text("What's your name?"), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  Asha  ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(me.updates.single.name, 'Asha');
    expect(find.text('Hi Asha'), findsOneWidget);
  });

  testWidgets('returning rider with a name skips the Name screen', (tester) async {
    final auth = FakeAuthApi()..user = rider(name: 'Ravi');
    await tester.pumpWidget(testApp(auth: auth, me: FakeMeApi(rider(name: 'Ravi'))));

    await enterPhone(tester, '+91 98000 00002');
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();

    expect(find.text('Hi Ravi'), findsOneWidget);
  });

  testWidgets('invalid phone is rejected locally', (tester) async {
    final auth = FakeAuthApi();
    await tester.pumpWidget(testApp(auth: auth, me: FakeMeApi(rider())));

    await enterPhone(tester, '12345');

    expect(find.text('Enter a valid 10-digit Indian mobile number'), findsOneWidget);
    expect(auth.sent, isEmpty);
  });

  testWidgets('send rate limit (429) shows the server message', (tester) async {
    final auth = FakeAuthApi()
      ..sendError = const ApiException(
          code: 'OTP_RATE_LIMITED', message: 'Too many code requests. Try again later.', statusCode: 429);
    await tester.pumpWidget(testApp(auth: auth, me: FakeMeApi(rider())));

    await enterPhone(tester, '9800000002');

    expect(find.text('Too many code requests. Try again later.'), findsOneWidget);
    expect(find.text('Enter your mobile number'), findsOneWidget);
  });

  testWidgets('wrong code shows OTP_INVALID; resend after 30 s handles 429', (tester) async {
    final auth = FakeAuthApi()
      ..verifyError = const ApiException(code: 'OTP_INVALID', message: 'Invalid or expired code', statusCode: 401);
    await tester.pumpWidget(testApp(auth: auth, me: FakeMeApi(rider())));
    await enterPhone(tester, '9800000002');

    await tester.enterText(find.byKey(const Key('otp-field')), '000000');
    await tester.pumpAndSettle();
    expect(find.text('Invalid or expired code'), findsOneWidget);
    expect(find.text('Enter the code'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code'), findsOneWidget);

    auth.sendError = const ApiException(
        code: 'OTP_RATE_LIMITED', message: 'Too many code requests. Try again later.', statusCode: 429);
    await tester.tap(find.text('Resend code'));
    await tester.pump();

    expect(auth.sent, hasLength(2));
    expect(find.text('Too many code requests. Try again later.'), findsOneWidget);
    expect(find.text('Resend code in 0:30'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ROLE_MISMATCH (driver number) is explained', (tester) async {
    final auth = FakeAuthApi()
      ..verifyError = const ApiException(
          code: 'ROLE_MISMATCH',
          message: 'This number is registered as a driver. Use the driver app.',
          statusCode: 403);
    await tester.pumpWidget(testApp(auth: auth, me: FakeMeApi(rider())));
    await enterPhone(tester, '9800000002');
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();

    expect(find.text('This number is registered as a driver. Use the driver app.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('riderRedirect', () {
    const out = SessionLoggedOut();
    test('unknown session always shows Splash', () {
      expect(riderRedirect(const SessionUnknown(), Routes.home), Routes.splash);
      expect(riderRedirect(const SessionUnknown(), Routes.splash), isNull);
    });
    test('logged out stays in Phone/OTP', () {
      expect(riderRedirect(out, Routes.splash), Routes.phone);
      expect(riderRedirect(out, Routes.profile), Routes.phone);
      expect(riderRedirect(out, Routes.otp), isNull);
    });
    test('logged in without a name is held on Name', () {
      expect(riderRedirect(SessionLoggedIn(rider()), Routes.home), Routes.name);
      expect(riderRedirect(SessionLoggedIn(rider()), Routes.name), isNull);
    });
    test('logged in leaves the auth flow for Home', () {
      final s = SessionLoggedIn(rider(name: 'A'));
      expect(riderRedirect(s, Routes.otp), Routes.home);
      expect(riderRedirect(s, Routes.name), Routes.home);
      expect(riderRedirect(s, Routes.profile), isNull);
    });
  });
}
