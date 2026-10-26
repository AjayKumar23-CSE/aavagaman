import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

Future<FakeRideApi> launchHome(WidgetTester tester) async {
  tallScreen(tester);
  final page = RidePageResult.fromJson(fixture('driver_rides_page1.json'));
  final rides = FakeRideApi()
    ..earnings[EarningsPeriod.today] = DriverEarnings.fromJson(fixture('driver_earnings_today.json'))
    ..earnings[EarningsPeriod.week] = DriverEarnings.fromJson(fixture('driver_earnings_week.json'))
    ..historyRides = page.data;
  await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), rides: rides));
  await tester.pumpAndSettle();
  return rides;
}

Future<void> openDrawerItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("Home shows today's net earnings and trip count", (tester) async {
    await launchHome(tester);
    expect(tester.widget<Text>(find.byKey(const Key('home-earnings'))).data, '₹71.24 · 1 trip');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drawer → Earnings: today/week cards and per-trip fare, commission, net', (tester) async {
    final rides = await launchHome(tester);
    await openDrawerItem(tester, 'Earnings');

    expect(rides.earningsCalls, containsAll([EarningsPeriod.today, EarningsPeriod.week]));
    expect(tester.widget<Text>(find.byKey(const Key('earnings-today-net'))).data, '₹71.24');
    final week = DriverEarnings.fromJson(fixture('driver_earnings_week.json'));
    expect(tester.widget<Text>(find.byKey(const Key('earnings-week-net'))).data, formatAmount(week.net));
    // Only the paid ride carries an earning split.
    expect(find.textContaining('Fare ₹88 · Commission ₹12.57 · GST ₹4.19'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('earnings error shows the message with Retry', (tester) async {
    tallScreen(tester);
    final rides = FakeRideApi()
      ..earningsError = const ApiException(code: 'NETWORK_ERROR', message: 'offline');
    await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile()), rides: rides));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('home-earnings'))).data, '—');
    await openDrawerItem(tester, 'Earnings');
    expect(find.text("Couldn't load this. Check your connection."), findsNWidgets(2));

    rides.earningsError = null;
    await tester.tap(find.text('Retry').first);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this. Check your connection."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('drawer → Trip history: status, who cancelled, net amount; Load more', (tester) async {
    final rides = await launchHome(tester);
    final base = RidePageResult.fromJson(fixture('driver_rides_page1.json')).data;
    rides.historyRides = [for (var i = 0; i < 8; i++) ...base].indexed
        .map((e) => Ride.fromJson({...fixture('driver_rides_page1.json')['data'][e.$1 % 3] as Map<String, dynamic>, 'id': 'r${e.$1}'}))
        .toList();
    await openDrawerItem(tester, 'Trip history');

    expect(rides.historyCalls.first, (page: 1, limit: 20));
    expect(find.textContaining('Paid'), findsWidgets);
    expect(find.text('₹71.24'), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const Key('history-more')), 300);
    await tester.tap(find.byKey(const Key('history-more')));
    await tester.pumpAndSettle();
    expect(rides.historyCalls.last, (page: 2, limit: 20));
    await tester.scrollUntilVisible(find.byKey(const Key('history-r23')), 300);
    expect(find.byKey(const Key('history-more')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
