import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../providers.dart';

class OfferState {
  const OfferState({this.offers = const [], this.acceptingId, this.error});

  /// Open offers, oldest first (D-055: several rides can ask at once).
  final List<RideOffer> offers;

  /// Ride being accepted right now, or null.
  final String? acceptingId;

  /// Why the last accept failed (409 `OFFER_NOT_VALID`, `DRIVER_BUSY`, …);
  /// shown once, then cleared.
  final String? error;

  bool get hasOffers => offers.isNotEmpty;
  bool get accepting => acceptingId != null;

  RideOffer? byId(String rideId) {
    for (final o in offers) {
      if (o.rideId == rideId) return o;
    }
    return null;
  }

  OfferState copyWith({List<RideOffer>? offers, String? acceptingId, bool clearAccepting = false, String? error}) =>
      OfferState(
        offers: offers ?? this.offers,
        acceptingId: clearAccepting ? null : (acceptingId ?? this.acceptingId),
        error: error,
      );
}

final offerProvider = NotifierProvider<OfferController, OfferState>(OfferController.new);

/// `ride:offer` → a card on the full-screen request list with tone + vibration
/// while any request is open. A request leaves the list on accept, reject,
/// local expiry or `ride:offer:expired`. Accept goes over the socket with a
/// REST fallback when the socket is unusable.
class OfferController extends Notifier<OfferState> {
  final _expiry = <String, Timer>{};

  @override
  OfferState build() {
    final rt = ref.watch(realtimeClientProvider);
    final subs = [rt.offers.listen(_onOffer), rt.offerExpired.listen(_onExpired)];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
      _cancelTimers();
    });
    return const OfferState();
  }

  void _cancelTimers([String? rideId]) {
    if (rideId != null) {
      _expiry.remove(rideId)?.cancel();
      return;
    }
    for (final t in _expiry.values) {
      t.cancel();
    }
    _expiry.clear();
  }

  void _onOffer(RideOffer offer) {
    final busy = ref.read(activeRideProvider).value;
    if (busy != null && !busy.ended) return; // on a trip: ignore stray offers
    _cancelTimers(offer.rideId);
    final wasEmpty = state.offers.isEmpty;
    state = state.copyWith(offers: [...state.offers.where((o) => o.rideId != offer.rideId), offer]);
    if (wasEmpty) unawaited(ref.read(offerAlertProvider).start());
    _expiry[offer.rideId] = Timer(offer.remaining() + const Duration(seconds: 1), () => _onExpired(offer.rideId));
  }

  void _onExpired(String rideId) => _remove(rideId);

  /// Drops one request; the tone stops with the last one.
  void _remove(String rideId, {String? error}) {
    _cancelTimers(rideId);
    if (state.byId(rideId) == null && error == null) return;
    final rest = state.offers.where((o) => o.rideId != rideId).toList();
    state = state.copyWith(offers: rest, clearAccepting: state.acceptingId == rideId, error: error);
    if (rest.isEmpty) unawaited(ref.read(offerAlertProvider).stop());
  }

  /// Returns the accepted ride, or null when the accept failed (the error
  /// is kept in [OfferState.error] and the other requests stay).
  Future<Ride?> accept(String rideId) async {
    final offer = state.byId(rideId);
    if (offer == null || state.accepting) return null;
    _cancelTimers(rideId);
    state = state.copyWith(acceptingId: rideId);
    unawaited(ref.read(offerAlertProvider).stop());
    final rt = ref.read(realtimeClientProvider);
    try {
      Ride ride;
      try {
        ride = await rt.acceptOffer(rideId);
      } on ApiException catch (e) {
        if (!e.isNetwork && e.code != 'ACK_TIMEOUT') rethrow;
        ride = await ref.read(rideApiProvider).driverAccept(rideId);
      }
      ref.read(activeRideProvider.notifier).set(ride);
      _cancelTimers();
      state = const OfferState();
      return ride;
    } on ApiException catch (e) {
      _failed(rideId, e.displayMessage);
      return null;
    } catch (e) {
      debugPrint('accept failed: $e');
      _failed(rideId, e.toString());
      return null;
    }
  }

  void _failed(String rideId, String message) {
    _remove(rideId, error: message);
    if (state.hasOffers) unawaited(ref.read(offerAlertProvider).start());
  }

  Future<void> reject(String rideId) async {
    if (state.byId(rideId) == null) return;
    _remove(rideId);
    final rt = ref.read(realtimeClientProvider);
    try {
      await rt.rejectOffer(rideId);
    } on ApiException catch (e) {
      if (!e.isNetwork && e.code != 'ACK_TIMEOUT') return; // already gone
      try {
        await ref.read(rideApiProvider).driverReject(rideId);
      } catch (e2) {
        debugPrint('reject fallback failed: $e2'); // it times out server-side anyway
      }
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith();
  }
}
