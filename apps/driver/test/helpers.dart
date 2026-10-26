import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:driver/main.dart';
import 'package:driver/src/documents/document_images.dart';
import 'package:driver/src/offers/offer_alert.dart';
import 'package:driver/src/prefs.dart';
import 'package:driver/src/presence/location_feed.dart';
import 'package:driver/src/presence/permissions.dart';
import 'package:driver/src/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:ride_shared/testing.dart';

const saved = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// A real `GET /driver/me` response (see test/fixtures) with overrides.
DriverProfile profileFrom(String name, [void Function(Map<String, dynamic> json)? edit]) {
  final json = fixture(name);
  edit?.call(json);
  return DriverProfile.fromJson(json);
}

DriverProfile approvedProfile() => profileFrom('driver_me_pending.json', (j) {
      j['verification_status'] = 'approved';
      j['documents'] = [
        for (final t in DocType.mandatoryTypes)
          {
            'id': t.wire,
            'doc_type': t.wire,
            'status': 'approved',
            'reviewer_note': null,
            'expiry': t.requiresExpiry ? '2031-01-01' : null,
            'uploaded_at': '2026-09-27T10:00:00.000Z',
          },
      ];
      j['missing_documents'] = <String>[];
      j['can_go_online'] = true;
    });

DriverProfile newDriverProfile() => DriverProfile.fromJson({
      'user_id': 'u1',
      'name': null,
      'phone': '+919800000001',
      'verification_status': 'pending',
      'registered': false,
      'vehicle': null,
      'documents': <Object>[],
      'missing_documents': [for (final t in DocType.mandatoryTypes) t.wire],
      'expired_documents': <Object>[],
      'can_go_online': false,
    });

User driverUser([String? name = 'Ravi Kumar']) => User(
      id: 'u1',
      phone: '+919800000001',
      role: UserRole.driver,
      status: UserStatus.active,
      name: name,
    );

class FakeDriverApi implements DriverApi {
  FakeDriverApi(this.profile);

  DriverProfile profile;
  int meCalls = 0;
  final registrations = <DriverRegistration>[];
  final presigned = <DocType>[];
  final puts = <Uint8List>[];
  final created = <({DocType type, String key, DateTime? expiry, String? idLast4})>[];

  /// Thrown once by the next createDocument call.
  Object? createErrorOnce;

  @override
  Future<DriverProfile> me() async {
    meCalls++;
    return profile;
  }

  @override
  Future<DriverProfile> register(DriverRegistration input) async {
    registrations.add(input);
    return profile = profileFrom('driver_me_pending.json', (j) {
      j['documents'] = <Object>[];
      j['missing_documents'] = [for (final t in DocType.mandatoryTypes) t.wire];
    });
  }

  @override
  Future<PresignedUpload> presign(DocType type, {String contentType = 'image/jpeg'}) async {
    presigned.add(type);
    return PresignedUpload(
      uploadUrl: 'https://r2.test/${type.wire}?sig=1',
      fileKey: 'drivers/u1/${type.wire}/k${presigned.length}.jpg',
      expiresIn: 600,
    );
  }

  @override
  Future<void> putObject(String uploadUrl, Uint8List bytes,
      {String contentType = 'image/jpeg', void Function(int sent, int total)? onProgress}) async {
    puts.add(bytes);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<DriverDocument> createDocument(DocType type, String fileKey,
      {DateTime? expiry, String? idLast4}) async {
    created.add((type: type, key: fileKey, expiry: expiry, idLast4: idLast4));
    if (createErrorOnce != null) {
      final e = createErrorOnce!;
      createErrorOnce = null;
      throw e;
    }
    return DriverDocument(id: 'new', type: type, status: VerificationStatus.pending, expiry: expiry);
  }

  @override
  Future<DriverDocument> uploadDocument(DocType type, Uint8List bytes,
          {String contentType = 'image/jpeg',
          DateTime? expiry,
          String? idLast4,
          void Function(double progress)? onProgress}) =>
      throw UnimplementedError();
}

class FakeMeApi implements MeApi {
  FakeMeApi(this.user);

  final User user;

  @override
  Future<User> get() async => user;

  @override
  Future<User> update({String? name, String? email}) async => user;

  @override
  Future<void> registerFcmToken(String token) async {}

  @override
  Future<void> delete() async {}
}

class FakeAuthApi implements AuthApi {
  FakeAuthApi(this.user);

  final User user;
  final sent = <String>[];
  final roles = <LoginRole>[];

  @override
  Future<int> sendOtp({required String phone, required LoginRole role}) async {
    sent.add(phone);
    roles.add(role);
    return 300;
  }

  @override
  Future<LoginResult> verifyOtp({
    required String phone,
    required String code,
    required LoginRole role,
    DeviceInfo device = const DeviceInfo(),
  }) async {
    roles.add(role);
    return LoginResult(tokens: saved, user: user);
  }

  @override
  Future<void> logout() async {}
}

class FakeImages implements DocumentImageService {
  /// A valid 1×1 PNG so Image.memory can decode the preview.
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
  final sources = <PhotoSource>[];

