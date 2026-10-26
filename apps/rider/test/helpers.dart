import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:ride_shared/testing.dart';
import 'package:rider/main.dart';
import 'package:rider/src/location/location_source.dart';
import 'package:rider/src/providers.dart';

const saved = AuthTokens(accessToken: 'a1', refreshToken: 'r1');
const cp = RidePlace(lat: 28.6315, lng: 77.2167, address: 'Connaught Place, New Delhi');
const indiaGate = RidePlace(lat: 28.6129, lng: 77.2295, address: 'India Gate, New Delhi');

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// A real ride payload with overrides applied.
Ride rideFrom(String name, [void Function(Map<String, dynamic> json)? edit]) {
  final json = fixture(name);
  edit?.call(json);
  return Ride.fromJson(json);
}

User rider({String? name, String? email}) => User(
      id: 'u1',
      phone: '+919800000002',
      role: UserRole.rider,
      status: UserStatus.active,
      name: name,
      email: email,
    );

class FakeAuthApi implements AuthApi {
  final sent = <String>[];
  final verified = <({String phone, String code, DeviceInfo device})>[];
  Object? sendError;
  Object? verifyError;
  User user = rider();

  @override
  Future<int> sendOtp({required String phone, required LoginRole role}) async {
    sent.add(phone);
    if (sendError != null) throw sendError!;
    return 300;
  }

  @override
  Future<LoginResult> verifyOtp({
    required String phone,
    required String code,
    required LoginRole role,
    DeviceInfo device = const DeviceInfo(),
  }) async {
    verified.add((phone: phone, code: code, device: device));
    if (verifyError != null) throw verifyError!;
    return LoginResult(tokens: const AuthTokens(accessToken: 'a', refreshToken: 'r'), user: user);
  }

  @override
  Future<void> logout() async {}
}

class FakeMeApi implements MeApi {
  FakeMeApi(this.current);

  User current;
  Object? deleteError;
  var deleted = false;
  final updates = <({String? name, String? email})>[];

  @override
  Future<User> get() async => current;

  @override
  Future<User> update({String? name, String? email}) async {
    updates.add((name: name, email: email));
    return current = User(
      id: current.id,
      phone: current.phone,
      role: current.role,
      status: current.status,
      name: name ?? current.name,
      email: email ?? current.email,
    );
  }

  @override
  Future<void> registerFcmToken(String token) async {}

  @override
  Future<void> delete() async {
    if (deleteError != null) throw deleteError!;
    deleted = true;
  }
}

class FakeRideApi implements RideApi {
  /// Returned by `GET /rides/active`; also what `get()` returns for its id.
  Ride? activeRide;
  Map<String, dynamic> estimateJson = const {};
  Object? estimateError;
  Object? createError;
  Object? cancelError;
  List<NearbyDriver> nearbyResult = const [];

  /// Fee the fake applies on cancel (the real API charges ₹30 after 120 s).
  double cancelFee = 0;

  /// Phase 3/4: receipt, history, rating, SOS.
  RideReceipt? receiptResult;
  Object? receiptError;
  List<Ride> historyRides = const [];
  Object? historyError;
  Object? rateError;
  Object? sosError;

  int activeCalls = 0;
  int estimateCalls = 0;
  int receiptCalls = 0;
  final created =
      <({RidePlace pickup, RidePlace drop, String fareConfigId, PaymentMethod paymentMethod, VehicleType vehicleType})>[];
  final cancelled = <String>[];
  final fetched = <String>[];
  final historyCalls = <({int page, int limit})>[];
  final rated = <({String id, int stars, String? comment})>[];
  final sosCalls = <({String id, double lat, double lng})>[];

  @override
  Future<FareEstimate> estimate({required RidePlace pickup, required RidePlace drop}) async {
    estimateCalls++;
    if (estimateError != null) throw estimateError!;
    return FareEstimate.fromJson(estimateJson);
  }

  @override
  Future<List<NearbyDriver>> nearby({required double lat, required double lng}) async => nearbyResult;

  @override
  Future<Ride> create({
    required RidePlace pickup,
    required RidePlace drop,
    required String fareConfigId,
    required PaymentMethod paymentMethod,
    VehicleType vehicleType = VehicleType.sedan,
  }) async {
    created.add((
      pickup: pickup,
      drop: drop,
      fareConfigId: fareConfigId,
      paymentMethod: paymentMethod,
      vehicleType: vehicleType,
    ));
    if (createError != null) throw createError!;
    return activeRide = rideFrom('ride_requested.json', (j) {
      j['payment_method'] = paymentMethod.name;
      j['requested_at'] = DateTime.now().toUtc().toIso8601String();
      j['pickup'] = pickup.toJson();
      j['drop'] = drop.toJson();
    });
  }

