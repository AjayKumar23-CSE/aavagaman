import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import 'location/location_source.dart';
import 'payments/razorpay_launcher.dart';
import 'share/share_sheet.dart';

// Core providers (config, tokens, API client, session, realtime) live in ride_shared.

final locationSourceProvider =
    Provider<LocationSource>((ref) => const GeolocatorLocationSource());

/// Razorpay Checkout (SPEC §15); tests use `FakeRazorpayLauncher`.
final razorpayLauncherProvider = Provider<RazorpayLauncher>((ref) => RazorpayFlutterLauncher());

/// System share sheet for the trip link (SPEC §11 Share trip).
final shareSheetProvider = Provider<ShareSheet>((ref) => systemShareSheet);

/// One GPS fix per app session; `ref.invalidate` to ask again.
/// First fix, then live updates while the app is open (the home map's blue
/// dot and the "Current location" pickup follow the rider).
final myLocationProvider = StreamProvider<LocationResult>((ref) async* {
  final source = ref.watch(locationSourceProvider);
  final first = await source.current();
  yield first;
  if (first.point == null) return;
  await for (final p in source.updates()) {
    yield LocationResult(point: p);
  }
});

/// Keeps the `/rt` socket open while logged in (watched from `App`).
final realtimeConnectorProvider = Provider<void>((ref) {
  final client = ref.watch(realtimeClientProvider);
  void sync(SessionState s) {
    switch (s) {
      case SessionLoggedIn():
        client.connect();
      case SessionLoggedOut():
        client.disconnect();
      case SessionUnknown():
        break;
    }
  }

  ref.listen(sessionProvider, (_, s) => sync(s));
  sync(ref.read(sessionProvider));
});

/// Map centre rounded to ~100 m so small pans do not restart the poll.
GeoPoint nearbyKey(GeoPoint p) =>
    GeoPoint((p.lat * 1000).round() / 1000, (p.lng * 1000).round() / 1000);

