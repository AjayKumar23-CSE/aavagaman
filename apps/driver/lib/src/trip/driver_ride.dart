import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

/// The driver's current ride plus whether it was taken away (admin reassign
/// or a re-queue after a driver cancel sends `ride:status` with
/// `reassigned: true`).
class DriverRide {
  const DriverRide(this.ride, {this.reassigned = false, this.cancelledByMe = false});

  final Ride ride;
  final bool reassigned;

  /// This driver cancelled: the ride went back to matching (or, for a
  /// no-show, was cancelled with a fee to the rider).
  final bool cancelledByMe;

  /// Ended (cancelled, reassigned, paid): shown until dismissed.
  bool get ended => reassigned || cancelledByMe || ride.status.isTerminal;

  /// Paid and still ours: the driver may rate the rider (SPEC §12, skip allowed).
  bool get awaitingRating => !reassigned && !cancelledByMe && ride.status == RideStatus.paid;
}

/// `GET /driver/rides/active` on login and resume, kept current with
/// `ride:status`. Ended rides stay until [DriverRideController.dismiss].
final activeRideProvider = AsyncNotifierProvider<DriverRideController, DriverRide?>(
  DriverRideController.new,
  retry: (_, _) => null,
);

class DriverRideController extends AsyncNotifier<DriverRide?> {
  @override
  Future<DriverRide?> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
    if (userId == null) return null;
    final rt = ref.read(realtimeClientProvider);
    final subs = [rt.rideStatus.listen(_onStatus), rt.paymentStatus.listen(_onPayment)];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    final ride = await ref.read(rideApiProvider).driverActive();
    return ride == null ? null : DriverRide(ride);
  }

  RideApi get _api => ref.read(rideApiProvider);

  DriverRide? get current => state.value;

  /// After a successful accept (socket ack or REST), or any trip endpoint
  /// that returned the ride (arrived, start, complete, cash-collected).
  void set(Ride ride) => state = AsyncData(DriverRide(ride));

  /// After `POST /driver/rides/:id/cancel`. The re-queued ride comes back as
  /// REQUESTED; keep our copy so the screen can explain, then dismiss.
  void cancelledByMe(Ride ride) => state = AsyncData(
    DriverRide(
      ride.status == RideStatus.requested ? ride.copyWith(status: RideStatus.cancelled) : ride,
      cancelledByMe: true,
    ),
  );

  Future<void> refresh() async {
    try {
      var ride = await _api.driverActive();
      final cur = current;
      if (ride == null && cur != null) {
        if (cur.ended) return;
        // Ended while we were away: an online payment made it PAID (no
        // longer "active" but still ours in the history), or it was
        // cancelled / reassigned (gone from our history).
        ride = await _fromHistory(cur.ride.id);
      }
      state = AsyncData(ride == null ? null : DriverRide(ride));
    } catch (e) {
      debugPrint('driver active ride refresh failed: $e');
    }
  }

  Future<Ride?> _fromHistory(String rideId) async {
    final page = await _api.driverHistory(page: 1, limit: 10);
    return page.data.where((r) => r.id == rideId).firstOrNull;
  }

  void dismiss() => state = const AsyncData(null);

  /// `payment:status paid` (online payment, or cash confirmed from another
  /// device / by admin) moves the trip to the rating step.
  void _onPayment(PaymentStatusEvent e) {
    final cur = current;
    if (cur == null || cur.ride.id != e.rideId || !e.isPaid) return;
    if (cur.ride.status == RideStatus.paid) return;
    state = AsyncData(DriverRide(cur.ride.copyWith(status: RideStatus.paid, paidAt: DateTime.now())));
  }

  void _onStatus(RideStatusEvent e) {
    final cur = current;
    // Our own cancel already ended it; the re-queue event must not relabel it.
    if (cur != null && cur.ride.id == e.rideId && cur.cancelledByMe) return;
    if (e.reassigned) {
      if (cur != null && cur.ride.id == e.rideId) {
        state = AsyncData(DriverRide(cur.ride.copyWith(status: RideStatus.cancelled), reassigned: true));
      }
      return;
    }
    if (cur == null || cur.ride.id != e.rideId) {
      // Re-sent on connect, or accepted on another device.
      if (!e.status.isTerminal) unawaited(refresh());
      return;
    }
    state = AsyncData(DriverRide(cur.ride.apply(e)));
    if (!e.status.isTerminal) unawaited(refresh());
  }
}
