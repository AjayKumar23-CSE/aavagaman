import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:rider/src/pages/history_page.dart';

import 'helpers.dart';

Future<FakeRideApi> launchHome(WidgetTester tester, {required List<Ride> history, RideReceipt? receipt}) async {
  tallScreen(tester);
  final api = FakeRideApi()
    ..historyRides = history
    ..receiptResult = receipt;
  await tester.pumpWidget(testApp(auth: FakeAuthApi(), me: FakeMeApi(rider(name: 'Asha')), tokens: saved, rides: api));
  await tester.pumpAndSettle();
  return api;
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('menu-history')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drawer → Ride history lists rides with status and amount; detail shows receipt, timeline and Rate',
      (tester) async {
    final rides = RidePageResult.fromJson(fixture('rides_page1.json')).data;
    final api = await launchHome(tester, history: rides, receipt: RideReceipt.fromJson(fixture('receipt_paid_cash.json')));

    await openHistory(tester);
    expect(find.text('Ride history'), findsOneWidget);
    expect(find.byType(RideHistoryTile), findsNWidgets(6));
    expect(api.historyCalls.single, (page: 1, limit: 20));
    expect(find.textContaining('Paid'), findsOneWidget);
    expect(find.textContaining('No driver found'), findsOneWidget);
    expect(find.textContaining('Cancelled'), findsNWidgets(4));
    expect(find.text('₹118'), findsOneWidget); // the paid ride's amount_due
    expect(find.text('₹30'), findsNWidgets(1)); // only the late cancel carries a fee
    expect(find.byKey(const Key('history-load-more')), findsNothing);

    final paid = rides.singleWhere((r) => r.status == RideStatus.paid);
    await tester.tap(find.byKey(Key('history-${paid.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Ride details'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('detail-status')), matching: find.text('Paid')), findsOneWidget);
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('Trip fare'), findsOneWidget);
    expect(find.text('Includes ₹4.19 GST'), findsOneWidget);
    expect(find.text('Cancellation fee (earlier ride)'), findsOneWidget);
    expect(find.text('₹118'), findsOneWidget);
    expect(find.text('Paid · Cash'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Trip started'), findsOneWidget);
    expect(find.text('Phase Two Driver'), findsOneWidget);
    expect(find.textContaining('pickup,drop lines:route'), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-rate')));
    await tester.pumpAndSettle();
    expect(find.text('How was your trip?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('star-4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rate-submit')));
    await tester.pumpAndSettle();

    expect(api.rated.single, (id: paid.id, stars: 4, comment: ''));
    expect(find.text('Thanks for your feedback'), findsOneWidget);
    expect(find.byKey(const Key('detail-rate')), findsNothing);
    expect(find.text("You've already rated this ride."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ALREADY_RATED hides the Rate button; a cancelled ride shows who cancelled and the fee', (tester) async {
    final rides = RidePageResult.fromJson(fixture('rides_page1.json')).data;
    final api = await launchHome(tester, history: rides, receipt: RideReceipt.fromJson(fixture('receipt_paid_cash.json')));
    api.rateError = const ApiException(code: 'ALREADY_RATED', message: 'You have already rated this ride', statusCode: 409);
    await openHistory(tester);

    final paid = rides.singleWhere((r) => r.status == RideStatus.paid);
    await tester.tap(find.byKey(Key('history-${paid.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-rate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('star-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rate-submit')));
    await tester.pumpAndSettle();
    expect(find.text("You've already rated this ride."), findsWidgets);
    expect(find.byKey(const Key('detail-rate')), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final cancelled = rides.firstWhere((r) => r.status == RideStatus.cancelled && (r.cancellationFee ?? 0) > 0);
    await tester.tap(find.byKey(Key('history-${cancelled.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled by you'), findsOneWidget);
    expect(find.text('Reason: Changed plans'), findsOneWidget);
    expect(find.text('Cancellation fee: ₹30'), findsOneWidget);
    expect(find.text('Receipt'), findsNothing);
    expect(find.byKey(const Key('detail-rate')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Load more fetches the next page; empty state', (tester) async {
    final many = [
      for (var i = 0; i < 25; i++)
        rideFrom('ride_paid_rider_view.json', (j) {
          j['id'] = 'ride-$i';
          j['paid_at'] = DateTime.utc(2026, 10, 1).subtract(Duration(hours: i)).toIso8601String();
        }),
    ];
    final api = await launchHome(tester, history: many);
    await openHistory(tester);
    expect(api.historyCalls, [(page: 1, limit: 20)]);

    await tester.scrollUntilVisible(find.byKey(const Key('history-load-more')), 300);
    await tester.tap(find.byKey(const Key('history-load-more')));
    await tester.pumpAndSettle();
    expect(api.historyCalls, [(page: 1, limit: 20), (page: 2, limit: 20)]);
    expect(find.byKey(const Key('history-load-more')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('history-ride-24')), 300);
    expect(find.byKey(const Key('history-ride-24')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await launchHome(tester, history: const []);
    await openHistory(tester);
    expect(find.text('No rides yet. Your trips will appear here.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