/// Cars around [centre], refreshed every 10 s (SPEC §11). Errors keep the
/// last list.
final nearbyDriversProvider =
    StreamProvider.autoDispose.family<List<NearbyDriver>, GeoPoint>((ref, centre) {
  final api = ref.watch(rideApiProvider);
  final controller = StreamController<List<NearbyDriver>>();
  Future<void> poll() async {
    try {
      final cars = await api.nearby(lat: centre.lat, lng: centre.lng);
      if (!controller.isClosed) controller.add(cars);
    } catch (e) {
      debugPrint('nearby drivers: $e');
    }
  }

  unawaited(poll());
  final timer = Timer.periodic(MapConfig.nearbyRefresh, (_) => poll());
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

// ----------------------------------------------------------------- booking

class BookingDraft {
  const BookingDraft({
    this.pickup,
    this.drop,
    this.payment = PaymentMethod.cash,
    this.vehicleType = VehicleType.sedan,
  });

  final RidePlace? pickup;
  final RidePlace? drop;
  final PaymentMethod payment;

  /// Vehicle class picked on Confirm (D-056).
  final VehicleType vehicleType;

  bool get complete => pickup != null && drop != null;

  BookingDraft copyWith({RidePlace? pickup, RidePlace? drop, PaymentMethod? payment, VehicleType? vehicleType}) =>
      BookingDraft(
        pickup: pickup ?? this.pickup,
        drop: drop ?? this.drop,
        payment: payment ?? this.payment,
        vehicleType: vehicleType ?? this.vehicleType,
      );
}

class BookingDraftController extends Notifier<BookingDraft> {
  BookingDraftController([this._initial = const BookingDraft()]);

  final BookingDraft _initial;

  @override
  BookingDraft build() => _initial;

  void setPickup(RidePlace p) => state = state.copyWith(pickup: p);

  void setDrop(RidePlace p) => state = state.copyWith(drop: p);

  void setPayment(PaymentMethod m) => state = state.copyWith(payment: m);

  void setVehicleType(VehicleType t) => state = state.copyWith(vehicleType: t);

  void clear() => state = const BookingDraft();
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftController, BookingDraft>(BookingDraftController.new);

/// `POST /fare/estimate` for the draft; re-fetched when pickup or drop change
/// and on `ref.invalidate` (e.g. after 422 `FARE_CONFIG_INVALID`).
final fareEstimateProvider = FutureProvider.autoDispose<FareEstimate>(
  (ref) {
    final (pickup, drop) = ref.watch(bookingDraftProvider.select((d) => (d.pickup, d.drop)));
    if (pickup == null || drop == null) throw StateError('Pickup and drop are required');
    return ref.watch(rideApiProvider).estimate(pickup: pickup, drop: drop);
  },
  // No automatic retries: the screen shows the error with a Retry button.
  retry: (_, _) => null,
);

/// Drop points chosen this session, newest first (in memory only for now).
class RecentPlaces extends Notifier<List<RidePlace>> {
  static const max = 8;

  @override
  List<RidePlace> build() => const [];

  void add(RidePlace place) {
    state = [place, ...state.where((p) => p.address != place.address)].take(max).toList();
  }
}

final recentPlacesProvider = NotifierProvider<RecentPlaces, List<RidePlace>>(RecentPlaces.new);

// -------------------------------------------------------------- active ride

/// The rider's current ride (REQUESTED … COMPLETED), kept in sync with
/// `ride:status` / `ride:no_driver` and re-fetched on launch and resume
/// (SPEC §11). A ride that just ended (NO_DRIVER, CANCELLED, PAID) stays here
/// until [ActiveRideController.dismiss] so its screen can show the outcome.
final activeRideProvider = AsyncNotifierProvider<ActiveRideController, Ride?>(
  ActiveRideController.new,
  retry: (_, _) => null,
);

class ActiveRideController extends AsyncNotifier<Ride?> {
  @override
  Future<Ride?> build() async {
    final userId =
        ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
    if (userId == null) return null;
    final rt = ref.read(realtimeClientProvider);
    final subs = [
      rt.rideStatus.listen(_onStatus),
      rt.noDriver.listen(_onNoDriver),
      rt.paymentStatus.listen(_onPayment),
      rt.statusChanges.listen((s) {
        if (s.isConnected) _subscribe();
      }),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        s.cancel();
      }
    });
    final ride = await ref.read(rideApiProvider).active();
    if (ride != null) _subscribe(ride.id);
    return ride;
  }

  RideApi get _api => ref.read(rideApiProvider);

  Ride? get current => state.value;

  /// Launch / resume: `GET /rides/active` and re-subscribe. Quiet on failure.
  Future<void> refresh() async {
    try {
      var ride = await _api.active();
      final cur = current;
      if (ride == null && cur != null) {
        // The server forgets ended rides; keep showing the outcome until dismissed.
        if (cur.status.isTerminal) return;
        // It ended while we were away (paid online, cancelled by the driver
        // or support): fetch it by id so the Rate / outcome screen still shows.
        ride = await _api.get(cur.id);
      }
      state = AsyncData(ride);
      if (ride != null && !ride.status.isTerminal) _subscribe(ride.id);
    } catch (e) {
      debugPrint('active ride refresh failed: $e');
    }
  }

  /// After `/payment/verify` succeeded: the server also emits
  /// `ride:status PAID`, but the screen should not wait for it.
  void markPaid() {
    final cur = current;
    if (cur == null || cur.status == RideStatus.paid) return;
    state = AsyncData(cur.copyWith(status: RideStatus.paid, paidAt: DateTime.now()));
  }

  /// `POST /rides`; throws [ApiException] (`OUTSIDE_SERVICE_AREA`,
  /// `ACTIVE_RIDE_EXISTS`, `FARE_CONFIG_INVALID`, `ROUTING_UNAVAILABLE`).
  Future<Ride> book({
    required RidePlace pickup,
    required RidePlace drop,
    required String fareConfigId,
    required PaymentMethod paymentMethod,
    VehicleType vehicleType = VehicleType.sedan,
  }) async {
    final ride = await _api.create(
      pickup: pickup,
      drop: drop,
      fareConfigId: fareConfigId,
      paymentMethod: paymentMethod,
      vehicleType: vehicleType,
    );
    state = AsyncData(ride);
    _subscribe(ride.id);
    return ride;
  }

  /// Rider-initiated cancel: on success the ride is dropped straight away
  /// (the rider knows why). Throws [ApiException] (409 `RIDE_NOT_CANCELLABLE`).
  Future<Ride> cancel({String? reason}) async {
    final cur = current;
    if (cur == null) throw StateError('No active ride');
    final ride = await _api.cancel(cur.id, reason: reason);
    state = const AsyncData(null);
    return ride;
  }

  /// After an ended ride's outcome has been shown.
  void dismiss() => state = const AsyncData(null);

  void _onStatus(RideStatusEvent e) {
    final cur = current;
    if (cur == null) {
      // Booked from another device, or re-sent on connect: load it.
      if (!e.status.isTerminal) unawaited(_fetch(e.rideId));
      return;
    }
    if (cur.id != e.rideId) return;
    state = AsyncData(cur.apply(e));
    // The event has no timestamps (accepted_at drives the fee warning).
    if (!e.status.isTerminal) unawaited(_fetch(e.rideId));
  }

  /// `payment:status paid` closes the payment screen even when the status
  /// event was missed (e.g. the app was in the background during checkout).
  void _onPayment(PaymentStatusEvent e) {
    final cur = current;
    if (cur == null || cur.id != e.rideId || !e.isPaid) return;
    if (cur.status == RideStatus.paid) return;
    state = AsyncData(cur.copyWith(status: RideStatus.paid, paidAt: DateTime.now()));
  }

  void _onNoDriver(String rideId) {
    final cur = current;
    if (cur != null && cur.id == rideId) {
      state = AsyncData(cur.copyWith(status: RideStatus.noDriver));
    }
  }

  Future<void> _fetch(String rideId) async {
    try {
      final fresh = await _api.get(rideId);
      final cur = current;
      // Never move backwards if a newer event landed while fetching.
      if (cur == null || cur.id != rideId || _rank(fresh.status) >= _rank(cur.status)) {
        state = AsyncData(fresh);
      }
    } catch (e) {
      debugPrint('ride fetch failed: $e');
    }
  }

  static int _rank(RideStatus s) => switch (s) {
        RideStatus.requested => 0,
        RideStatus.accepted => 1,
        RideStatus.arrived => 2,
        RideStatus.started => 3,
        RideStatus.completed => 4,
        RideStatus.paid => 5,
        RideStatus.cancelled || RideStatus.noDriver => 6,
      };

  void _subscribe([String? rideId]) {
    final id = rideId ?? current?.id;
    if (id == null) return;
    final rt = ref.read(realtimeClientProvider);
    if (!rt.isConnected) return;
    unawaited(rt.subscribeRide(id).catchError((Object e) => debugPrint('rider:subscribe: $e')));
  }
}

/// Latest `driver:position` for the active ride; cleared when the ride changes.
final driverPositionProvider =
    NotifierProvider<DriverPositionController, DriverPosition?>(DriverPositionController.new);

class DriverPositionController extends Notifier<DriverPosition?> {
  @override
  DriverPosition? build() {
    final rt = ref.watch(realtimeClientProvider);
    final sub = rt.driverPositions.listen((p) {
      final ride = ref.read(activeRideProvider).value;
      if (ride == null || p.rideId.isEmpty || p.rideId == ride.id) state = p;
    });
    ref.onDispose(sub.cancel);
    ref.listen(activeRideProvider, (prev, next) {
      if (prev?.value?.id != next.value?.id) state = null;
    });
    return null;
  }
}

/// Driver positions received for the active ride, oldest first (the trip
/// track drawn on the in-progress map). Cleared when the ride changes.
final driverTrackProvider = NotifierProvider<DriverTrackController, List<GeoPoint>>(DriverTrackController.new);

class DriverTrackController extends Notifier<List<GeoPoint>> {
  static const maxPoints = 600;

  @override
  List<GeoPoint> build() {
    final rt = ref.watch(realtimeClientProvider);
    final sub = rt.driverPositions.listen((p) {
      final ride = ref.read(activeRideProvider).value;
      if (ride == null || (p.rideId.isNotEmpty && p.rideId != ride.id)) return;
      final point = GeoPoint(p.lat, p.lng);
      if (state.isNotEmpty && state.last == point) return;
      state = [if (state.length >= maxPoints) ...state.skip(1) else ...state, point];
    });
    ref.onDispose(sub.cancel);
    ref.listen(activeRideProvider, (prev, next) {
      final p = prev?.value;
      final n = next.value;
      // New ride, or the trip just started: the track is the trip itself.
      if (p?.id != n?.id || (p?.status != RideStatus.started && n?.status == RideStatus.started)) {
        state = const [];
      }
    });
    return const [];
  }
}

// ------------------------------------------------------------ fare & rating

/// `GET /rides/:id/receipt` (COMPLETED / PAID only).
final receiptProvider = FutureProvider.autoDispose.family<RideReceipt, String>(
  (ref, rideId) => ref.watch(rideApiProvider).receipt(rideId),
  retry: (_, _) => null,
);

/// Rides rated in this session, so Rate buttons disappear right away (the
/// ride JSON carries no "rated" flag; the server answers 409 ALREADY_RATED).
final ratedRidesProvider = NotifierProvider<RatedRides, Set<String>>(RatedRides.new);

class RatedRides extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String rideId) => state = {...state, rideId};
}