  @override
  Future<Ride?> active() async {
    activeCalls++;
    return activeRide;
  }

  @override
  Future<Ride> get(String id) async {
    fetched.add(id);
    final r = activeRide;
    if (r != null && r.id == id) return r;
    for (final h in historyRides) {
      if (h.id == id) return h;
    }
    throw const ApiException(code: 'NOT_FOUND', message: 'Ride not found', statusCode: 404);
  }

  @override
  Future<Ride> cancel(String id, {String? reason}) async {
    cancelled.add(id);
    if (cancelError != null) throw cancelError!;
    final r = activeRide!.copyWith(
      status: RideStatus.cancelled,
      cancelledBy: CancelActor.rider,
      cancelReason: reason,
      cancellationFee: cancelFee,
      cancelledAt: DateTime.now(),
    );
    activeRide = null;
    return r;
  }

  @override
  Future<RidePageResult> history({int page = 1, int limit = 20}) async {
    historyCalls.add((page: page, limit: limit));
    if (historyError != null) throw historyError!;
    final start = (page - 1) * limit;
    final slice = start >= historyRides.length ? <Ride>[] : historyRides.skip(start).take(limit).toList();
    return RidePageResult(data: slice, page: page, limit: limit, total: historyRides.length);
  }

  @override
  Future<RideReceipt> receipt(String id) async {
    receiptCalls++;
    if (receiptError != null) throw receiptError!;
    final r = receiptResult;
    if (r == null) {
      throw const ApiException(
          code: 'RECEIPT_NOT_READY', message: 'The receipt is available once the trip is completed', statusCode: 409);
    }
    return r;
  }

  @override
  Future<RatingResult> rate(String id, {required int stars, String? comment}) async {
    rated.add((id: id, stars: stars, comment: comment));
    if (rateError != null) throw rateError!;
    return RatingResult(id: 'rating-${rated.length}', rideId: id, stars: stars, comment: comment);
  }

  /// Ride ids `requestCall` was asked for; [callError] makes it throw.
  final callRequests = <String>[];
  Object? callError;

  @override
  Future<RideCall> requestCall(String id, {bool driver = false}) async {
    callRequests.add(id);
    if (callError != null) throw callError!;
    return const RideCall(id: 'call-1', status: 'initiated', via: '+911140001234');
  }

  @override
  Future<void> sos(String id, {required double lat, required double lng}) async {
    sosCalls.add((id: id, lat: lat, lng: lng));
    if (sosError != null) throw sosError!;
  }

  // Driver endpoints: not used by the rider app.
  @override
  Future<void> driverOnline({required double lat, required double lng}) => throw UnimplementedError();
  @override
  Future<void> driverOffline() => throw UnimplementedError();
  @override
  Future<void> driverLocation(DriverFix fix) => throw UnimplementedError();
  @override
  Future<Ride?> driverActive() => throw UnimplementedError();
  @override
  Future<Ride> driverAccept(String id) => throw UnimplementedError();
  @override
  Future<void> driverReject(String id) => throw UnimplementedError();
  @override
  Future<Ride> driverArrived(String id, {required double lat, required double lng}) => throw UnimplementedError();
  @override
  Future<Ride> driverStart(String id, {required String otp, required double lat, required double lng}) =>
      throw UnimplementedError();
  @override
  Future<Ride> driverComplete(String id, {required double lat, required double lng}) => throw UnimplementedError();
  @override
  Future<Ride> driverCancel(String id, {required String reason}) => throw UnimplementedError();
  @override
  Future<Ride> driverCashCollected(String id) => throw UnimplementedError();
  @override
  Future<RatingResult> driverRate(String id, {required int stars}) => throw UnimplementedError();
  @override
  Future<RidePageResult> driverHistory({int page = 1, int limit = 20}) => throw UnimplementedError();
  @override
  Future<DriverEarnings> driverEarnings(EarningsPeriod period) => throw UnimplementedError();
}

