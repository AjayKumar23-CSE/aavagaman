import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../widgets.dart';
import 'documents_page.dart';

/// Keeps `GET /driver/me` fresh: every [interval] and whenever the app
/// returns to the foreground. When the driver is approved the router
/// redirect moves on to Home.
mixin ProfilePolling<T extends ConsumerStatefulWidget> on ConsumerState<T>, WidgetsBindingObserver {
  static const interval = Duration(seconds: 15);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(interval, (_) => _quietRefresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _quietRefresh();
  }

  Future<void> _quietRefresh() async {
    try {
      await ref.read(driverProfileProvider.notifier).refresh();
    } catch (_) {
      // Background poll: stay quiet, the next tick or a pull retries.
    }
  }
}

/// Pending approval: status, reviewer note, rejected documents with notes.
class PendingPage extends ConsumerStatefulWidget {
  const PendingPage({super.key});

  @override
  ConsumerState<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends ConsumerState<PendingPage> with WidgetsBindingObserver, ProfilePolling<PendingPage> {
  Future<void> _pullRefresh() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(driverProfileProvider.notifier).refresh();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.pendingRefreshFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(driverProfileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final attention = [
      for (final t in DocType.values)
        if (profile.missingDocuments.contains(t) ||
            profile.expiredDocuments.contains(t) ||
            profile.documentFor(t)?.status == VerificationStatus.rejected)
          t,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pendingTitle)),
      drawer: const DriverDrawer(),
      body: RefreshIndicator(
        onRefresh: _pullRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.of(context).gradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              ),
              child: Column(
                children: [
                  const IconBadge(icon: Icons.hourglass_top_rounded, color: Colors.white, size: 60),
                  const SizedBox(height: 14),
                  Text(
                    l10n.pendingHeadline,
                    style: text.headlineSmall?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.pendingBody,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            if (profile.reviewerNote != null) ...[
              const SizedBox(height: 16),
              NoteBanner(text: l10n.reviewerNoteLabel(profile.reviewerNote!)),
            ],
            if (attention.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionTitle(l10n.pendingNeedsAttention),
              for (final t in attention)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  child: DocumentTile(profile: profile, type: t),
                ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => context.push(Routes.documents),
                child: Text(l10n.pendingFixDocuments),
              ),
            ],
            const SizedBox(height: 24),
            SectionTitle(l10n.pendingAllDocuments),
            for (final t in DocType.values)
              if (!attention.contains(t) && profile.documentFor(t) != null) DocumentTile(profile: profile, type: t),
          ],
        ),
      ),
    );
  }
}
