import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../models/json.dart';
import '../models/payment.dart';
import '../models/ride.dart';
import 'realtime_socket.dart';

enum RealtimeStatus {
  disconnected,
  connecting,
  connected,

  /// Was connected (or should be) and is retrying with backoff.
  reconnecting;

  bool get isConnected => this == connected;
}

/// Socket.io `/rt` client (SPEC §8).
///
/// * connects with the current access token (read on every handshake);
/// * reconnects with backoff;
/// * on `connect_error` `UNAUTHORIZED` rotates the token through
///   [reauthenticate] (the session's single-flight refresh) and reconnects;
/// * exposes typed streams per server event and `emitWithAck` helpers whose
///   failures surface as [ApiException] in the REST error shape.
class RealtimeClient {
  RealtimeClient({
    required this.apiBaseUrl,
    required this.accessToken,
    required this.reauthenticate,
    RealtimeSocket Function(String url, AuthProvider auth)? socketFactory,
    this.ackTimeout = const Duration(seconds: 8),
    this.maxBackoff = const Duration(seconds: 30),
  }) : _socketFactory = socketFactory ?? SocketIoRealtimeSocket.new;

  static const namespace = '/rt';

  final String apiBaseUrl;

  /// Current access token, or null when logged out.
  final Future<String?> Function() accessToken;

  /// Rotates tokens after `UNAUTHORIZED`; returns the new access token or
  /// null when the session is over.
  final Future<String?> Function(String staleAccessToken) reauthenticate;
  final RealtimeSocket Function(String url, AuthProvider auth) _socketFactory;
  final Duration ackTimeout;
  final Duration maxBackoff;

  RealtimeSocket? _socket;
  bool _wanted = false;
  bool _disposed = false;
  String _lastToken = '';
  int _failures = 0;
  Timer? _retry;

  final _status = ValueNotifier(RealtimeStatus.disconnected);
  // Async delivery: listeners (Riverpod notifiers) must never run inside a
  // socket callback or a provider lifecycle.
  final _statusChanges = StreamController<RealtimeStatus>.broadcast();
  final _offers = StreamController<RideOffer>.broadcast();
  final _offerExpired = StreamController<String>.broadcast();
  final _rideStatus = StreamController<RideStatusEvent>.broadcast();
  final _positions = StreamController<DriverPosition>.broadcast();
  final _noDriver = StreamController<String>.broadcast();
  final _payment = StreamController<PaymentStatusEvent>.broadcast();

  RealtimeStatus get status => _status.value;

  /// Current status as a listenable (for widgets) …
  ValueListenable<RealtimeStatus> get statusListenable => _status;

  /// … and as a stream (for providers).
  Stream<RealtimeStatus> get statusChanges => _statusChanges.stream;

  bool get isConnected => status.isConnected;

  Stream<RideOffer> get offers => _offers.stream;

  /// `ride:offer:expired` → ride id.
  Stream<String> get offerExpired => _offerExpired.stream;
  Stream<RideStatusEvent> get rideStatus => _rideStatus.stream;
  Stream<DriverPosition> get driverPositions => _positions.stream;

  /// `ride:no_driver` → ride id.
  Stream<String> get noDriver => _noDriver.stream;

  /// `payment:status` (SPEC §15): `paid` also means the ride is PAID; sent to
  /// rider and driver, so a payment completed while the app was in the
  /// background still closes the payment screen.
  Stream<PaymentStatusEvent> get paymentStatus => _payment.stream;

  /// Opens the connection (idempotent) and keeps it open until [disconnect].
  void connect() {
    if (_disposed) return;
    _wanted = true;
    if (_socket == null) {
      _socket = _socketFactory('$apiBaseUrl$namespace', _auth);
      _wire(_socket!);
    }
    if (status == RealtimeStatus.disconnected) _set(RealtimeStatus.connecting);
    _socket!.connect();
  }

  /// Closes the connection and stops reconnecting (logout, driver offline).
  void disconnect() {
    _wanted = false;
    _retry?.cancel();
    _failures = 0;
    _socket?.disconnect();
    _set(RealtimeStatus.disconnected);
  }

  void dispose() {
    // Mark first so no status change is emitted while providers tear down.
    _disposed = true;
    _wanted = false;
    _retry?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    for (final c in [_offers, _offerExpired, _rideStatus, _positions, _noDriver, _payment, _statusChanges]) {
      c.close();
    }
    _status.dispose();
  }

  Future<Map<String, dynamic>> _auth() async {
    _lastToken = await accessToken() ?? '';
    return {'token': _lastToken};
  }