  @override
  Future<Uint8List?> pick(PhotoSource source, {bool frontCamera = false}) async {
    sources.add(source);
    return bytes;
  }
}

/// A real ride payload with overrides applied.
Ride rideFrom(String name, [void Function(Map<String, dynamic> json)? edit]) {
  final json = fixture(name);
  edit?.call(json);
  return Ride.fromJson(json);
}

const cpFix = DriverFix(lat: 28.6325, lng: 77.2177, heading: 90, speed: 0, accuracy: 8, ts: 1);

class FakeRideApi implements RideApi {
  Ride? activeRide;
  Object? onlineError;
  Object? offlineError;
  Object? locationError;
  Object? acceptError;
  final onlineCalls = <({double lat, double lng})>[];
  int offlineCalls = 0;
  final locationCalls = <DriverFix>[];
  final accepted = <String>[];
  final rejected = <String>[];
  int activeCalls = 0;

  // Phase 3/4: trip, payment, rating, earnings, history, SOS.
  Object? arrivedError;
  Object? startError;
  Object? completeError;
  Object? cancelError;
  Object? cashError;
  Object? rateError;
  Object? earningsError;
  Object? historyError;
  Object? sosError;

  /// What `driverCancel` returns (defaults to the re-queued ride).
  Ride? cancelResult;
  List<Ride> historyRides = const [];
  final earnings = <EarningsPeriod, DriverEarnings>{};

  final arrivedCalls = <({String id, double lat, double lng})>[];
  final startCalls = <({String id, String otp, double lat, double lng})>[];
  final completeCalls = <({String id, double lat, double lng})>[];
  final cancelCalls = <({String id, String reason})>[];
  final cashCalls = <String>[];
  final rated = <({String id, int stars})>[];
  final earningsCalls = <EarningsPeriod>[];
  final historyCalls = <({int page, int limit})>[];
  final sosCalls = <({String id, double lat, double lng})>[];

  @override
  Future<void> driverOnline({required double lat, required double lng}) async {
    onlineCalls.add((lat: lat, lng: lng));
    if (onlineError != null) throw onlineError!;
  }

  @override
  Future<void> driverOffline() async {
    offlineCalls++;
    if (offlineError != null) throw offlineError!;
  }

  @override
  Future<void> driverLocation(DriverFix fix) async {
    locationCalls.add(fix);
    if (locationError != null) throw locationError!;
  }

  @override
  Future<Ride?> driverActive() async {
    activeCalls++;
    return activeRide;
  }

  @override
  Future<Ride> driverAccept(String id) async {
    accepted.add(id);
    if (acceptError != null) throw acceptError!;
    return activeRide = rideFrom('ride_accepted_driver_view.json', (j) => j['id'] = id);
  }

  @override
  Future<void> driverReject(String id) async => rejected.add(id);

  @override
  Future<Ride> driverArrived(String id, {required double lat, required double lng}) async {
    arrivedCalls.add((id: id, lat: lat, lng: lng));
    if (arrivedError != null) throw arrivedError!;
    return activeRide = rideFrom('ride_arrived_driver_view.json', (j) {
      j['id'] = id;
      j['arrived_at'] = DateTime.now().toUtc().toIso8601String();
    });
  }

  @override
  Future<Ride> driverStart(String id, {required String otp, required double lat, required double lng}) async {
    startCalls.add((id: id, otp: otp, lat: lat, lng: lng));
    if (startError != null) throw startError!;
    return activeRide = rideFrom('ride_started_driver_view.json', (j) => j['id'] = id);
  }

  @override
  Future<Ride> driverComplete(String id, {required double lat, required double lng}) async {
    completeCalls.add((id: id, lat: lat, lng: lng));
    if (completeError != null) throw completeError!;
    return activeRide = rideFrom('ride_completed_driver_view.json', (j) {
      j['id'] = id;
      j['payment_method'] = activeRide?.paymentMethod.name ?? 'cash';
    });
  }

  @override
  Future<Ride> driverCancel(String id, {required String reason}) async {
    cancelCalls.add((id: id, reason: reason));
    if (cancelError != null) throw cancelError!;
    activeRide = null;
    return cancelResult ?? rideFrom('driver_cancel_requeued.json', (j) => j['id'] = id);
  }

  @override
  Future<Ride> driverCashCollected(String id) async {
    cashCalls.add(id);
    if (cashError != null) throw cashError!;
    activeRide = null; // the server no longer reports a PAID ride as active
    return rideFrom('ride_paid_driver_view.json', (j) => j['id'] = id);
  }

  @override
  Future<RatingResult> driverRate(String id, {required int stars}) async {
    rated.add((id: id, stars: stars));
    if (rateError != null) throw rateError!;
    return RatingResult(id: 'rating-${rated.length}', rideId: id, stars: stars);
  }

