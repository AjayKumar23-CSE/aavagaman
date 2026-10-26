import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fixed-length numeric code entry drawn as one box per digit. A single
/// (transparent) text field keeps paste and SMS autofill working.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.onCompleted,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.hasError = false,
    this.controller,
    this.onChanged,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;

  /// Outlines the boxes in the error colour.
  final bool hasError;
  final TextEditingController? controller;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _changed(String value) {
    widget.onChanged?.call(value);
    if (value.length == widget.length) widget.onCompleted(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _controller.text;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < widget.length; i++)
              _Box(
                digit: i < text.length ? text[i] : '',
                active: _focus.hasFocus && i == text.length.clamp(0, widget.length - 1),
                error: widget.hasError,
                scheme: scheme,
              ),
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              key: const Key('otp-field'),
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              showCursor: false,
              enableInteractiveSelection: false,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
              onChanged: _changed,
            ),
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.digit, required this.active, required this.error, required this.scheme});

  final String digit;
  final bool active;
  final bool error;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final border = error
        ? scheme.error
        : active
            ? scheme.primary
            : Colors.transparent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 48,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: border, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        digit,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// "Resend code in 0:30" countdown that turns into a resend button.
class ResendCountdown extends StatefulWidget {
  const ResendCountdown({
    super.key,
    required this.onResend,
    required this.waitingLabel,
    required this.resendLabel,
    this.seconds = 30,
  });

  /// Called on tap; the countdown restarts when the future completes
  /// (successfully or not), so a failed resend cannot be spammed. Errors are
  /// the caller's to display; this widget only swallows them.
  final Future<void> Function() onResend;

  /// Builds the label while waiting, e.g. `(s) => 'Resend code in $s'`.
  final String Function(String remaining) waitingLabel;
  final String resendLabel;
  final int seconds;

  @override
  State<ResendCountdown> createState() => _ResendCountdownState();
}

class _ResendCountdownState extends State<ResendCountdown> {
  Timer? _timer;
  late int _remaining;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await widget.onResend();
    } catch (_) {
      // Shown by the caller (e.g. an ErrorBanner); just restart the timer.
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _start();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining > 0) {
      final m = _remaining ~/ 60;
      final s = (_remaining % 60).toString().padLeft(2, '0');
      return TextButton(onPressed: null, child: Text(widget.waitingLabel('$m:$s')));
    }
    return TextButton(
      onPressed: _sending ? null : _resend,
      child: Text(widget.resendLabel),
    );
  }
}
