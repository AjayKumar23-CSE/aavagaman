import 'dart:typed_data';

import 'package:driver/src/documents/document_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'helpers.dart';

/// Opens the Documents screen for [profile] (a pending driver lands on
/// Pending, so go through "Fix documents" / the gate as needed).
Future<void> openDocuments(WidgetTester tester, FakeDriverApi api, {FakeImages? images}) async {
  tallScreen(tester);
  await tester.pumpWidget(testApp(driver: api, images: images));
  await tester.pumpAndSettle();
  if (find.text('Fix documents').evaluate().isNotEmpty) {
    await tester.tap(find.text('Fix documents'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('lists all 7 documents with status, expiry and reviewer note', (tester) async {
    await openDocuments(tester, FakeDriverApi(profileFrom('driver_me_rejected_doc.json')));

    expect(find.text('Upload a clear photo of each document. We\'ll review them within 1–2 working days.'),
        findsOneWidget);
    expect(find.text('Driving licence'), findsOneWidget);
    expect(find.text('Registration certificate (RC)'), findsOneWidget);
    expect(find.text('Fitness certificate'), findsOneWidget);

    expect(find.text('Approved'), findsNWidgets(2)); // licence + selfie
    expect(find.text('Under review'), findsNWidgets(3)); // insurance, permit, id proof
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('RC photo is blurry, please re-upload'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget); // fitness certificate
    expect(find.text('Valid until 31 May 2031'), findsOneWidget);
    expect(find.text('Valid until 31 Mar 2027'), findsOneWidget);
    expect(find.text('Re-upload'), findsNWidgets(6));
    expect(find.text('Upload'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new registration: shows not-uploaded docs and blocks Continue', (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_pending.json'));
    await openDocuments(tester, api);

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget); // the real fixture has RC pending
    expect(find.text('Not uploaded'), findsNWidgets(6));
    expect(find.text('5 documents left to upload'), findsOneWidget);
    final continueBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueBtn.onPressed, isNull);
  });

  testWidgets('ID proof upload: gallery → last-4 → presign/PUT/register; retry re-registers only',
      (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_pending.json'))
      ..createErrorOnce = const ApiException(code: 'NETWORK_ERROR', message: 'offline');
    final images = FakeImages();
    await openDocuments(tester, api, images: images);

    await tester.tap(find.text('ID proof (Aadhaar, PAN or voter ID)'));
    await tester.pumpAndSettle();
    expect(find.text('Upload ID proof (Aadhaar, PAN or voter ID)'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Take or choose a photo first'), findsOneWidget);

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(images.sources, [PhotoSource.gallery]);

    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Enter exactly 4 digits'), findsOneWidget);
    expect(api.presigned, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Last 4 digits of the ID number'), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();

    // Stored in R2 but registering failed → error + retry.
    expect(api.presigned, [DocType.idProof]);
    expect(api.puts.single, images.bytes);
    expect(find.text("Can't reach the server. Check your connection and try again."), findsOneWidget);

    // Profile after the upload.
    api.profile = profileFrom('driver_me_pending.json', (j) {
      (j['documents'] as List).add({
        'id': 'n',
        'doc_type': 'id_proof',
        'status': 'pending',
        'reviewer_note': null,
        'expiry': null,
        'uploaded_at': '2026-09-28T10:00:00.000Z',
      });
      (j['missing_documents'] as List).remove('id_proof');
    });
    await tester.tap(find.widgetWithText(FilledButton, 'Retry upload'));
    await tester.pumpAndSettle();

    expect(api.presigned, hasLength(1), reason: 'retry must not re-upload the file');
    expect(api.created.map((c) => c.key), ['drivers/u1/id_proof/k1.jpg', 'drivers/u1/id_proof/k1.jpg']);
    expect(api.created.last.idLast4, '1234');
    expect(api.created.last.expiry, isNull);
    expect(find.text('Document uploaded'), findsOneWidget);
    expect(find.text('4 documents left to upload'), findsOneWidget);
  });

  testWidgets('insurance upload requires an expiry date', (tester) async {
    final api = FakeDriverApi(profileFrom('driver_me_pending.json'));
    await openDocuments(tester, api);

    await tester.tap(find.text('Vehicle insurance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget);

    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
    await tester.pumpAndSettle();

    expect(api.created.single.type, DocType.insurance);
    expect(api.created.single.expiry!.isAfter(DateTime.now()), isTrue);
  });

  group('compressToLimit', () {
    test('steps quality/size down until the JPEG fits in 800 KB', () async {
      final calls = <(int, int)>[];
      final out = await compressToLimit(
        Uint8List(10),
        encode: (input, side, quality) async {
          calls.add((side, quality));
          // Pretend size scales with side² × quality.
          final size = side * side * quality ~/ 100;
          return Uint8List(size);
        },
      );
      expect(out.lengthInBytes, lessThanOrEqualTo(maxDocumentBytes));
      expect(calls.first, (1600, 85));
      expect(calls.length, greaterThan(1));
      expect(calls, compressionSteps.take(calls.length));
    });

    test('small images are still re-encoded once', () async {
      var n = 0;
      final out = await compressToLimit(Uint8List(10), encode: (i, s, q) async {
        n++;
        return Uint8List(1000);
      });
      expect(n, 1);
      expect(out.lengthInBytes, 1000);
    });

    test('fails when nothing fits', () async {
      await expectLater(
        compressToLimit(Uint8List(10), encode: (i, s, q) async => Uint8List(maxDocumentBytes + 1)),
        throwsStateError,
      );
    });
  });
}
