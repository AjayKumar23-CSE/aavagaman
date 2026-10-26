import 'package:driver/src/router.dart';
import 'package:driver/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

void main() {
  testWidgets('approved driver: Splash → Home placeholder with the approved note', (tester) async {
    await tester.pumpWidget(testApp(driver: FakeDriverApi(approvedProfile())));
    await tester.pumpAndSettle();

    expect(find.text('Hi Ravi Kumar'), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.byKey(const Key('online-switch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new driver: Phone → OTP (driver role) → Registration → Documents', (tester) async {
    tallScreen(tester);
    final auth = FakeAuthApi(driverUser(null));
    final api = FakeDriverApi(newDriverProfile());
    await tester.pumpWidget(testApp(driver: api, tokens: null, auth: auth, user: driverUser(null)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '9800000001');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otp-field')), '123456');
    await tester.pumpAndSettle();

    expect(auth.roles, [LoginRole.driver, LoginRole.driver]);
    expect(find.text('Your details'), findsOneWidget);

    // Client-side validation mirrors the backend DTO.
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(api.registrations, isEmpty);

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('Full name (as on licence)'), 'Ravi Kumar');
    await tester.enterText(field('Driving licence number'), 'dl04 2011-0012345');
    await tester.enterText(field('Registration number'), 'DL 01 AB 1234');
    await tester.enterText(field('Make'), 'Maruti Suzuki');
    await tester.enterText(field('Model'), 'Dzire');
    await tester.enterText(field('Colour'), 'White');
    await tester.tap(find.text('CNG'));
    await tester.tap(find.byKey(const Key('vehicle-type-auto')));

    // Licence expiry (future dates only), then date of birth (18+ only).
    await tester.tap(find.text('Select date').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('date-of-birth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final reg = api.registrations.single;
    expect(reg.licenceNo, 'DL0420110012345');
    expect(reg.vehicle.regNumber, 'DL01AB1234');
    expect(reg.vehicle.fuelType, FuelType.cng);
    expect(reg.vehicle.vehicleType, VehicleType.auto);
    expect(reg.licenceExpiry.isAfter(DateTime.now()), isTrue);
    expect(reg.dateOfBirth.isAfter(BirthDateField.latestAllowed()), isFalse);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('6 documents left to upload'), findsOneWidget);
  });

  testWidgets('rejected driver is sent back to a prefilled Registration with the note', (tester) async {
    tallScreen(tester);
    final api = FakeDriverApi(profileFrom('driver_me_pending.json', (j) {
      j['verification_status'] = 'rejected';
      j['reviewer_note'] = 'Licence photo does not match the number';
    }));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();

    expect(find.text('Your details'), findsOneWidget);
    expect(find.text('Note from our team: Licence photo does not match the number'), findsOneWidget);
    expect(find.text('DL0420110012345'), findsOneWidget);
    expect(find.text('15 Jun 1990'), findsOneWidget);
    expect(find.text('White'), findsOneWidget);
  });

  testWidgets('a date of birth under 18 is refused before submitting', (tester) async {
    tallScreen(tester);
    final young = DateTime.now().subtract(const Duration(days: 365 * 17));
    final api = FakeDriverApi(profileFrom('driver_me_pending.json', (j) {
      j['verification_status'] = 'rejected';
      j['date_of_birth'] = formatApiDate(young);
    }));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.text('You must be at least 18 years old to drive'), findsOneWidget);
    expect(api.registrations, isEmpty);
  });

  testWidgets('suspended driver sees "Account paused, contact support"', (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_pending.json', (j) {
      j['verification_status'] = 'suspended';
    }));
    await tester.pumpWidget(testApp(driver: api));
    await tester.pumpAndSettle();

    expect(find.text('Account paused, contact support'), findsOneWidget);
  });

  group('gateFor / driverRedirect', () {
    test('onboarding order', () {
      expect(gateFor(newDriverProfile()), Routes.register);
      expect(gateFor(profileFrom('driver_me_pending.json')), Routes.documents);
      expect(gateFor(profileFrom('driver_me_rejected_doc.json')), Routes.pending);
      expect(gateFor(approvedProfile()), Routes.home);
    });

    test('redirects', () {
      final li = SessionLoggedIn(driverUser());
      expect(driverRedirect(const SessionUnknown(), null, Routes.home), Routes.splash);
      expect(driverRedirect(const SessionLoggedOut(), null, Routes.pending), Routes.phone);
      expect(driverRedirect(li, null, Routes.home), Routes.splash);
      final pending = profileFrom('driver_me_rejected_doc.json');
      expect(driverRedirect(li, pending, Routes.splash), Routes.pending);
      expect(driverRedirect(li, pending, Routes.documents), isNull);
      expect(driverRedirect(li, pending, Routes.home), Routes.pending);
      expect(driverRedirect(li, approvedProfile(), Routes.pending), Routes.home);
      expect(driverRedirect(li, approvedProfile(), Routes.register), Routes.home);
    });
  });
}
