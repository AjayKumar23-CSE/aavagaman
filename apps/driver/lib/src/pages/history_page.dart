import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../earnings/earnings_providers.dart';
import 'earnings_page.dart';

/// Trip history (SPEC §12 drawer): every ride this driver was assigned,
/// newest first, with status and amount.
class DriverHistoryPage extends ConsumerWidget {
  const DriverHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(driverHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: switch (async) {
        AsyncData(:final value) when value.rides.isEmpty => EmptyState(
          icon: Icons.route_rounded,
          title: l10n.historyEmpty,
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: ref.read(driverHistoryProvider.notifier).reload,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: value.rides.length + 1,
            itemBuilder: (context, i) {
              if (i < value.rides.length) return _HistoryTile(ride: value.rides[i]);
              if (value.error != null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(
                    message: errorText(value.error!, l10n),
                    retryLabel: l10n.retry,
                    onRetry: ref.read(driverHistoryProvider.notifier).loadMore,
                  ),
                );
              }
              if (!value.hasMore) return const SizedBox(height: 24);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: value.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton(
                        key: const Key('history-more'),
                        onPressed: ref.read(driverHistoryProvider.notifier).loadMore,
                        child: Text(l10n.historyLoadMore),
                      ),
              );
            },
          ),
        ),
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorBanner(
            message: errorText(error, l10n),
            retryLabel: l10n.retry,
            onRetry: () => ref.invalidate(driverHistoryProvider),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final (status, color, icon) = switch (ride.status) {
      RideStatus.paid => (l10n.historyStatusPaid, colors.success, Icons.check_rounded),
      RideStatus.completed => (l10n.historyStatusCompleted, colors.accent, Icons.hourglass_bottom_rounded),
      RideStatus.cancelled => (
        switch (ride.cancelledBy) {
          CancelActor.driver => l10n.historyCancelledByYou,
          CancelActor.rider => l10n.historyCancelledByRider,
          CancelActor.admin => l10n.historyCancelledByAdmin,
          _ => l10n.historyStatusCancelled,
        },
        scheme.error,
        Icons.close_rounded,
      ),
      _ => (l10n.historyStatusActive, scheme.primary, Icons.directions_car_rounded),
    };
    final amount = ride.earning?.net ?? ride.finalFare;
    final at = ride.lastEventAt;
    return SoftCard(
      key: Key('history-${ride.id}'),
      shadow: false,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ride.drop.address, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [ride.pickup.address.split(',').first, if (at != null) formatTripTime(at)].join(' · '),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                StatusPill(label: status, color: color),
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 8),
            Text(
              formatAmount(amount),
              style: text.titleMedium?.copyWith(
                color: ride.status == RideStatus.cancelled ? scheme.onSurfaceVariant : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
