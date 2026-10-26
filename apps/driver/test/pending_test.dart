import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('Pending shows status and the rejected document with its note', (tester) async {
    tallScreen(tester);
    final api = FakeDriverApi(profileFrom('driver_me_rejected_doc.json', (j) {
      j['reviewer_note'] = 'Please fix your RC';
    }));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();

    expect(find.text('Your profile is under review'), findsOneWidget);
    expect(find.text('Note from our team: Please fix your RC'), findsOneWidget);
    expect(find.text('Needs your attention'), findsOneWidget);
    expect(find.text('Registration certificate (RC)'), findsOneWidget);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('RC photo is blurry, please re-upload'), findsOneWidget);
    expect(find.text('Fix documents'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('polls GET /driver/me every 15 s and moves to Home once approved', (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_rejected_doc.json'));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();
    expect(find.text('Your profile is under review'), findsOneWidget);
    final initialCalls = api.meCalls;

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(api.meCalls, initialCalls + 1);
    expect(find.text('Your profile is under review'), findsOneWidget);

    api.profile = approvedProfile();
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(find.text("You're offline"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refreshes when the app returns to the foreground', (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_rejected_doc.json'));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();
    final before = api.meCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.meCalls, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pull-to-refresh re-fetches the profile', (tester) async {
    tallScreen(tester);
    final api = FakeDriverApi(profileFrom('driver_me_rejected_doc.json'));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();
    final before = api.meCalls;

    // Far enough to arm the indicator on the tall test viewport.
    await tester.fling(find.byType(ListView), const Offset(0, 900), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(api.meCalls, before + 1);
    await tester.pumpWidget(const SizedBox());
  });
}
