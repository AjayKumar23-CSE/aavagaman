import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../providers.dart';
import 'location_feed.dart';
import 'permissions.dart';

enum PresencePhase { offline, goingOnline, online, goingOffline }

class PresenceState {
  const PresenceState({
    this.phase = PresencePhase.offline,
    this.wantOnline = false,
    this.socketUp = false,
    this.onTrip = false,
    this.problems = const {},
    this.serverMessage,
    this.lastFix,
    this.sentCount = 0,
  });

  final PresencePhase phase;

  /// The switch position. Stays true through reconnects.
  final bool wantOnline;
  final bool socketUp;

  /// Driver holds an ACCEPTED/ARRIVED/STARTED ride: 2 s updates, no offline.
  final bool onTrip;
  final Set<PermissionProblem> problems;

  /// Last error from the server (403 `NOT_ELIGIBLE`, 409 `ON_TRIP`, …).
  final String? serverMessage;
  final DriverFix? lastFix;
  final int sentCount;

  bool get isOnline => phase == PresencePhase.online;
  bool get busy => phase == PresencePhase.goingOnline || phase == PresencePhase.goingOffline;

  /// "Reconnecting…": online but the socket is down.
  bool get reconnecting => isOnline && !socketUp;

  PresenceState copyWith({
    PresencePhase? phase,
    bool? wantOnline,
    bool? socketUp,
    bool? onTrip,
    Set<PermissionProblem>? problems,
    String? serverMessage,
    bool clearServerMessage = false,
    DriverFix? lastFix,
    int? sentCount,
  }) => PresenceState(
    phase: phase ?? this.phase,
    wantOnline: wantOnline ?? this.wantOnline,
    socketUp: socketUp ?? this.socketUp,
    onTrip: onTrip ?? this.onTrip,
    problems: problems ?? this.problems,
    serverMessage: clearServerMessage ? null : (serverMessage ?? this.serverMessage),
    lastFix: lastFix ?? this.lastFix,
    sentCount: sentCount ?? this.sentCount,
  );
}

final presenceProvider = NotifierProvider<PresenceController, PresenceState>(PresenceController.new);

/// Online/offline switch logic (SPEC §12 background location):
/// permissions → GPS fix → `POST /driver/online` → foreground service →
/// `driver:location` every 4 s (2 s on a trip) over the socket, REST
/// `POST /driver/location` while the socket is down, fixes with accuracy
/// > 100 m dropped, `/driver/online` re-sent on 409 `DRIVER_OFFLINE` and on
/// socket reconnect while the switch is on.
class PresenceController extends Notifier<PresenceState> {
  static const idleInterval = Duration(seconds: 4);
  static const tripInterval = Duration(seconds: 2);
  static const maxAccuracyM = 100.0;
  static const maxBatch = 10;

  Timer? _timer;
  StreamSubscription<DriverFix>? _fixes;
  StreamSubscription<RealtimeStatus>? _socket;
  DriverFix? _latest;
  final _batch = <DriverFix>[];
  bool _reOnlining = false;
  bool _ticking = false;
  late LocationFeed _feed;

  @override
  PresenceState build() {
    // Read once here: the dispose callback stops the feed and must not touch ref.
    _feed = ref.read(locationFeedProvider);
    ref.listen(activeRideProvider, (_, next) {
      final onTrip = next.value?.ride.status.isActive ?? false;
      if (onTrip != state.onTrip) {
        state = state.copyWith(onTrip: onTrip);
        if (_timer != null) _startTimer();
      }
    });
    ref.onDispose(_stopStreaming);
    return PresenceState(onTrip: ref.read(activeRideProvider).value?.ride.status.isActive ?? false);
  }

  RideApi get _api => ref.read(rideApiProvider);
  RealtimeClient get _rt => ref.read(realtimeClientProvider);

  /// Switch toggled. [notificationTitle] / [notificationBody] are the
  /// localised foreground-notification texts ("You are online").
  Future<void> setOnline(bool on, {required String notificationTitle, required String notificationBody}) =>
      on ? goOnline(notificationTitle: notificationTitle, notificationBody: notificationBody) : goOffline();

  Future<void> goOnline({required String notificationTitle, required String notificationBody}) async {
    if (state.phase != PresencePhase.offline) return;
    state = state.copyWith(
      phase: PresencePhase.goingOnline,
      wantOnline: true,
      problems: const {},
      clearServerMessage: true,
    );
    final problems = await ref.read(permissionGateProvider).ensure();
    if (problems.any((p) => p.blocksOnline)) {
      state = state.copyWith(phase: PresencePhase.offline, wantOnline: false, problems: problems);
      return;
    }
    final fix = await _feed.currentFix();
    if (fix == null) {
      state = state.copyWith(
        phase: PresencePhase.offline,
        wantOnline: false,
        problems: {...problems, PermissionProblem.serviceOff},
      );
      return;
    }
    try {
      await _api.driverOnline(lat: fix.lat, lng: fix.lng);
    } on ApiException catch (e) {
      // 403 NOT_ELIGIBLE or a network problem.
      state = state.copyWith(
        phase: PresencePhase.offline,
        wantOnline: false,
        problems: problems,
        serverMessage: e.displayMessage,
      );
      return;
    }
    _latest = fix;
    await _feed.start(notificationTitle: notificationTitle, notificationBody: notificationBody);
    _fixes = _feed.fixes.listen(_onFix);
    _socket = _rt.statusChanges.listen(_onSocket);
    _rt.connect();
    _startTimer();
    state = state.copyWith(
      phase: PresencePhase.online,
      socketUp: _rt.isConnected,
      problems: problems, // may still carry notificationsDenied as a warning
      lastFix: fix,
    );
  }

