import 'package:intl/intl.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';

extension DriverStringsX on AppLocalizations {
  CommonStrings get common => CommonStrings(
    appName: appTitle,
    tagline: appTagline,
        splashQuote: splashQuote,
    phoneConsent: phoneConsent,
    phoneTitle: phoneTitle,
    phoneSubtitle: phoneSubtitle,
    phoneLabel: phoneLabel,
    invalidPhone: invalidPhone,
    continueLabel: continueLabel,
    otpTitle: otpTitle,
    otpSubtitle: otpSubtitle,
    resendIn: resendIn,
    resend: resend,
    codeResent: codeResent,
    changeNumber: changeNumber,
    retry: retry,
    networkError: networkError,
    genericError: genericError,
  );

  String docType(DocType t) => switch (t) {
    DocType.drivingLicence => docDrivingLicence,
    DocType.rc => docRc,
    DocType.insurance => docInsurance,
    DocType.permit => docPermit,
    DocType.idProof => docIdProof,
    DocType.selfie => docSelfie,
    DocType.fitness => docFitness,
  };

  String fuel(FuelType f) => switch (f) {
    FuelType.petrol => fuelPetrol,
    FuelType.diesel => fuelDiesel,
    FuelType.cng => fuelCng,
    FuelType.ev => fuelEv,
  };

  String verification(VerificationStatus s) => switch (s) {
    VerificationStatus.pending => statusPending,
    VerificationStatus.approved => statusApproved,
    VerificationStatus.rejected => statusRejected,
    VerificationStatus.suspended => statusSuspended,
  };
}

/// "31 May 2031" for an API calendar date.
String formatDate(DateTime date) => DateFormat('d MMM yyyy', 'en').format(date);
