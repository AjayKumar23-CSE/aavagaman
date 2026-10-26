import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../earnings/earnings_providers.dart';

/// "12 Oct, 9:41 pm" in the device's zone (IST on drivers' phones).
String formatTripTime(DateTime at) => DateFormat('d MMM, h:mm a', 'en').format(at.toLocal());

String errorText(Object error, AppLocalizations l10n) =>
    error is ApiException && !error.isNetwork ? error.displayMessage : l10n.loadFailed;

/// Earnings (SPEC §12): today / week cards, then recent trips with fare,
/// commission and net.
class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(driverHistoryProvider);
    final paid = history.value?.rides.where((r) => r.earning != null).toList() ?? const <Ride>[];

    Future<void> refresh() async {
      ref.invalidate(driverEarningsProvider);
      await ref.read(driverHistoryProvider.notifier).reload();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.earningsTitle)),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _PeriodCard(period: EarningsPeriod.today),
            const SizedBox(height: 12),
            const _PeriodCard(period: EarningsPeriod.week),
            const SizedBox(height: 12),
            InfoBanner(message: l10n.earningsSettlementNote, icon: Icons.event_repeat_rounded),
            const SizedBox(height: 24),
            SectionTitle(l10n.earningsRecent),
            if (history.isLoading && history.value == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (history.hasError && history.value == null)
              ErrorBanner(
                message: errorText(history.error!, l10n),
                retryLabel: l10n.retry,
                onRetry: () => ref.invalidate(driverHistoryProvider),
              )
            else if (paid.isEmpty)
              EmptyState(icon: Icons.route_rounded, title: l10n.historyEmpty)
            else
              for (final r in paid) _TripEarningTile(ride: r),
          ],
        ),
      ),
    );
  }
}

class _PeriodCard extends ConsumerWidget {
  const _PeriodCard({required this.period});

  final EarningsPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final async = ref.watch(driverEarningsProvider(period));
    final title = period == EarningsPeriod.today ? l10n.earningsToday : l10n.earningsWeek;
    final hero = period == EarningsPeriod.today;
    final fg = hero ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final muted = hero ? Colors.white.withValues(alpha: 0.85) : Theme.of(context).colorScheme.onSurfaceVariant;

    Widget body = switch (async) {
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: text.titleMedium?.copyWith(color: fg)),
              ),
              StatusPill(
                label: l10n.earningsTrips(value.rides),
                color: hero ? Colors.white : colors.accent,
                icon: Icons.directions_car_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l10n.earningsNet, style: text.labelMedium?.copyWith(color: muted)),
          Text(
            formatAmount(value.net),
            key: Key('earnings-${period.name}-net'),
            style: text.displaySmall?.copyWith(color: fg),
          ),
          Divider(height: 24, color: hero ? Colors.white.withValues(alpha: 0.25) : null),
          _Line(l10n.earningsGross, value.gross, color: fg),
          _Line(l10n.earningsCommission, -value.commission, color: muted),
          _Line(l10n.earningsGst, -value.gst, color: muted),
          const SizedBox(height: 8),
          _Line(l10n.earningsCash, value.cashCollected, color: fg, icon: Icons.payments_rounded),
          _Line(l10n.earningsOnline, value.online, color: fg, icon: Icons.qr_code_2_rounded),
        ],
      ),
      AsyncError(:final error) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium?.copyWith(color: fg)),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: ErrorBanner(
              message: errorText(error, l10n),
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(driverEarningsProvider(period)),
            ),
          ),
        ],
      ),
      _ => Center(child: CircularProgressIndicator(color: hero ? Colors.white : null)),
    };

    return Container(
      key: Key('earnings-${period.name}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: hero ? colors.gradient : null,
        color: hero ? null : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: hero ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: hero ? colors.gradientEnd.withValues(alpha: 0.3) : colors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: body,
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.amount, {this.color, this.icon});

  final String label;
  final double amount;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 8)],
          Expanded(child: Text(label, style: style)),
          Text(formatAmount(amount), style: style?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TripEarningTile extends StatelessWidget {
  const _TripEarningTile({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final e = ride.earning!;
    final at = ride.paidAt ?? ride.completedAt ?? ride.lastEventAt;
    return SoftCard(
      shadow: false,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          IconBadge(icon: Icons.check_rounded, color: colors.success, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ride.drop.address, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (at != null) Text(formatTripTime(at), style: text.bodySmall),
                Text(
                  l10n.earningsTripLine(formatAmount(e.fare), formatAmount(e.commission), formatAmount(e.gst)),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatAmount(e.net), style: text.titleMedium),
        ],
      ),
    );
  }
}
