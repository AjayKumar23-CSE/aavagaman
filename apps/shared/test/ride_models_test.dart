import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

void main() {
  group('Ride (real API payloads)', () {
    test('POST /rides → REQUESTED ride, rider view', () {
      final r = Ride.fromJson(fixture('ride_requested.json'));
      expect(r.status, RideStatus.requested);
      expect(r.isSearching, isTrue);
      expect(r.vehicleType, 'sedan');
      expect(r.paymentMethod, PaymentMethod.cash);
      expect(r.pickup, const RidePlace(lat: 28.6315, lng: 77.2167, address: 'Connaught Place, New Delhi'));
      expect(r.drop.address, 'India Gate, New Delhi');
      expect(r.estDistanceM, 3141);
      expect(r.estDurationS, 449);
      expect(r.estFareMin, 94);
      expect(r.estFareMax, 109);
      expect(r.finalFare, isNull);
      expect(r.cancellationFee, 0);
      expect(r.fareConfigId, isNotEmpty);
      expect(r.requestedAt, isNotNull);
      expect(r.acceptedAt, isNull);
      // OTP is hidden until a driver accepts; the share token exists from creation.
      expect(r.tripOtp, isNull);
      expect(r.shareToken, hasLength(32));
      expect(r.driver, isNull);
      expect(r.rider, isNull);
    });

    test('GET /rides/:id → ACCEPTED ride with driver, OTP and masked phone', () {
      final r = Ride.fromJson(fixture('ride_accepted_rider_view.json'));
      expect(r.status, RideStatus.accepted);
      expect(r.status.isActive, isTrue);
      expect(r.acceptedAt, isNotNull);
      expect(r.tripOtp, matches(RegExp(r'^\d{4}$')));
      final d = r.driver!;
      expect(d.name, 'Phase Two Driver');
      expect(d.rating, 5);
      expect(d.phoneMasked, matches(RegExp(r'^\*+0777$')));
      expect(d.phone, isNull);
      expect(d.canCall, isFalse);
      expect(d.vehicle!.regNumber, 'DL01CP2002');
      expect(d.vehicle!.label, 'White Maruti Suzuki Dzire');
    });

    test('GET /driver/rides/active → driver view has rider, no OTP', () {
      final r = Ride.fromJson(fixture('ride_accepted_driver_view.json'));
      expect(r.status, RideStatus.accepted);
      expect(r.tripOtp, isNull);
      expect(r.shareToken, isNull);
      expect(r.rider!.name, 'Phase Two Rider');
      expect(r.rider!.phoneMasked, endsWith('0778'));
      expect(r.rider!.phone, isNull);
      expect(r.driver!.id, isNotEmpty);
    });

    test('cancelled while REQUESTED', () {
      final r = Ride.fromJson(fixture('ride_cancelled_by_rider.json'));
      expect(r.status, RideStatus.cancelled);
      expect(r.status.isTerminal, isTrue);
      expect(r.cancelledBy, CancelActor.rider);
      expect(r.cancellationFee, 0);
      expect(r.cancelledAt, isNotNull);
      expect(r.paymentMethod, PaymentMethod.online);
    });

    test('NUMERIC fields as strings and unknown payment method are tolerated', () {
      final json = fixture('ride_requested.json')
        ..['est_fare_min'] = '94.00'
        ..['est_fare_max'] = '109.50'
        ..['est_distance_m'] = '3141'
        ..['payment_method'] = 'upi';
      final r = Ride.fromJson(json);
      expect(r.estFareMin, 94);
      expect(r.estFareMax, 109.5);
      expect(r.estDistanceM, 3141);
      expect(r.paymentMethod, PaymentMethod.cash);
    });

    test('apply() merges a ride:status event (REQUESTED → ACCEPTED)', () {
      final r = Ride.fromJson(fixture('ride_requested.json'));
      final ev = RideStatusEvent.fromJson(fixture('ws_ride_status_accepted_rider.json'));
      final now = DateTime.utc(2026, 10, 4, 6);
      final a = r.apply(ev, now: now);
      expect(a.status, RideStatus.accepted);
      expect(a.driver!.vehicle!.regNumber, 'DL01CP2002');
      expect(a.tripOtp, ev.tripOtp);
      expect(a.acceptedAt, now);
      // Unchanged fields survive the merge.
      expect(a.pickup, r.pickup);
      expect(a.shareToken, r.shareToken);
      // An event for another ride is ignored.
      expect(r.apply(const RideStatusEvent(rideId: 'other', status: RideStatus.cancelled)).status,
          RideStatus.requested);
    });

    test('apply() CANCELLED clears the OTP and keeps the reason', () {
      final r = Ride.fromJson(fixture('ride_accepted_rider_view.json'));
      final c = r.apply(RideStatusEvent.fromJson({
        'ride_id': r.id,
        'status': 'CANCELLED',
        'cancellation_fee': '30.00',
        'cancelled_by': 'driver',
        'cancel_reason': 'Vehicle breakdown',
      }));
      expect(c.status, RideStatus.cancelled);
      expect(c.tripOtp, isNull);
      expect(c.cancellationFee, 30);
      expect(c.cancelledBy, CancelActor.driver);
      expect(c.cancelReason, 'Vehicle breakdown');
    });
  });

  group('WebSocket payloads (real)', () {
    test('ride:offer', () {
      final o = RideOffer.fromJson(fixture('ws_ride_offer.json'));
      expect(o.rideId, hasLength(36));
      expect(o.pickup.address, 'Connaught Place, New Delhi');
      expect(o.dropAddress, 'India Gate, New Delhi');
      expect(o.distanceToPickupM, 148);
      expect(o.estFareMin, 94);
      expect(o.estFareMax, 109);
      expect(o.expiresAt.isUtc, isTrue);
      expect(o.remaining(o.expiresAt.subtract(const Duration(seconds: 12))), const Duration(seconds: 12));
      expect(o.remaining(o.expiresAt.add(const Duration(seconds: 1))), Duration.zero);
    });

    test('ride:status for rider carries trip_otp; for driver it does not', () {
      final rider = RideStatusEvent.fromJson(fixture('ws_ride_status_accepted_rider.json'));
      expect(rider.status, RideStatus.accepted);
      expect(rider.tripOtp, matches(RegExp(r'^\d{4}$')));
      expect(rider.driver!.name, 'Phase Two Driver');
      expect(rider.reassigned, isFalse);
      final driver = RideStatusEvent.fromJson(fixture('ws_ride_status_accepted_driver.json'));
      expect(driver.tripOtp, isNull);
      expect(driver.driver!.vehicle!.model, 'Dzire');
      final requested = RideStatusEvent.fromJson(fixture('ws_ride_status_requested.json'));
      expect(requested.status, RideStatus.requested);
      expect(requested.driver, isNull);
    });

    test('ride:status CANCELLED and the reassigned flag', () {
      final c = RideStatusEvent.fromJson(fixture('ws_ride_status_cancelled.json'));
      expect(c.status, RideStatus.cancelled);
      expect(c.cancellationFee, 0);
      expect(c.cancelledBy, CancelActor.rider);
      expect(c.cancelReason, isNull);
      final lost = RideStatusEvent.fromJson({'ride_id': 'x', 'status': 'CANCELLED', 'reassigned': true});
      expect(lost.reassigned, isTrue);
    });

    test('driver:position with eta_s', () {
      final p = DriverPosition.fromJson(fixture('ws_driver_position.json'));
      expect(p.lat, closeTo(28.63, 0.01));
      expect(p.heading, 225);
      expect(p.etaS, 25);
      expect(p.rideId, isNotEmpty);
      final noEta = DriverPosition.fromJson({'ride_id': 'r', 'driver_id': 'd', 'lat': 1, 'lng': 2, 'heading': 0});
      expect(noEta.etaS, isNull);
    });
  });

  test('FareEstimate parses in_service_area flags', () {
    final e = FareEstimate.fromJson(fixture('fare_estimate.json'));
    expect(e.distanceM, 3141);
    expect(e.durationS, 449);
    expect(e.fareMin, 94);
    expect(e.fareMax, 109);
    expect(e.currency, 'INR');
    expect(e.pickupInArea, isTrue);
    expect(e.dropInArea, isTrue);
    expect(e.fareConfigId, hasLength(36));
    final out = FareEstimate.fromJson(fixture('fare_estimate_drop_outside.json'));
    expect(out.dropInArea, isFalse);
    expect(out.pickupInArea, isTrue);
  });

  test('NearbyDriver parses the anonymised list', () {
    final list = [
      for (final d in fixtureList('drivers_nearby.json'))
        NearbyDriver.fromJson((d as Map).cast<String, dynamic>()),
    ];
    expect(list, hasLength(1));
    expect(list.single.driverId, hasLength(16));
    expect(list.single.heading, 90);
    expect(list.single.lat, closeTo(28.6325, 0.001));
  });

  test('DriverFix serialises within the server DTO bounds', () {
    const fix = DriverFix(lat: 28.6, lng: 77.2, heading: 370, speed: 140, accuracy: -1, ts: 1700000000000);
    expect(fix.toJson(), {'lat': 28.6, 'lng': 77.2, 'heading': 360, 'speed': 100, 'ts': 1700000000000});
    expect(const DriverFix(lat: 1, lng: 2).toJson(), {'lat': 1, 'lng': 2});
  });

  test('formatting helpers', () {
    expect(formatDistance(148), '148 m');
    expect(formatDistance(3141), '3.1 km');
    expect(formatMinutes(449), '7 min');
    expect(formatMinutes(10), '1 min');
    expect(formatFareRange(94, 109), '₹94 – ₹109');
    expect(formatFare(214.6), '₹215');
    expect(MapConfig.ncrBounds.contains(MapConfig.connaughtPlace), isTrue);
    expect(MapConfig.ncrBounds.contains(const GeoPoint(26.9, 75.8)), isFalse);
    expect(MapConfig.connaughtPlace.distanceTo(const GeoPoint(28.6129, 77.2295)), closeTo(2416, 30));
  });
}