class FakePaymentsApi implements PaymentsApi {
  Object? orderError;
  Object? verifyError;
  PaymentOrder order = const PaymentOrder(
      razorpayOrderId: 'order_test1', amountPaise: 11800, currency: 'INR', keyId: 'rzp_test_key');
  final orders = <String>[];
  final verified = <({String rideId, RazorpayResult result})>[];

  @override
  Future<PaymentOrder> createOrder(String rideId) async {
    orders.add(rideId);
    if (orderError != null) throw orderError!;
    return order;
  }

  @override
  Future<PaymentRecord> verify(String rideId, RazorpayResult result) async {
    verified.add((rideId: rideId, result: result));
    if (verifyError != null) throw verifyError!;
    return PaymentRecord(
      id: 'p1',
      rideId: rideId,
      method: 'upi',
      amount: order.amountRupees,
      status: PaymentStatus.paid,
      gatewayOrderId: result.orderId,
      gatewayPaymentId: result.paymentId,
      paidAt: DateTime.now(),
    );
  }
}

/// Records what the app asked the system share sheet to share.
class RecordingShareSheet {
  final shared = <({String text, String? subject})>[];
  bool available = true;

  Future<bool> call({required String text, String? subject}) async {
    shared.add((text: text, subject: subject));
    return available;
  }
}

/// Records dialer launches for the SOS flow.
class DialerHarness {
  final dialled = <Uri>[];
  bool canDial = true;

  Future<bool> launch(Uri uri) async {
    dialled.add(uri);
    return canDial;
  }
}

/// Pumps a few frames: for screens with an indeterminate spinner, where
/// `pumpAndSettle` would never return.
Future<void> settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Room for the booking / ride cards without scrolling.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Holds the fake socket the realtime client creates, so tests can drive it.
class SocketHarness {
  FakeRealtimeSocket? socket;

  /// Completes the handshake once the client has connected.
  void connect() => socket!.serverConnect();

  void emit(String event, Object data) => socket!.serverEmit(event, data);
}

/// The app wired to fakes. [tokens] non-null means a saved session.
Widget testApp({
  required FakeAuthApi auth,
  required FakeMeApi me,
  AuthTokens? tokens,
  FakeRideApi? rides,
  FakePaymentsApi? payments,
  RazorpayLauncher? razorpay,
  RecordingShareSheet? share,
  DialerHarness? dialer,
  SocketHarness? sockets,
  LocationResult location = const LocationResult(point: GeoPoint(28.6315, 77.2167)),
  Stream<GeoPoint> locationUpdates = const Stream.empty(),
  PlacesApi places = const NoPlacesApi(),
  BookingDraft draft = const BookingDraft(),
  MapBuilder mapBuilder = placeholderMapBuilder,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'http://api.test')),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore(tokens)),
        authApiProvider.overrideWithValue(auth),
        meApiProvider.overrideWithValue(me),
        rideApiProvider.overrideWithValue(rides ?? FakeRideApi()),
        paymentsApiProvider.overrideWithValue(payments ?? FakePaymentsApi()),
        razorpayLauncherProvider.overrideWithValue(
            razorpay ?? FakeRazorpayLauncher(outcome: const RazorpayFailure(RazorpayFailureKind.cancelled))),
        shareSheetProvider.overrideWithValue((share ?? RecordingShareSheet()).call),
        sosFlowProvider.overrideWith(
            (ref) => SosFlow(api: ref.watch(rideApiProvider), launch: (dialer ?? DialerHarness()).launch)),
        placesApiProvider.overrideWithValue(places),
        pushTokenSourceProvider.overrideWithValue(const NoPushTokenSource()),
        appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
        locationSourceProvider.overrideWithValue(FixedLocationSource(location, live: locationUpdates)),
        splashHoldProvider.overrideWithValue(Duration.zero),
        mapBuilderProvider.overrideWithValue(mapBuilder),
        bookingDraftProvider.overrideWith(() => BookingDraftController(draft)),
        realtimeClientProvider.overrideWith((ref) {
          final client = RealtimeClient(
            apiBaseUrl: 'http://api.test',
            accessToken: () async => 'a1',
            reauthenticate: (_) async => 'a1',
            socketFactory: (url, authFn) {
              final s = FakeRealtimeSocket(url, authFn);
              sockets?.socket = s;
              return s;
            },
          );
          ref.onDispose(client.dispose);
          return client;
        }),
        ...overrides,
      ],
      child: const App(),
    );
