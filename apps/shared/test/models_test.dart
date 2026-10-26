import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

void main() {
  test('User parses NUMERIC rating sent as a string', () {
    final u = User.fromJson({
      'id': 'u1',
      'phone': '+919800000000',
      'role': 'rider',
      'status': 'active',
      'rating_avg': '4.75',
      'rating_count': 12,
    });
    expect(u.role, UserRole.rider);
    expect(u.ratingAvg, 4.75);
  });

  test('RideStatus round-trips wire values', () {
    for (final s in RideStatus.values) {
      expect(RideStatus.fromWire(s.wire), s);
    }
    expect(RideStatus.fromWire('NO_DRIVER'), RideStatus.noDriver);
    expect(RideStatus.started.isActive, isTrue);
    expect(RideStatus.paid.isTerminal, isTrue);
    expect(() => RideStatus.fromWire('BOGUS'), throwsArgumentError);
  });
}
