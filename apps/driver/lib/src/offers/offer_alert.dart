import 'package:ride_shared/ride_shared.dart';

/// Loud repeating tone + vibration while an offer is on screen (SPEC §12).
abstract class OfferAlert {
  Future<void> start();

  Future<void> stop();

  /// The app is in the background (socket still up): a full-screen
  /// notification wakes the screen and opens the request when tapped.
  Future<void> notify(RideOffer offer);

  /// No request left: removes that notification.
  Future<void> clearNotification();
}

/// No sound (tests).
class SilentOfferAlert implements OfferAlert {
  const SilentOfferAlert();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> notify(RideOffer offer) async {}

  @override
  Future<void> clearNotification() async {}
}
