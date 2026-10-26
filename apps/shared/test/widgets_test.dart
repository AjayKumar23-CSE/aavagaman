import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

void main() {
  group('OtpInput', () {
    testWidgets('shows digits in boxes and completes after 6 digits', (tester) async {
      String? completed;
      final changes = <String>[];
      await tester.pumpWidget(host(OtpInput(onCompleted: (c) => completed = c, onChanged: changes.add)));

      await tester.enterText(find.byKey(const Key('otp-field')), '123');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(completed, isNull);

      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await tester.pump();
      expect(completed, '123456');
      expect(changes.last, '123456');
    });

    testWidgets('ignores non-digits and extra characters', (tester) async {
      String? completed;
      final controller = TextEditingController();
      await tester.pumpWidget(host(OtpInput(controller: controller, onCompleted: (c) => completed = c)));

      await tester.enterText(find.byKey(const Key('otp-field')), '12a3456789');
      await tester.pump();

      expect(controller.text, '123456');
      expect(completed, '123456');
    });
  });

  group('ResendCountdown', () {
    testWidgets('counts down 30 s, then resends and restarts', (tester) async {
      var resends = 0;
      await tester.pumpWidget(host(ResendCountdown(
        onResend: () async => resends++,
        waitingLabel: (t) => 'Resend code in $t',
        resendLabel: 'Resend code',
      )));

      expect(find.text('Resend code in 0:30'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      expect(resends, 0);

      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Resend code in 0:20'), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Resend code'), findsOneWidget);

      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(resends, 1);
      expect(find.text('Resend code in 0:30'), findsOneWidget);
    });

    testWidgets('restarts the countdown even when resend fails', (tester) async {
      await tester.pumpWidget(host(ResendCountdown(
        seconds: 2,
        onResend: () async => throw const ApiException(code: 'OTP_RATE_LIMITED', message: 'slow down'),
        waitingLabel: (t) => 'wait $t',
        resendLabel: 'Resend',
      )));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Resend'));
      await tester.pump();

      expect(find.text('wait 0:02'), findsOneWidget);
    });
  });

  testWidgets('PrimaryButton shows a spinner and ignores taps while loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(PrimaryButton(label: 'Continue', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  testWidgets('ErrorBanner shows the message and retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(host(ErrorBanner(message: 'No connection', retryLabel: 'Retry', onRetry: () => retried = true)));
    expect(find.text('No connection'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('PhoneField accepts at most 10 digits', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(host(PhoneField(controller: c, label: 'Mobile number')));
    await tester.enterText(find.byType(TextField), '98x1234567890');
    expect(c.text, '9812345678');
    expect(find.text('+91'), findsOneWidget);
  });
}
