import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

const config = AppConfig(apiBaseUrl: 'http://api.test');
const tokens = AuthTokens(accessToken: 'a1', refreshToken: 'r1');

ApiClient client(FakeAdapter adapter, [TokenStore? store]) =>
    ApiClient(config: config, tokens: store ?? MemoryTokenStore(tokens), adapter: adapter);

void main() {
  group('AuthApi', () {
    test('sendOtp posts phone + role without a bearer token', () async {
      final adapter = FakeAdapter((_) => (status: 200, body: {'sent': true, 'ttl': 300}));
      final ttl = await AuthApi(client(adapter)).sendOtp(phone: '+919800000002', role: LoginRole.rider);

      expect(ttl, 300);
      final call = adapter.calls.single;
      expect(call.uri.toString(), 'http://api.test/v1/auth/otp/send');
      expect(call.headers['Authorization'], isNull);
      expect(adapter.jsonBody(0), {'phone': '+919800000002', 'role': 'rider'});
    });

    test('sendOtp surfaces 429 OTP_RATE_LIMITED as ApiException', () async {
      final adapter = FakeAdapter(
          (_) => apiError(429, 'OTP_RATE_LIMITED', 'Too many code requests. Try again later.'));
      await expectLater(
        AuthApi(client(adapter)).sendOtp(phone: '9800000002', role: LoginRole.driver),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'OTP_RATE_LIMITED')
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.message, 'message', contains('Too many'))),
      );
    });

    test('verifyOtp sends the device block and parses tokens + user', () async {
      final adapter = FakeAdapter((_) => (status: 200, body: fixture('otp_verify_rider.json')));
      final result = await AuthApi(client(adapter)).verifyOtp(
        phone: '+919800000002',
        code: '123456',
        role: LoginRole.rider,
        device: const DeviceInfo(fcmToken: 'fcm-1', appVersion: '0.1.0+1'),
      );

      expect(result.tokens.accessToken, 'test-access-token');
      expect(result.user.needsName, isTrue);
      expect(adapter.jsonBody(0), {
        'phone': '+919800000002',
        'code': '123456',
        'role': 'rider',
        'device': {'platform': 'android', 'fcm_token': 'fcm-1', 'app_version': '0.1.0+1'},
      });
    });

    test('verifyOtp omits a missing FCM token', () async {
      final adapter = FakeAdapter((_) => (status: 200, body: fixture('otp_verify_rider.json')));
      await AuthApi(client(adapter))
          .verifyOtp(phone: '+919800000002', code: '123456', role: LoginRole.rider);
      expect((adapter.jsonBody(0) as Map)['device'], {'platform': 'android'});
    });

    test('ROLE_MISMATCH keeps the server message', () async {
      final adapter = FakeAdapter((_) => apiError(
          403, 'ROLE_MISMATCH', 'This number is registered as a driver. Use the driver app.'));
      await expectLater(
        AuthApi(client(adapter)).verifyOtp(phone: '+919800000002', code: '123456', role: LoginRole.rider),
        throwsA(isA<ApiException>().having((e) => e.displayMessage, 'msg', contains('driver app'))),
      );
    });
  });

  group('MeApi', () {
    test('update sends only provided fields', () async {
      final user = (fixture('otp_verify_rider.json')['user'] as Map<String, dynamic>)
        ..['name'] = 'Asha';
      final adapter = FakeAdapter((_) => (status: 200, body: user));
      final u = await MeApi(client(adapter)).update(name: 'Asha');

      expect(u.name, 'Asha');
      expect(adapter.calls.single.method, 'PATCH');
      expect(adapter.calls.single.headers['Authorization'], 'Bearer a1');
      expect(adapter.jsonBody(0), {'name': 'Asha'});
    });

    test('registerFcmToken and delete accept 204', () async {
      final adapter = FakeAdapter((_) => (status: 204, body: null));
      final api = MeApi(client(adapter));
      await api.registerFcmToken('fcm-token-123');
      await api.delete();

      expect(adapter.calls.map((c) => '${c.method} ${c.path}'), ['POST /me/fcm-token', 'DELETE /me']);
      expect(adapter.jsonBody(0), {'token': 'fcm-token-123'});
    });

    test('delete surfaces 409 ACTIVE_RIDE', () async {
      final adapter = FakeAdapter((_) => apiError(409, 'ACTIVE_RIDE', 'Finish your ride first'));
      await expectLater(MeApi(client(adapter)).delete(),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ACTIVE_RIDE')));
    });
  });

  group('DriverApi', () {
    test('register sends the SPEC body and parses the profile', () async {
      final adapter = FakeAdapter((_) => (status: 200, body: fixture('driver_me_pending.json')));
      final p = await DriverApi(client(adapter)).register(DriverRegistration(
        name: 'Ravi Kumar',
        licenceNo: 'DL0420110012345',
        licenceExpiry: DateTime(2031, 5, 31),
        dateOfBirth: DateTime(1990, 6, 15),
        vehicle: const VehicleInput(
          regNumber: 'DL01AB1234',
          make: 'Maruti Suzuki',
          model: 'Dzire',
          colour: 'White',
          fuelType: FuelType.cng,
        ),
      ));

      expect(p.registered, isTrue);
      expect(adapter.jsonBody(0), {
        'name': 'Ravi Kumar',
        'licence_no': 'DL0420110012345',
        'licence_expiry': '2031-05-31',
        'date_of_birth': '1990-06-15',
        'vehicle': {
          'reg_number': 'DL01AB1234',
          'make': 'Maruti Suzuki',
          'model': 'Dzire',
          'colour': 'White',
          'fuel_type': 'cng',
          'vehicle_type': 'sedan',
        },
      });
    });

    test('VALIDATION_FAILED details are shown to the user', () async {
      final adapter = FakeAdapter((_) => (
            status: 400,
            body: {
              'error': {
                'code': 'VALIDATION_FAILED',
                'message': 'Validation failed',
                'details': ['vehicle.reg_number must look like DL01AB1234'],
              },
            },
          ));
      await expectLater(
        DriverApi(client(adapter)).me(),
        throwsA(isA<ApiException>().having(
            (e) => e.displayMessage, 'msg', contains('reg_number must look like DL01AB1234'))),
      );
    });

    test('uploadDocument: presign → bare PUT to storage → register document', () async {
      const uploadUrl = 'https://r2.test/bucket/drivers/u1/insurance/k.jpg?X-Amz-Signature=abc';
      final adapter = FakeAdapter((o) => switch (o.path) {
            '/driver/documents/presign' => (
                status: 200,
                body: {
                  'upload_url': uploadUrl,
                  'file_key': 'drivers/u1/insurance/k.jpg',
                  'expires_in': 600,
                },
              ),
            '/driver/documents' => (
                status: 201,
                body: {
                  'id': 'd1',
                  'doc_type': 'insurance',
                  'status': 'pending',
                  'reviewer_note': null,
                  'expiry': '2027-03-31',
                  'uploaded_at': '2026-09-27T19:11:05.908Z',
                },
              ),
            _ => (status: 200, body: null),
          });
      final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final progress = <double>[];

      final doc = await DriverApi(client(adapter)).uploadDocument(
        DocType.insurance,
        bytes,
        expiry: DateTime(2027, 3, 31),
        onProgress: progress.add,
      );

      expect(doc.type, DocType.insurance);
      expect(doc.expiry, DateTime.utc(2027, 3, 31));
      expect(adapter.calls.map((c) => c.method), ['POST', 'PUT', 'POST']);
      expect(adapter.jsonBody(0), {'doc_type': 'insurance', 'content_type': 'image/jpeg'});

      final put = adapter.calls[1];
      expect(put.uri.toString(), uploadUrl);
      expect(put.headers['Authorization'], isNull);
      expect(put.headers['content-type'] ?? put.contentType, 'image/jpeg');
      expect(adapter.bodies[1], bytes);

      expect(adapter.jsonBody(2), {
        'doc_type': 'insurance',
        'file_key': 'drivers/u1/insurance/k.jpg',
        'expiry': '2027-03-31',
      });
      expect(progress.first, 0);
      expect(progress.last, 1);
    });

    test('createDocument sends id_last4 for ID proof', () async {
      final adapter = FakeAdapter((_) => (
            status: 201,
            body: {'id': 'd', 'doc_type': 'id_proof', 'status': 'pending', 'uploaded_at': null},
          ));
      await DriverApi(client(adapter)).createDocument(DocType.idProof, 'k', idLast4: '1234');
      expect(adapter.jsonBody(0), {'doc_type': 'id_proof', 'file_key': 'k', 'id_last4': '1234'});
    });
  });
}