  /// `POST /driver/offline`. Refused with 409 `ON_TRIP` while on a ride.
  Future<void> goOffline() async {
    if (state.phase != PresencePhase.online) return;
    state = state.copyWith(phase: PresencePhase.goingOffline, clearServerMessage: true);
    try {
      await _api.driverOffline();
    } on ApiException catch (e) {
      if (e.code == 'ON_TRIP') {
        state = state.copyWith(phase: PresencePhase.online, serverMessage: e.displayMessage);
        return;
      }
      // Network trouble: go offline locally; the heartbeat sweeper (15 s)
      // marks us offline server-side.
      debugPrint('offline request failed: $e');
    }
    await _stopStreaming();
    state = PresenceState(onTrip: state.onTrip);
  }

  /// App start: the foreground service may have outlived the UI (the
  /// process survived in the background). Rejoin it.
  Future<void> resumeIfServiceRunning({required String notificationTitle, required String notificationBody}) async {
    if (state.phase != PresencePhase.offline) return;
    if (await _feed.isRunning()) {
      await goOnline(notificationTitle: notificationTitle, notificationBody: notificationBody);
    }
  }

  void _onFix(DriverFix fix) {
    if (fix.accuracy != null && fix.accuracy! > maxAccuracyM) return; // SPEC §12
    _latest = fix;
    state = state.copyWith(lastFix: fix);
  }

  void _onSocket(RealtimeStatus s) {
    final wasUp = state.socketUp;
    state = state.copyWith(socketUp: s.isConnected);
    // Back after a drop: the server may have swept us offline meanwhile.
    if (s.isConnected && !wasUp && state.wantOnline) unawaited(_reOnline());
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(state.onTrip ? tripInterval : idleInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_ticking || !state.isOnline) return;
    final fix = _latest;
    if (fix == null) return;
    _ticking = true;
    try {
      if (_rt.isConnected) {
        _batch.clear(); // the server only keeps the latest position
        try {
          await _rt.sendDriverLocation(fix);
          state = state.copyWith(sentCount: state.sentCount + 1);
        } on ApiException catch (e) {
          if (e.code == 'DRIVER_OFFLINE') {
            await _reOnline();
          } else if (e.isNetwork || e.code == 'ACK_TIMEOUT') {
            _enqueue(fix);
          } else {
            debugPrint('driver:location rejected: $e');
          }
        }
      } else {
        _enqueue(fix);
        await _flushRest();
      }
    } finally {
      _ticking = false;
    }
  }

  void _enqueue(DriverFix fix) {
    _batch.add(fix);
    while (_batch.length > maxBatch) {
      _batch.removeAt(0);
    }
  }

  /// REST fallback while the socket is down: send the queued fixes in order
  /// so the server ends with the newest.
  Future<void> _flushRest() async {
    for (final fix in List.of(_batch)) {
      try {
        await _api.driverLocation(fix);
        _batch.remove(fix);
        state = state.copyWith(sentCount: state.sentCount + 1);
      } on ApiException catch (e) {
        if (e.code == 'DRIVER_OFFLINE') {
          _batch.clear();
          await _reOnline();
          return;
        }
        if (e.isNetwork) return; // keep the batch for the next tick
        _batch.remove(fix); // validation etc.: drop the bad fix
      }
    }
  }

  /// The server dropped us (heartbeat expired) or the socket came back:
  /// re-send `/driver/online` if the switch is still on.
  Future<void> _reOnline() async {
    if (_reOnlining || !state.wantOnline) return;
    _reOnlining = true;
    try {
      final fix = _latest ?? await _feed.currentFix();
      if (fix == null) return;
      await _api.driverOnline(lat: fix.lat, lng: fix.lng);
      state = state.copyWith(clearServerMessage: true);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        // Suspended / document expired while online: stop for real.
        await _stopStreaming();
        state = PresenceState(onTrip: state.onTrip, serverMessage: e.displayMessage);
      } else {
        debugPrint('re-online failed: $e');
      }
    } finally {
      _reOnlining = false;
    }
  }

  Future<void> _stopStreaming() async {
    _timer?.cancel();
    _timer = null;
    // Not awaited: a broadcast subscription's cancel future completes in the
    // root zone, which would stall callers under fake async.
    unawaited(_fixes?.cancel());
    _fixes = null;
    unawaited(_socket?.cancel());
    _socket = null;
    _batch.clear();
    _latest = null;
    try {
      await _feed.stop();
    } catch (e) {
      debugPrint('stop feed: $e');
    }
  }
}
