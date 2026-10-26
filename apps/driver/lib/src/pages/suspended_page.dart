import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../strings.dart';
import '../widgets.dart';

/// `verification_status == suspended` (SPEC §14 "Account paused, contact support").
class SuspendedPage extends ConsumerStatefulWidget {
  const SuspendedPage({super.key});

  @override
  ConsumerState<SuspendedPage> createState() => _SuspendedPageState();
}

class _SuspendedPageState extends ConsumerState<SuspendedPage> {
  bool _loading = false;

  Future<void> _check() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _loading = true);
    try {
      await ref.read(driverProfileProvider.notifier).refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.common.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final note = ref.watch(driverProfileProvider).value?.reviewerNote;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.suspendedTitle), actions: const [LogoutButton()]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: IconBadge(icon: Icons.pause_rounded, size: 88, color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 20),
          Text(l10n.suspendedHeadline, style: text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.suspendedBody, textAlign: TextAlign.center, style: text.bodyMedium),
          if (note != null) ...[const SizedBox(height: 16), NoteBanner(text: l10n.reviewerNoteLabel(note))],
          const SizedBox(height: 20),
          SoftCard(
            shadow: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                ListTile(
                  leading: const IconBadge(icon: Icons.phone_rounded, size: 36),
                  title: Text(l10n.helpPhoneLabel),
                  subtitle: SelectableText(l10n.helpPhone),
                ),
                ListTile(
                  leading: const IconBadge(icon: Icons.email_rounded, size: 36),
                  title: Text(l10n.helpEmailLabel),
                  subtitle: SelectableText(l10n.helpEmail),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l10n.checkAgain, loading: _loading, onPressed: _check),
        ],
      ),
    );
  }
}
