import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// SPEC §12: documents are uploaded as JPEG of at most 800 KB.
const maxDocumentBytes = 800 * 1024;

enum PhotoSource { camera, gallery }

/// Picks a document photo and returns it as an upload-ready JPEG.
abstract class DocumentImageService {
  /// Null when the user cancels.
  Future<Uint8List?> pick(PhotoSource source, {bool frontCamera = false});
}

final documentImageServiceProvider = Provider<DocumentImageService>((ref) => const DeviceDocumentImageService());

class DeviceDocumentImageService implements DocumentImageService {
  const DeviceDocumentImageService();

  @override
  Future<Uint8List?> pick(PhotoSource source, {bool frontCamera = false}) async {
    final file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: frontCamera ? CameraDevice.front : CameraDevice.rear,
      // Pre-shrink huge camera images; final size is enforced below.
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (file == null) return null;
    return compressToLimit(await file.readAsBytes());
  }
}

typedef JpegEncoder = Future<Uint8List> Function(Uint8List input, int maxSide, int quality);

/// (longest side in px, JPEG quality), from best to smallest.
const compressionSteps = [(1600, 85), (1600, 70), (1280, 70), (1280, 55), (1024, 55), (1024, 40), (800, 40), (640, 30)];

/// Re-encodes [input] as JPEG, stepping quality and size down until it fits
/// in [maxBytes]. Always re-encodes once so PNG/HEIC become JPEG and EXIF
/// (GPS, device) is stripped.
Future<Uint8List> compressToLimit(
  Uint8List input, {
  int maxBytes = maxDocumentBytes,
  JpegEncoder encode = _flutterEncode,
}) async {
  Uint8List? last;
  for (final (side, quality) in compressionSteps) {
    last = await encode(input, side, quality);
    if (last.lengthInBytes <= maxBytes) return last;
  }
  throw StateError('Could not compress image below $maxBytes bytes (got ${last!.lengthInBytes})');
}

Future<Uint8List> _flutterEncode(Uint8List input, int maxSide, int quality) => FlutterImageCompress.compressWithList(
  input,
  // The plugin scales down (never up) keeping the aspect ratio so the
  // image fits these bounds.
  minWidth: maxSide,
  minHeight: maxSide,
  quality: quality,
  format: CompressFormat.jpeg,
  keepExif: false,
);
