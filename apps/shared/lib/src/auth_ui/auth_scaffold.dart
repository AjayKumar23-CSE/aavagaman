import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Layout for the login flow: brand gradient on top with the mark and app
/// name, a white rounded panel below with the step's title and content.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.appName,
    required this.title,
    required this.children,
    this.subtitle,
    this.tagline,
    this.footer,
  });

  final String appName;
  final String title;
  final String? subtitle;

  /// Short line under the app name on the gradient (e.g. "Delhi NCR").
  final String? tagline;
  final List<Widget> children;

  /// Pinned below the content (e.g. Change number / Resend).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: colors.gradientEnd,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: colors.gradient),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: canPop
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                              ),
                            )
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          const AavagamanMark(size: 52),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(appName, style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                              if (tagline != null)
                                Text(
                                  tagline!.toUpperCase(),
                                  style: t.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.75), letterSpacing: 2),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          children: [
                            Text(title, style: t.headlineMedium),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(subtitle!, style: t.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                            const SizedBox(height: 28),
                            ...children,
                          ],
                        ),
                      ),
                      if (footer != null)
                        Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), child: footer),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
