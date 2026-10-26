/// Loud repeating tone + vibration while an offer is on screen (SPEC §12).
abstract class OfferAlert {
  Future<void> start();

  Future<void> stop();
}

/// No sound (tests).
class SilentOfferAlert implements OfferAlert {
  const SilentOfferAlert();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
