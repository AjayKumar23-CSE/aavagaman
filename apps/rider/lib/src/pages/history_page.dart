import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

/// Ride history (SPEC §11 drawer): `GET /rides` newest first, a page at a
/// time; tap a ride for its detail / receipt.
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(rideHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorBanner(
              message: l10n.historyLoadFailed,
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(rideHistoryProvider),
            ),
          ),
        ),
        data: (state) {
          if (state.rides.isEmpty) {
            return EmptyState(icon: Icons.route_rounded, title: l10n.historyTitle, body: l10n.historyEmpty);
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(rideHistoryProvider.notifier).reload(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.rides.length + (state.hasMore || state.error != null ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == state.rides.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: state.error != null
                        ? ErrorBanner(
                            message: l10n.historyLoadFailed,
                            retryLabel: l10n.retry,
                            onRetry: () => ref.read(rideHistoryProvider.notifier).loadMore(),
                          )
                        : state.loadingMore
                            ? const Center(child: CircularProgressIndicator())
                            : OutlinedButton(
                                key: const Key('history-load-more'),
                                onPressed: () => ref.read(rideHistoryProvider.notifier).loadMore(),
                                child: Text(l10n.historyLoadMore),
                              ),
                  );
                }
                return RideHistoryTile(ride: state.rides[i]);
              },
            ),
          );
        },
      ),
    );
  }
}

class RideHistoryTile extends StatelessWidget {
  const RideHistoryTile({super.key, required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final when = ride.lastEventAt;
    final amount = switch (ride.status) {
      RideStatus.completed || RideStatus.paid => ride.dueAmount,
      RideStatus.cancelled when (ride.cancellationFee ?? 0) > 0 => ride.cancellationFee,
      _ => null,
    };
    final (icon, color) = switch (ride.status) {
      RideStatus.paid => (Icons.check_rounded, colors.success),
      RideStatus.completed => (Icons.flag_rounded, scheme.primary),
      RideStatus.cancelled || RideStatus.noDriver => (Icons.close_rounded, scheme.error),
      _ => (Icons.directions_car_rounded, scheme.onSurfaceVariant),
    };
    return SoftCard(
      key: Key('history-${ride.id}'),
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      shadow: false,
      onTap: () => context.push(Routes.historyDetail(ride.id)),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        leading: IconBadge(icon: icon, color: color, size: 40),
        title: Text(ride.drop.address, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(when == null ? '' : formatDateTime(when)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (amount != null) Text(formatAmount(amount), style: text.titleMedium),
            const SizedBox(height: 4),
            StatusPill(label: l10n.rideStatusLabel(ride.status), color: color),
          ],
        ),
      ),
    );
  }
}
