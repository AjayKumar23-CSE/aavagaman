import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/auth_api.dart';
import '../providers.dart';
import '../session/session.dart';
import '../util/phone.dart';
import '../widgets/buttons.dart';
import '../widgets/brand.dart';
import '../widgets/otp_input.dart';
import '../widgets/phone_field.dart';
import 'auth_scaffold.dart';
import 'common_strings.dart';

/// Restores the session from secure storage. Routing away from here is done
/// by the app's router redirect once the session state is known.
/// How long the splash stays up even when the session restores instantly,
/// so the brand screen is actually seen. Tests override it to zero.
final splashHoldProvider = Provider<Duration>((_) => const Duration(milliseconds: 1200));

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key, required this.strings, this.error, this.onRetry});

  final CommonStrings strings;

  /// An app-specific error to show instead of the spinner (e.g. the driver
  /// profile failed to load after login).
  final Object? error;
  final VoidCallback? onRetry;

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  Object? _restoreError;
  bool _held = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Future<void> _restore() async {
    if (ref.read(sessionProvider) is! SessionUnknown) return;
    setState(() => _restoreError = null);
    try {
      if (!_held) {
        await Future<void>.delayed(ref.read(splashHoldProvider));
        _held = true;
        if (!mounted) return;
      }
      await ref.read(sessionProvider.notifier).restore();
    } catch (e) {
      if (mounted) setState(() => _restoreError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _restoreError ?? widget.error;
    final retry = _restoreError != null ? _restore : widget.onRetry;
    return Scaffold(
      backgroundColor: Brand.charcoal,
      body: SplashArt(
        appName: widget.strings.appName,
        tagline: widget.strings.tagline,
        quote: widget.strings.splashQuote,
        footer: error == null
            ? RouteLoader(size: 40, stroke: 4, color: Brand.mint, track: Colors.white.withValues(alpha: 0.12))
            : Material(
                color: Colors.transparent,
                child: ErrorBanner(
                  message: widget.strings.errorMessage(error),
                  retryLabel: widget.strings.retry,
                  onRetry: retry,
                ),
              ),
      ),
    );
  }
}

/// Phone number entry → `POST /auth/otp/send`.
class PhonePage extends ConsumerStatefulWidget {
  const PhonePage({
    super.key,
    required this.strings,
    required this.role,
    required this.onCodeSent,
  });

  final CommonStrings strings;
  final LoginRole role;

  /// Receives the E.164 phone; typically pushes the OTP route.
  final void Function(BuildContext context, String phone) onCodeSent;

  @override
  ConsumerState<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends ConsumerState<PhonePage> {
  final _controller = TextEditingController();
  String? _fieldError;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = widget.strings;
    final phone = IndianPhone.normalize(_controller.text);
    if (phone == null) {
      setState(() => _fieldError = s.invalidPhone);
      return;
    }
    setState(() {
      _fieldError = null;
      _error = null;
      _loading = true;
    });
    try {
      await ref.read(authApiProvider).sendOtp(phone: phone, role: widget.role);
      if (mounted) widget.onCodeSent(context, phone);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => e.code == 'INVALID_PHONE' ? _fieldError = e.message : _error = s.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.strings;
    return AuthScaffold(
      appName: s.appName,
      tagline: s.tagline,
      title: s.phoneTitle,
      subtitle: s.phoneSubtitle,
      children: [
        PhoneField(
          controller: _controller,
          label: s.phoneLabel,
          errorText: _fieldError,
          enabled: !_loading,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 24),
        PrimaryButton(label: s.continueLabel, loading: _loading, onPressed: _submit),
        const SizedBox(height: 16),
        Text(s.phoneConsent, style: t.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// 6-digit code entry → `SessionController.verifyOtp`. On success the
/// session changes and the router moves on.
class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({
    super.key,
    required this.strings,
    required this.role,
    required this.phone,
    this.resendAfter = 30,
  });

  final CommonStrings strings;
  final LoginRole role;

  /// E.164.
  final String phone;
  final int resendAfter;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _code = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    if (_loading) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .verifyOtp(phone: widget.phone, code: code, role: widget.role);
    } catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = widget.strings.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(authApiProvider).sendOtp(phone: widget.phone, role: widget.role);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.strings.codeResent)));
    } catch (e) {
      // 429 OTP_RATE_LIMITED lands here with the server's message.
      if (mounted) setState(() => _error = widget.strings.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AuthScaffold(
      appName: s.appName,
      tagline: s.tagline,
      title: s.otpTitle,
      subtitle: s.otpSubtitle(IndianPhone.format(widget.phone)),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).maybePop(),
            child: Text(s.changeNumber),
          ),
          ResendCountdown(
            seconds: widget.resendAfter,
            onResend: _resend,
            waitingLabel: s.resendIn,
            resendLabel: s.resend,
          ),
        ],
      ),
      children: [
        OtpInput(
          controller: _code,
          enabled: !_loading,
          hasError: _error != null,
          onCompleted: _verify,
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 24),
        if (_loading)
          const Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))),
      ],
    );
  }
}
