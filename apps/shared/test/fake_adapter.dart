import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef FakeRoute = ({int status, Object? body});

/// Routes requests to canned responses and records calls (and raw bodies).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeRoute Function(RequestOptions o) handler;
  final calls = <RequestOptions>[];

  /// Raw request bytes, parallel to [calls].
  final bodies = <Uint8List>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final bytes = BytesBuilder();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    bodies.add(bytes.takeBytes());
    final r = handler(options);
    return ResponseBody.fromString(
      r.body == null ? '' : jsonEncode(r.body),
      r.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// Request body of call [i] decoded as JSON.
  Object? jsonBody(int i) => jsonDecode(utf8.decode(bodies[i]));

  @override
  void close({bool force = false}) {}
}

/// Reads `test/fixtures/<name>` as a JSON object.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// Reads `test/fixtures/<name>` as a JSON array.
List<dynamic> fixtureList(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List<dynamic>;

FakeRoute apiError(int status, String code, String message) =>
    (status: status, body: {'error': {'code': code, 'message': message}});
