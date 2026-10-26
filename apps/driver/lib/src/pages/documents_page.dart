import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../documents/upload_sheet.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

enum DocState { notUploaded, pending, approved, rejected, expired }

DocState docState(DriverProfile profile, DocType type) {
  final doc = profile.documentFor(type);
  if (doc == null) return DocState.notUploaded;
  if (doc.status == VerificationStatus.rejected) return DocState.rejected;
  final now = DateTime.now().toUtc();
  final expired =
      profile.expiredDocuments.contains(type) ||
      (doc.expiry != null && doc.expiry!.isBefore(DateTime.utc(now.year, now.month, now.day)));
  if (expired) return DocState.expired;
  return doc.status == VerificationStatus.approved ? DocState.approved : DocState.pending;
}

/// The 6 mandatory documents plus optional fitness certificate.
class DocumentsPage extends ConsumerWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(driverProfileProvider).value;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final remaining = profile.notUploaded.length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.documentsTitle)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: InfoBanner(message: l10n.documentsIntro, icon: Icons.verified_user_outlined),
            ),
            for (final type in DocType.values)
              DocumentTile(profile: profile, type: type, onTap: () => showDocumentUploadSheet(context, type)),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (remaining > 0)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l10n.documentsRemaining(remaining))),
              PrimaryButton(
                label: l10n.documentsContinue,
                onPressed: remaining > 0 ? null : () => context.go(gateFor(profile)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(driverProfileProvider.notifier).refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.common.errorMessage(e))));
    }
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.profile, required this.type, this.onTap});

  final DriverProfile profile;
  final DocType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final doc = profile.documentFor(type);
    final state = docState(profile, type);

    final (IconData icon, Color color, String label) = switch (state) {
      DocState.notUploaded => (Icons.upload_file_rounded, scheme.onSurfaceVariant, l10n.docStatusNotUploaded),
      DocState.pending => (Icons.hourglass_top_rounded, colors.accent, l10n.docStatusPending),
      DocState.approved => (Icons.check_rounded, colors.success, l10n.docStatusApproved),
      DocState.rejected => (Icons.close_rounded, scheme.error, l10n.docStatusRejected),
      DocState.expired => (Icons.event_busy_rounded, scheme.error, l10n.docStatusExpired),
    };

    return SoftCard(
      shadow: false,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.docType(type), style: text.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(label: label, color: color),
                    if (!type.mandatory) Text(l10n.docOptional, style: text.bodySmall),
                    if (doc?.expiry != null) Text(l10n.docExpires(formatDate(doc!.expiry!)), style: text.bodySmall),
                  ],
                ),
                if (state == DocState.rejected && doc?.reviewerNote != null) ...[
                  const SizedBox(height: 6),
                  Text(doc!.reviewerNote!, style: text.bodySmall?.copyWith(color: scheme.error)),
                ],
              ],
            ),
          ),
          if (onTap != null)
            TextButton(
              onPressed: onTap,
              child: Text(state == DocState.notUploaded ? l10n.docUpload : l10n.docReupload),
            ),
        ],
      ),
    );
  }
}
