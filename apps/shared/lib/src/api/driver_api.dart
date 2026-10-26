import 'dart:typed_data';
import '../models/vehicle_type.dart';

import 'package:dio/dio.dart';

import '../models/driver.dart';
import 'api_client.dart';
import 'api_exception.dart';

class PresignedUpload {
  const PresignedUpload({required this.uploadUrl, required this.fileKey, required this.expiresIn});

  factory PresignedUpload.fromJson(Map<String, dynamic> json) => PresignedUpload(
        uploadUrl: json['upload_url'] as String,
        fileKey: json['file_key'] as String,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 600,
      );

  final String uploadUrl;
  final String fileKey;
  final int expiresIn;
}

class VehicleInput {
  const VehicleInput({
    required this.regNumber,
    required this.make,
    required this.model,
    required this.colour,
    required this.fuelType,
    this.vehicleType = VehicleType.sedan,
  });

  final String regNumber;
  final String make;
  final String model;
  final String colour;
  final FuelType fuelType;
  final VehicleType vehicleType;

  Map<String, dynamic> toJson() => {
        'reg_number': regNumber,
        'vehicle_type': vehicleType.wire,
        'make': make,
        'model': model,
        'colour': colour,
        'fuel_type': fuelType.name,
      };
}

class DriverRegistration {
  const DriverRegistration({
    required this.name,
    required this.licenceNo,
    required this.licenceExpiry,
    required this.dateOfBirth,
    required this.vehicle,
  });

  final String name;
  final String licenceNo;
  final DateTime licenceExpiry;

  /// As printed on the licence; the admin needs it for the Parivahan check.
  final DateTime dateOfBirth;
  final VehicleInput vehicle;

  Map<String, dynamic> toJson() => {
        'name': name,
        'licence_no': licenceNo,
        'licence_expiry': formatApiDate(licenceExpiry),
        'date_of_birth': formatApiDate(dateOfBirth),
        'vehicle': vehicle.toJson(),
      };
}

/// SPEC §7.3 driver onboarding endpoints.
class DriverApi {
  DriverApi(this._client);

  final ApiClient _client;

  /// `GET /driver/me`.
  Future<DriverProfile> me() => guardApi(() async {
        final res = await _client.dio.get<Map<String, dynamic>>('/driver/me');
        return DriverProfile.fromJson(res.data!);
      });

  /// `POST /driver/register`. 409 `ALREADY_REGISTERED`, 422 `LICENCE_EXPIRED`,
  /// 400 `VALIDATION_FAILED`.
  Future<DriverProfile> register(DriverRegistration input) => guardApi(() async {
        final res = await _client.dio
            .post<Map<String, dynamic>>('/driver/register', data: input.toJson());
        return DriverProfile.fromJson(res.data!);
      });

  /// `POST /driver/documents/presign`.
  Future<PresignedUpload> presign(DocType type, {String contentType = 'image/jpeg'}) =>
      guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>(
          '/driver/documents/presign',
          data: {'doc_type': type.wire, 'content_type': contentType},
        );
        return PresignedUpload.fromJson(res.data!);
      });

  /// PUTs [bytes] to a presigned URL. Uses a bare Dio: no base URL and no
  /// bearer token (object storage would reject the extra auth header).
  Future<void> putObject(
    String uploadUrl,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
    void Function(int sent, int total)? onProgress,
  }) =>
      guardApi(() => _client.uploadDio.putUri<void>(
            Uri.parse(uploadUrl),
            data: Stream<List<int>>.value(bytes),
            options: Options(headers: {
              Headers.contentTypeHeader: contentType,
              Headers.contentLengthHeader: bytes.length,
            }),
            onSendProgress: onProgress,
          ));

  /// `POST /driver/documents`. [expiry] is required for [DocType.requiresExpiry]
  /// and [idLast4] for [DocType.idProof].
  Future<DriverDocument> createDocument(
    DocType type,
    String fileKey, {
    DateTime? expiry,
    String? idLast4,
  }) =>
      guardApi(() async {
        final res = await _client.dio.post<Map<String, dynamic>>('/driver/documents', data: {
          'doc_type': type.wire,
          'file_key': fileKey,
          if (expiry != null) 'expiry': formatApiDate(expiry),
          'id_last4': ?idLast4,
        });
        return DriverDocument.fromJson(res.data!);
      });

  /// presign → PUT → register in one go. [onProgress] reports 0..1.
  Future<DriverDocument> uploadDocument(
    DocType type,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
    DateTime? expiry,
    String? idLast4,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0);
    final presigned = await presign(type, contentType: contentType);
    await putObject(
      presigned.uploadUrl,
      bytes,
      contentType: contentType,
      onProgress: (sent, total) {
        if (total > 0) onProgress?.call(0.05 + 0.9 * sent / total);
      },
    );
    final doc = await createDocument(type, presigned.fileKey, expiry: expiry, idLast4: idLast4);
    onProgress?.call(1);
    return doc;
  }
}