  void _wire(RealtimeSocket s) {
    s.on('connect', (_) {
      _failures = 0;
      _retry?.cancel();
      _set(RealtimeStatus.connected);
    });
    s.on('disconnect', (_) {
      if (_wanted) _set(RealtimeStatus.reconnecting);
    });
    s.on('reconnect_attempt', (_) {
      if (_wanted) _set(RealtimeStatus.reconnecting);
    });
    s.on('connect_error', _onConnectError);
    s.on('ride:offer', (d) => _emit(_offers, d, RideOffer.fromJson));
    s.on('ride:offer:expired', (d) => _emitId(_offerExpired, d));
    s.on('ride:status', (d) => _emit(_rideStatus, d, RideStatusEvent.fromJson));
    s.on('driver:position', (d) => _emit(_positions, d, DriverPosition.fromJson));
    s.on('ride:no_driver', (d) => _emitId(_noDriver, d));
    s.on('payment:status', (d) => _emit(_payment, d, PaymentStatusEvent.fromJson));
  }

  Future<void> _onConnectError(dynamic err) async {
    if (!_wanted || _disposed) return;
    _set(RealtimeStatus.reconnecting);
    _failures++;
    if (_isUnauthorized(err)) {
      try {
        final token = await reauthenticate(_lastToken);
        if (token == null) {
          // Session over: stop trying; the app logs out.
          disconnect();
          return;
        }
        _scheduleRetry(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('Realtime re-auth failed: $e');
        _scheduleRetry(_backoff());
      }
      return;
    }
    // Namespace-level rejections destroy the socket's subscriptions, so the
    // transport's own reconnection would not revive it: retry ourselves.
    _scheduleRetry(_backoff());
  }

  static bool _isUnauthorized(dynamic err) {
    final msg = switch (err) {
      Map m => m['message']?.toString(),
      String s => s,
      _ => err?.toString(),
    };
    return msg != null && msg.contains('UNAUTHORIZED');
  }

  Duration _backoff() {
    final ms = min(maxBackoff.inMilliseconds, 1000 * (1 << min(_failures, 6)));
    final jitter = Random().nextInt(ms ~/ 2 + 1);
    return Duration(milliseconds: ms ~/ 2 + jitter);
  }

  void _scheduleRetry(Duration delay) {
    _retry?.cancel();
    _retry = Timer(delay, () {
      if (_wanted && !_disposed && !(_socket?.connected ?? false)) _socket?.connect();
    });
  }

  void _set(RealtimeStatus s) {
    if (_disposed || _status.value == s) return;
    _status.value = s;
    _statusChanges.add(s);
  }

  void _emit<T>(StreamController<T> c, dynamic data, T Function(Map<String, dynamic>) parse) {
    final m = asMap(data);
    if (m == null) return;
    try {
      c.add(parse(m));
    } catch (e) {
      debugPrint('Realtime: dropped malformed event ($e): $data');
    }
  }

  void _emitId(StreamController<String> c, dynamic data) {
    final id = asMap(data)?['ride_id'];
    if (id is String) c.add(id);
  }

  // ------------------------------------------------------------- emit + ack

  /// Emits [event] and returns the acknowledgement's `data` (null when the
  /// server acknowledged without data). Throws [ApiException]: the server's
  /// `{ok:false, error}` as-is, `NETWORK_ERROR` when the socket is not
  /// connected, `ACK_TIMEOUT` when no acknowledgement arrives.
  Future<Map<String, dynamic>?> emitWithAck(String event, Map<String, dynamic> data) {
    final s = _socket;
    if (s == null || !s.connected) {
      return Future.error(const ApiException(
          code: ApiException.networkError, message: 'Not connected to the server'));
    }
    final completer = Completer<Map<String, dynamic>?>();
    final timer = Timer(ackTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
            const ApiException(code: 'ACK_TIMEOUT', message: 'The server did not respond'));
      }
    });
    s.emitWithAck(event, data, (ack) {
      timer.cancel();
      if (completer.isCompleted) return;
      final m = asMap(ack);
      if (m == null) {
        completer.completeError(
            const ApiException(code: 'BAD_ACK', message: 'Unexpected server reply'));
      } else if (m['ok'] == true) {
        completer.complete(asMap(m['data']));
      } else {
        final err = asMap(m['error']) ?? const {};
        completer.completeError(ApiException(
          code: err['code']?.toString() ?? 'WS_ERROR',
          message: err['message']?.toString() ?? 'Request failed',
        ));
      }
    });
    return completer.future;
  }

  /// `driver:location` (every 4 s idle, 2 s on a trip).
  Future<void> sendDriverLocation(DriverFix fix) => emitWithAck('driver:location', fix.toJson());

  /// `driver:offer:accept` → the accepted ride (driver view).
  Future<Ride> acceptOffer(String rideId) async {
    final data = await emitWithAck('driver:offer:accept', {'ride_id': rideId});
    if (data == null) {
      throw const ApiException(code: 'BAD_ACK', message: 'Server returned no ride');
    }
    return Ride.fromJson(data);
  }

  Future<void> rejectOffer(String rideId) => emitWithAck('driver:offer:reject', {'ride_id': rideId});

  /// `rider:subscribe`: the server replies with `ride:status` and the last
  /// `driver:position` on the streams.
  Future<void> subscribeRide(String rideId) => emitWithAck('rider:subscribe', {'ride_id': rideId});
}
