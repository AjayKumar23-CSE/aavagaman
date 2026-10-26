import 'realtime_socket.dart';

/// In-memory [RealtimeSocket] for tests: push server events with
/// [serverEmit], inspect sent events in [emitted], answer acks via [ackHandler].
class FakeRealtimeSocket implements RealtimeSocket {
  FakeRealtimeSocket(this.url, this.auth);

  final String url;
  final AuthProvider auth;
  final _handlers = <String, List<void Function(dynamic)>>{};

  /// `(event, data)` pairs the client emitted, in order.
  final emitted = <({String event, Map<String, dynamic> data})>[];

  /// Decides the acknowledgement for an emitted event; defaults to `{ok:true}`.
  dynamic Function(String event, Map<String, dynamic> data)? ackHandler;

  /// Set to false to swallow emits (simulates a lost ack).
  bool autoAck = true;

  /// Handshake payloads seen on each [connect].
  final handshakes = <Map<String, dynamic>>[];
  int connectCalls = 0;
  int disconnectCalls = 0;
  bool disposed = false;

  @override
  bool connected = false;

  @override
  void connect() {
    connectCalls++;
    auth().then(handshakes.add);
  }

  @override
  void disconnect() {
    disconnectCalls++;
    final was = connected;
    connected = false;
    if (was) serverEmit('disconnect', 'io client disconnect');
  }

  @override
  void dispose() => disposed = true;

  @override
  void on(String event, void Function(dynamic data) handler) =>
      _handlers.putIfAbsent(event, () => []).add(handler);

  @override
  void emitWithAck(String event, Map<String, dynamic> data, void Function(dynamic ack) onAck) {
    emitted.add((event: event, data: data));
    if (!autoAck) return;
    final ack = ackHandler?.call(event, data) ?? {'ok': true};
    Future.microtask(() => onAck(ack));
  }

  /// Simulates the server: delivers [data] to the handlers of [event].
  void serverEmit(String event, dynamic data) {
    for (final h in List.of(_handlers[event] ?? const [])) {
      h(data);
    }
  }

  /// Completes the handshake.
  void serverConnect() {
    connected = true;
    serverEmit('connect', null);
  }

  /// Rejects the handshake (`connect_error`), e.g. `{'message': 'UNAUTHORIZED'}`.
  void serverReject(dynamic error) {
    connected = false;
    serverEmit('connect_error', error);
  }

  /// Drops the transport; the client shows "reconnecting".
  void serverDrop() {
    connected = false;
    serverEmit('disconnect', 'transport close');
  }
}