// ------------------------------------------------------------------ history

/// `GET /rides?page=&limit=` (SPEC §11 Ride history), newest first, loaded
/// page by page.
final rideHistoryProvider = AsyncNotifierProvider<RideHistoryController, RidePages>(
  RideHistoryController.new,
  retry: (_, _) => null,
);

class RideHistoryController extends AsyncNotifier<RidePages> {
  static const pageSize = 20;

  @override
  Future<RidePages> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
    if (userId == null) return const RidePages();
    return const RidePages().append(await ref.read(rideApiProvider).history(page: 1, limit: pageSize));
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.loadingMore || !cur.hasMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      state = AsyncData(cur.append(await ref.read(rideApiProvider).history(page: cur.page + 1, limit: pageSize)));
    } catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false, error: e));
    }
  }

  /// Pull to refresh / after a ride ends: reload page 1.
  Future<void> reload() async {
    try {
      state = AsyncData(const RidePages().append(await ref.read(rideApiProvider).history(page: 1, limit: pageSize)));
    } catch (e) {
      if (state.value == null) state = AsyncError(e, StackTrace.current);
    }
  }
}

/// One ride for the detail screen: from the loaded history when present,
/// otherwise `GET /rides/:id`.
final rideDetailProvider = FutureProvider.autoDispose.family<Ride, String>(
  (ref, id) async {
    final cached = ref.watch(rideHistoryProvider).value?.byId(id);
    if (cached != null) return cached;
    return ref.watch(rideApiProvider).get(id);
  },
  retry: (_, _) => null,
);
