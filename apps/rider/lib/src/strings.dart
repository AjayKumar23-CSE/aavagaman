import 'package:intl/intl.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';

extension CommonStringsX on AppLocalizations {
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

  String rideStatusLabel(RideStatus s) => switch (s) {
        RideStatus.requested => statusLabelRequested,
        RideStatus.accepted => statusLabelAccepted,
        RideStatus.arrived => statusLabelArrived,
        RideStatus.started => statusLabelStarted,
        RideStatus.completed => statusLabelCompleted,
        RideStatus.paid => statusLabelPaid,
        RideStatus.cancelled => statusLabelCancelled,
        RideStatus.noDriver => statusLabelNoDriver,
      };

  String cancelActorLabel(CancelActor a) => switch (a) {
        CancelActor.rider => actorRider,
        CancelActor.driver => actorDriver,
        CancelActor.admin => actorAdmin,
        CancelActor.system => actorSystem,
      };

  String paymentMethodLabel(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => paymentCash,
        PaymentMethod.online => paymentOnline,
      };

  /// `paid_with` on a receipt: cash, upi, card, wallet (or the method name).
  String paidWithLabel(String paidWith) => switch (paidWith) {
        'cash' => paymentCash,
        'upi' => paidWithUpi,
        'card' => paidWithCard,
        'wallet' => paidWithWallet,
        _ => paymentOnline,
      };
}

/// "4 Oct, 12:08 pm" in the device's local time.
String formatDateTime(DateTime at) => DateFormat('d MMM, h:mm a', 'en').format(at.toLocal());
