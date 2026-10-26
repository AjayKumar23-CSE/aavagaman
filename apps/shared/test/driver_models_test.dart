import 'package:flutter_test/flutter_test.dart';
import 'package:ride_shared/ride_shared.dart';

import 'fake_adapter.dart';

void main() {
  test('parses a real GET /driver/me response (registered, docs pending)', () {
    final p = DriverProfile.fromJson(fixture('driver_me_pending.json'));

    expect(p.name, 'Ravi Kumar');
    expect(p.verificationStatus, VerificationStatus.pending);
    expect(p.registered, isTrue);
    expect(p.needsRegistration, isFalse);
    expect(p.licenceNo, 'DL0420110012345');
    expect(p.licenceExpiry, DateTime.utc(2031, 5, 31));
    expect(p.dateOfBirth, DateTime.utc(1990, 6, 15));
    expect(p.ratingAvg, 5.0);
    expect(p.vehicle!.regNumber, startsWith('DL01AB'));
    expect(p.vehicle!.fuelType, FuelType.cng);
    expect(p.vehicle!.vehicleType, 'sedan');
    expect(p.vehicle!.insuranceExpiry, isNull);
    expect(p.documents.single.type, DocType.rc);
    expect(p.documents.single.status, VerificationStatus.pending);
    expect(p.missingDocuments, [
      DocType.drivingLicence,
      DocType.insurance,
      DocType.permit,
      DocType.idProof,
      DocType.selfie,
    ]);
    expect(p.notUploaded, p.missingDocuments);
    expect(p.canGoOnline, isFalse);
  });

  test('rejected document keeps its note and counts as missing, not un-uploaded', () {
    final p = DriverProfile.fromJson(fixture('driver_me_rejected_doc.json'));

    final rc = p.documentFor(DocType.rc)!;
    expect(rc.status, VerificationStatus.rejected);
    expect(rc.reviewerNote, 'RC photo is blurry, please re-upload');
    expect(p.rejectedDocuments.single.type, DocType.rc);
    expect(p.missingDocuments, [DocType.rc]);
    expect(p.notUploaded, isEmpty);
    expect(p.documentFor(DocType.insurance)!.expiry, DateTime.utc(2027, 3, 31));
  });

  test('new driver: not registered, no vehicle, unknown doc types ignored', () {
    final p = DriverProfile.fromJson({
      'user_id': 'u1',
      'name': null,
      'phone': '+919800000001',
      'verification_status': 'rejected',
      'reviewer_note': 'Licence number does not match',
      'registered': false,
      'rating_avg': '4.5',
      'vehicle': null,
      'documents': [
        {'id': 'x', 'doc_type': 'passport', 'status': 'pending', 'uploaded_at': null},
      ],
      'missing_documents': ['driving_licence', 'passport'],
      'expired_documents': [],
      'can_go_online': false,
    });
    expect(p.needsRegistration, isTrue);
    expect(p.vehicle, isNull);
    expect(p.documents, isEmpty);
    expect(p.missingDocuments, [DocType.drivingLicence]);
    expect(p.ratingAvg, 4.5);
  });

  test('DocType wire names and rules match the backend', () {
    expect(DocType.values.map((t) => t.wire), [
      'driving_licence',
      'rc',
      'insurance',
      'permit',
      'id_proof',
      'selfie',
      'fitness',
    ]);
    expect(
      DocType.values.where((t) => t.requiresExpiry),
      [DocType.drivingLicence, DocType.insurance, DocType.permit, DocType.fitness],
    );
    expect(DocType.mandatoryTypes, hasLength(6));
    expect(DocType.fitness.mandatory, isFalse);
    expect(DocType.idProof.requiresIdLast4, isTrue);
    expect(DocType.tryParse('selfie'), DocType.selfie);
    expect(DocType.tryParse('nope'), isNull);
    expect(DocType.rc.label, contains('RC'));
  });

  test('VerificationStatus tolerates unknown values', () {
    expect(VerificationStatus.fromWire('suspended'), VerificationStatus.suspended);
    expect(VerificationStatus.fromWire('weird'), VerificationStatus.pending);
  });

  test('API dates round-trip as calendar dates', () {
    expect(parseApiDate('2031-05-31'), DateTime.utc(2031, 5, 31));
    expect(parseApiDate(null), isNull);
    expect(formatApiDate(DateTime(2027, 3, 4, 23, 59)), '2027-03-04');
  });

  test('User parses the OTP verify payload', () {
    final u = User.fromJson(fixture('otp_verify_rider.json')['user'] as Map<String, dynamic>);
    expect(u.role, UserRole.rider);
    expect(u.needsName, isTrue);
    expect(u.ratingAvg, 5.0);
    expect(u.createdAt, isNotNull);
  });

  group('IndianPhone mirrors backend normalizeIndianPhone', () {
    const cases = {
      '9812345678': '+919812345678',
      '09812345678': '+919812345678',
      '919812345678': '+919812345678',
      '+91 98123 45678': '+919812345678',
      '+91-98123-45678': '+919812345678',
      '(981) 234-5678': '+919812345678',
      '6000000000': '+916000000000',
    };
    for (final e in cases.entries) {
      test('accepts "${e.key}"', () => expect(IndianPhone.normalize(e.key), e.value));
    }
    for (final bad in ['5812345678', '981234567', '98123456789', '+929812345678', 'abc', '']) {
      test('rejects "$bad"', () => expect(IndianPhone.normalize(bad), isNull));
    }
    test('formats for display', () {
      expect(IndianPhone.format('+919812345678'), '+91 98123 45678');
      expect(IndianPhone.format('deleted:abc'), 'deleted:abc');
    });
  });
}