  @override
  Future<RidePageResult> driverHistory({int page = 1, int limit = 20}) async {
    historyCalls.add((page: page, limit: limit));
    if (historyError != null) throw historyError!;
    final start = (page - 1) * limit;
    final slice = start >= historyRides.length ? <Ride>[] : historyRides.skip(start).take(limit).toList();
    return RidePageResult(data: slice, page: page, limit: limit, total: historyRides.length);
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
  Future<DriverEarnings> driverEarnings(EarningsPeriod period) async {
    earningsCalls.add(period);
    if (earningsError != null) throw earningsError!;
    return earnings[period] ?? DriverEarnings.empty(period);
  }

  @override
  Future<void> sos(String id, {required double lat, required double lng}) async {
    sosCalls.add((id: id, lat: lat, lng: lng));
    if (sosError != null) throw sosError!;
  }

  // Rider endpoints: not used by the driver app.
  @override
  Future<FareEstimate> estimate({required RidePlace pickup, required RidePlace drop}) =>
      throw UnimplementedError();
  @override
  Future<List<NearbyDriver>> nearby({required double lat, required double lng}) => throw UnimplementedError();
  @override
  Future<Ride> create({
    required RidePlace pickup,
    required RidePlace drop,
    required String fareConfigId,
    required PaymentMethod paymentMethod,
    VehicleType vehicleType = VehicleType.sedan,
  }) =>
      throw UnimplementedError();
  @override
  Future<Ride?> active() => throw UnimplementedError();
  @override
  Future<Ride> get(String id) => throw UnimplementedError();
  @override
  Future<Ride> cancel(String id, {String? reason}) => throw UnimplementedError();
  @override
  Future<RidePageResult> history({int page = 1, int limit = 20}) => throw UnimplementedError();
  @override
  Future<RideReceipt> receipt(String id) => throw UnimplementedError();
  @override
  Future<RatingResult> rate(String id, {required int stars, String? comment}) => throw UnimplementedError();
}

class FakeLocationFeed implements LocationFeed {
  final _controller = StreamController<DriverFix>.broadcast();
  DriverFix? fix = cpFix;
  bool running = false;
  int startCalls = 0;
  int stopCalls = 0;
  String? notificationTitle;

  @override
  Stream<DriverFix> get fixes => _controller.stream;

  /// Simulates a GPS fix from the foreground service.
  void emit(DriverFix f) => _controller.add(f);

  @override
  Future<DriverFix?> currentFix() async => fix;

  @override
  Future<void> start({required String notificationTitle, required String notificationBody}) async {
    startCalls++;
    running = true;
    this.notificationTitle = notificationTitle;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    running = false;
  }

  @override
  Future<bool> isRunning() async => running;
}

class FakePermissionGate implements PermissionGate {
  FakePermissionGate([this.problems = const {}]);

  Set<PermissionProblem> problems;
  int ensureCalls = 0;
  int openedAppSettings = 0;

  @override
  Future<Set<PermissionProblem>> ensure() async {
    ensureCalls++;
    return problems;
  }

  @override
  Future<void> openAppSettings() async => openedAppSettings++;

  @override
  Future<void> openLocationSettings() async {}
}

class RecordingOfferAlert implements OfferAlert {
  int starts = 0;
  int stops = 0;
  bool get ringing => starts > stops;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

/// Holds the fake socket the realtime client creates, so tests can drive it.
class SocketHarness {
  FakeRealtimeSocket? socket;

  void connect() => socket!.serverConnect();

  void emit(String event, Object data) => socket!.serverEmit(event, data);
}

Widget testApp({
  required FakeDriverApi driver,
  User? user,
  AuthTokens? tokens = saved,
  FakeImages? images,
  FakeAuthApi? auth,
  FakeRideApi? rides,
  FakeLocationFeed? feed,
  FakePermissionGate? permissions,
  RecordingOfferAlert? alert,
  SocketHarness? sockets,
  bool batteryGuideSeen = true,
  List<Override> overrides = const [],
}) {
  final u = user ?? driverUser();
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(MemoryTokenStore(tokens)),
      splashHoldProvider.overrideWithValue(Duration.zero),
      authApiProvider.overrideWithValue(auth ?? FakeAuthApi(u)),
      meApiProvider.overrideWithValue(FakeMeApi(u)),
      driverApiProvider.overrideWithValue(driver),
      rideApiProvider.overrideWithValue(rides ?? FakeRideApi()),
      pushTokenSourceProvider.overrideWithValue(const NoPushTokenSource()),
      appVersionProvider.overrideWith((ref) async => '0.1.0+1'),
      documentImageServiceProvider.overrideWithValue(images ?? FakeImages()),
      locationFeedProvider.overrideWithValue(feed ?? FakeLocationFeed()),
      mapBuilderProvider.overrideWithValue(placeholderMapBuilder),
      permissionGateProvider.overrideWithValue(permissions ?? FakePermissionGate()),
      offerAlertProvider.overrideWithValue(alert ?? RecordingOfferAlert()),
      appPrefsProvider.overrideWithValue(MemoryAppPrefs({'battery_guide_seen': batteryGuideSeen})),
      deviceBrandProvider.overrideWith((ref) async => 'xiaomi'),
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
}

/// Room for the full document list without scrolling.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
