import 'package:socket_io_client/socket_io_client.dart' as sio;

/// The slice of a Socket.io client that [RealtimeClient] needs. Real
/// connections use [SocketIoRealtimeSocket]; tests drive a fake.
abstract class RealtimeSocket {
  bool get connected;

  void connect();

  void disconnect();

  void dispose();

  /// Registers a handler for a server event or a reserved event
  /// (`connect`, `disconnect`, `connect_error`, `reconnect_attempt`).
  void on(String event, void Function(dynamic data) handler);

  /// Emits [data] and calls [onAck] with the server's acknowledgement.
  void emitWithAck(String event, Map<String, dynamic> data, void Function(dynamic ack) onAck);
}

/// Supplies the handshake `auth` payload on every (re)connect, so a rotated
/// access token is picked up without rebuilding the socket.
typedef AuthProvider = Future<Map<String, dynamic>> Function();

class SocketIoRealtimeSocket implements RealtimeSocket {
  /// [url] is the namespace URL, e.g. `http://10.0.2.2:3000/rt`.
  SocketIoRealtimeSocket(String url, AuthProvider auth)
      : _socket = sio.io(
          url,
          sio.OptionBuilder()
              .setTransports(['websocket'])
              .disableAutoConnect()
              .enableReconnection()
              .setReconnectionDelay(1000)
              .setReconnectionDelayMax(15000)
              .setRandomizationFactor(0.5)
              .setAuthFn((callback) {
                auth().then(callback, onError: (_) => callback({'token': ''}));
              })
              .build(),
        );

  final sio.Socket _socket;

  @override
  bool get connected => _socket.connected;

  @override
  void connect() => _socket.connect();

  @override
  void disconnect() => _socket.disconnect();

  @override
  void dispose() => _socket.dispose();

  @override
  void on(String event, void Function(dynamic data) handler) {
    switch (event) {
      case 'connect':
        _socket.onConnect(handler);
      case 'disconnect':
        _socket.onDisconnect(handler);
      case 'connect_error':
        _socket.onConnectError(handler);
      case 'reconnect_attempt':
        _socket.io.on('reconnect_attempt', handler);
      default:
        _socket.on(event, handler);
    }
  }

  @override
  void emitWithAck(String event, Map<String, dynamic> data, void Function(dynamic ack) onAck) =>
      _socket.emitWithAck(event, data, ack: onAck);
}
