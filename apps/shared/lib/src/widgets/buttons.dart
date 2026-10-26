import 'package:flutter/material.dart';

import 'design.dart';

/// Full-width filled button that shows a spinner and ignores taps while
/// [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// Background override (e.g. success green for "Accept").
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = color == null ? null : FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white);
    final child = loading
        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Text(label);
    if (icon == null || loading) {
      return FilledButton(onPressed: loading ? null : onPressed, style: style, child: child);
    }
    return FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon), label: child);
  }
}

/// Inline error message with an optional retry action.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: InfoBanner(
        message: message,
        tone: BannerTone.error,
        action: onRetry != null && retryLabel != null
            ? TextButton(onPressed: onRetry, child: Text(retryLabel!))
            : null,
      ),
    );
  }
}
