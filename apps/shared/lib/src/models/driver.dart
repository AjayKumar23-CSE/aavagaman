/// Driver onboarding models (SPEC §5 drivers / vehicles / driver_documents,
/// §7.3 `GET /driver/me`).
library;

import 'json.dart';

/// `verification_status` enum; also used as a document's review status.
enum VerificationStatus {
  pending,
  approved,
  rejected,
  suspended;

  /// Unknown values fall back to [pending] so a newer backend cannot crash
  /// the app.
  static VerificationStatus fromWire(Object? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => pending);
}

/// `doc_type` enum. Order is the order shown in the driver app.
enum DocType {
  drivingLicence('driving_licence', requiresExpiry: true),
  rc('rc'),
  insurance('insurance', requiresExpiry: true),
  permit('permit', requiresExpiry: true),
  idProof('id_proof', requiresIdLast4: true),
  selfie('selfie'),
  fitness('fitness', requiresExpiry: true, mandatory: false);

  const DocType(
    this.wire, {
    this.requiresExpiry = false,
    this.requiresIdLast4 = false,
    this.mandatory = true,
  });

  final String wire;

  /// `POST /driver/documents` rejects these without `expiry` (EXPIRY_REQUIRED).
  final bool requiresExpiry;

  /// `id_proof` needs the last 4 digits of the ID (ID_LAST4_REQUIRED).
  final bool requiresIdLast4;

  /// Needed before a driver can go online (D-013). Fitness is optional.
  final bool mandatory;

  /// Default English label. The apps localise via their ARB files.
  String get label => switch (this) {
        drivingLicence => 'Driving licence',
        rc => 'Registration certificate (RC)',
        insurance => 'Vehicle insurance',
        permit => 'Permit',
        idProof => 'ID proof',
        selfie => 'Selfie',
        fitness => 'Fitness certificate',
      };

  static DocType? tryParse(Object? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }

  static List<DocType> get mandatoryTypes =>
      values.where((t) => t.mandatory).toList(growable: false);
}

enum FuelType {
  petrol,
  diesel,
  cng,
  ev;

  static FuelType? tryParse(Object? value) {
    for (final f in values) {
      if (f.name == value) return f;
    }
    return null;
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.regNumber,
    required this.make,
    required this.model,
    required this.colour,
    this.vehicleType,
    this.fuelType,
    this.insuranceExpiry,
    this.permitExpiry,
    this.fitnessExpiry,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        regNumber: json['reg_number'] as String,
        make: json['make'] as String,
        model: json['model'] as String,
        colour: json['colour'] as String,
        vehicleType: json['vehicle_type'] as String?,
        fuelType: FuelType.tryParse(json['fuel_type']),
        insuranceExpiry: parseApiDate(json['insurance_expiry']),
        permitExpiry: parseApiDate(json['permit_expiry']),
        fitnessExpiry: parseApiDate(json['fitness_expiry']),
      );

  final String id;
  final String regNumber;
  final String make;
  final String model;
  final String colour;
  final String? vehicleType;
  final FuelType? fuelType;
  final DateTime? insuranceExpiry;
  final DateTime? permitExpiry;
  final DateTime? fitnessExpiry;
}

class DriverDocument {
  const DriverDocument({
    required this.id,
    required this.type,
    required this.status,
    this.reviewerNote,
    this.expiry,
    this.uploadedAt,
  });

  factory DriverDocument.fromJson(Map<String, dynamic> json) => DriverDocument(
        id: json['id'] as String,
        type: DocType.tryParse(json['doc_type'])!,
        status: VerificationStatus.fromWire(json['status']),
        reviewerNote: json['reviewer_note'] as String?,
        expiry: parseApiDate(json['expiry']),
        uploadedAt: asInstant(json['uploaded_at']),
      );

  final String id;
  final DocType type;

  /// pending, approved or rejected.
  final VerificationStatus status;
  final String? reviewerNote;

  /// Calendar date (UTC midnight) or null.
  final DateTime? expiry;
  final DateTime? uploadedAt;
}

class DriverProfile {
  const DriverProfile({
    required this.userId,
    required this.phone,
    required this.verificationStatus,
    required this.registered,
    required this.documents,
    required this.missingDocuments,
    required this.expiredDocuments,
    required this.canGoOnline,
    this.name,
    this.reviewerNote,
    this.licenceNo,
    this.licenceExpiry,
    this.dateOfBirth,
    this.approvedAt,
    this.ratingAvg,
    this.vehicle,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        userId: json['user_id'] as String,
        name: json['name'] as String?,
        phone: json['phone'] as String,
        verificationStatus: VerificationStatus.fromWire(json['verification_status']),
        reviewerNote: json['reviewer_note'] as String?,
        licenceNo: json['licence_no'] as String?,
        licenceExpiry: parseApiDate(json['licence_expiry']),
        dateOfBirth: parseApiDate(json['date_of_birth']),
        approvedAt: asInstant(json['approved_at']),
        registered: json['registered'] == true,
        ratingAvg: asDouble(json['rating_avg']),
        vehicle: json['vehicle'] is Map<String, dynamic>
            ? Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>)
            : null,
        // Skip document types this app version does not know about.
        documents: [
          for (final d in (json['documents'] as List? ?? const []).cast<Map<String, dynamic>>())
            if (DocType.tryParse(d['doc_type']) != null) DriverDocument.fromJson(d),
        ],
        missingDocuments: _docTypes(json['missing_documents']),
        expiredDocuments: _docTypes(json['expired_documents']),
        canGoOnline: json['can_go_online'] == true,
      );

  final String userId;
  final String? name;
  final String phone;
  final VerificationStatus verificationStatus;
  final String? reviewerNote;
  final String? licenceNo;
  final DateTime? licenceExpiry;
  final DateTime? dateOfBirth;
  final DateTime? approvedAt;

  /// Profile and vehicle submitted (`POST /driver/register` done).
  final bool registered;
  final double? ratingAvg;
  final Vehicle? vehicle;

  /// Latest upload per document type.
  final List<DriverDocument> documents;

  /// Mandatory types that are missing or rejected.
  final List<DocType> missingDocuments;
  final List<DocType> expiredDocuments;
  final bool canGoOnline;

  DriverDocument? documentFor(DocType type) {
    for (final d in documents) {
      if (d.type == type) return d;
    }
    return null;
  }

  /// Mandatory types never uploaded (as opposed to uploaded and rejected).
  List<DocType> get notUploaded =>
      DocType.mandatoryTypes.where((t) => documentFor(t) == null).toList(growable: false);

  List<DriverDocument> get rejectedDocuments =>
      documents.where((d) => d.status == VerificationStatus.rejected).toList(growable: false);

  /// Registration form must be (re)submitted.
  bool get needsRegistration =>
      !registered || verificationStatus == VerificationStatus.rejected;
}

/// Parses `YYYY-MM-DD` as a UTC calendar date.
DateTime? parseApiDate(Object? value) {
  if (value is! String || value.length < 10) return null;
  final d = DateTime.tryParse(value.substring(0, 10));
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

/// Formats a calendar date as the API's `YYYY-MM-DD`.
String formatApiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<DocType> _docTypes(Object? value) => [
      for (final v in (value as List? ?? const []))
        ?DocType.tryParse(v),
    ];
