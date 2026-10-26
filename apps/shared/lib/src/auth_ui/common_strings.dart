import '../api/api_exception.dart';

/// Localised strings for the shared screens. Each app builds one from its own
/// ARB file, so every user-facing string stays in `app_en.arb`.
class CommonStrings {
  const CommonStrings({
    required this.appName,
    required this.tagline,
    this.splashQuote = 'Har safar ka apna ek maqsad hota hai.',
    required this.phoneConsent,
    required this.phoneTitle,
    required this.phoneSubtitle,
    required this.phoneLabel,
    required this.invalidPhone,
    required this.continueLabel,
    required this.otpTitle,
    required this.otpSubtitle,
    required this.resendIn,
    required this.resend,
    required this.codeResent,
    required this.changeNumber,
    required this.retry,
    required this.networkError,
    required this.genericError,
  });

  final String appName;

  /// Short line under the app name on the login screens.
  final String tagline;

  /// Line under the splash illustration (D-057).
  final String splashQuote;

  /// Small print under the Continue button.
  final String phoneConsent;
  final String phoneTitle;
  final String phoneSubtitle;
  final String phoneLabel;
  final String invalidPhone;
  final String continueLabel;
  final String otpTitle;
  final String Function(String phone) otpSubtitle;
  final String Function(String remaining) resendIn;
  final String resend;
  final String codeResent;
  final String changeNumber;
  final String retry;
  final String networkError;
  final String genericError;

  /// Message to show for an error thrown by an API call: the server's
  /// `error.message` (SPEC §7), or a localised fallback.
  String errorMessage(Object error) => switch (error) {
        ApiException e when e.isNetwork => networkError,
        ApiException e => e.displayMessage,
        _ => genericError,
      };
}
