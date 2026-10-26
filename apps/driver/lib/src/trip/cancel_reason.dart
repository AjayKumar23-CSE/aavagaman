/// Driver cancel reasons (SPEC §12 "Cancel with reason picker"). The API
/// takes free text; these are the fixed choices plus "Other" with a note.
enum CancelReason {
  vehicleBreakdown('Vehicle breakdown'),
  riderNotReachable('Rider not reachable'),
  riderNoShow('Rider no-show'),
  wrongPickup('Wrong pickup location'),
  other('Other');

  const CancelReason(this.wire);

  /// Text sent as `reason` (English; the admin panel shows it as-is).
  final String wire;
}

/// SPEC §9.5: a no-show cancel (fee to the rider, not counted against the
/// driver) is allowed once the driver has waited this long at the pickup.
const noShowWait = Duration(seconds: 300);
