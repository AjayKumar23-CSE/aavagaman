import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../strings.dart';

/// Ride detail / receipt (SPEC §11): map, status timeline, fare breakdown
/// from `GET /rides/:id/receipt`, Rate when the trip was not rated yet.
class RideDetailPage extends ConsumerWidget {
  const RideDetailPage({super.key, required this.rideId});

  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ride = ref.watch(rideDetailProvider(rideId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailTitle)),
      body: ride.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorBanner(
              message: l10n.common.errorMessage(e),
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(rideDetailProvider(rideId)),
            ),
          ),
        ),
        data: (r) => _Detail(ride: r),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.ride});

  final Ride ride;

  Future<void> _rate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<_RateOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RateSheet(ride: ride),
    );
    if (result == null) return;
    ref.read(ratedRidesProvider.notifier).add(ride.id);
    messenger.showSnackBar(SnackBar(
      content: Text(result == _RateOutcome.rated ? l10n.rateThanks : l10n.detailAlreadyRated),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rated = ref.watch(ratedRidesProvider).contains(ride.id);
    final pickup = GeoPoint(ride.pickup.lat, ride.pickup.lng);
    final drop = GeoPoint(ride.drop.lat, ride.drop.lng);
    final driver = ride.driver;

    final timeline = <(String, DateTime?)>[
      (l10n.statusLabelRequested, ride.requestedAt),
      (l10n.statusLabelAccepted, ride.acceptedAt),
      (l10n.statusLabelArrived, ride.arrivedAt),
      (l10n.statusLabelStarted, ride.startedAt),
      (l10n.statusLabelCompleted, ride.completedAt),
      (l10n.statusLabelPaid, ride.paidAt),
      (l10n.statusLabelCancelled, ride.cancelledAt),
    ].where((e) => e.$2 != null).toList();

    return ListView(
      children: [
        SizedBox(
          height: 200,
          child: RideMap(
            spec: RideMapSpec(
              center: pickup,
              fitPoints: [pickup, drop],
              interactive: false,
              markers: [
                MapMarkerSpec(id: 'pickup', point: pickup, kind: MapMarkerKind.pickup),
                MapMarkerSpec(id: 'drop', point: drop, kind: MapMarkerKind.drop),
              ],
              polylines: [MapPolylineSpec(id: 'route', points: [pickup, drop], dashed: true)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ride.lastEventAt == null ? '' : formatDateTime(ride.lastEventAt!),
                  style: text.titleMedium,
                ),
              ),
              KeyedSubtree(
                key: const Key('detail-status'),
                child: StatusPill(
                  label: l10n.rideStatusLabel(ride.status),
                  color: switch (ride.status) {
                    RideStatus.paid => AppColors.of(context).success,
                    RideStatus.completed => scheme.primary,
                    RideStatus.cancelled || RideStatus.noDriver => scheme.error,
                    _ => scheme.onSurfaceVariant,
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SoftCard(
            shadow: false,
            child: RoutePoints(
              pickup: ride.pickup.address,
              drop: ride.drop.address,
              pickupLabel: l10n.confirmPickup,
              dropLabel: l10n.confirmDrop,
            ),
          ),
        ),
        if (driver != null)
          ListTile(
            leading: InitialsAvatar(name: driver.name, radius: 20),
            title: Text(driver.name ?? ''),
            subtitle: Text([
              if (driver.vehicle != null) driver.vehicle!.label,
              if (driver.vehicle != null) driver.vehicle!.regNumber,
            ].join(' · ')),
          ),
        if (ride.status == RideStatus.cancelled) ...[
          ListTile(
            leading: Icon(Icons.cancel_outlined, color: scheme.error),
            title: Text(ride.cancelledBy == null
                ? l10n.statusCancelledBody
                : l10n.detailCancelledBy(l10n.cancelActorLabel(ride.cancelledBy!))),
            subtitle: ride.cancelReason == null ? null : Text(l10n.statusCancelledReason(ride.cancelReason!)),
          ),
          if ((ride.cancellationFee ?? 0) > 0)
            ListTile(
              leading: const Icon(Icons.currency_rupee),
              title: Text(l10n.statusCancellationFee(formatAmount(ride.cancellationFee!))),
              subtitle: Text(l10n.detailFeeCarriedNote),
            ),
        ],
        if (ride.hasReceipt) _ReceiptCard(ride: ride),
        if (timeline.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(l10n.detailTimeline, style: text.titleMedium),
          ),
          for (final (label, at) in timeline)
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 10, color: scheme.primary),
              title: Text(label),
              trailing: Text(formatDateTime(at!), style: text.bodySmall),
            ),
        ],
        if (ride.isRateable)
          Padding(
            padding: const EdgeInsets.all(16),
            child: rated
                ? Text(l10n.detailAlreadyRated, textAlign: TextAlign.center, style: text.bodyMedium)
                : OutlinedButton.icon(
                    key: const Key('detail-rate'),
                    onPressed: () => _rate(context, ref),
                    icon: const Icon(Icons.star_outline_rounded),
                    label: Text(l10n.detailRate),
                  ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  const _ReceiptCard({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final receipt = ref.watch(receiptProvider(ride.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.detailReceipt, style: text.titleMedium),
              const SizedBox(height: 8),
              receipt.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
                error: (e, _) => ErrorBanner(
                  message: l10n.payReceiptFailed,
                  retryLabel: l10n.retry,
                  onRetry: () => ref.invalidate(receiptProvider(ride.id)),
                ),
                data: (r) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (r.distanceM != null && r.durationS != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(l10n.payTripStats(formatDistance(r.distanceM!), formatClock(r.durationS!)),
                            style: text.bodySmall),
                      ),
                    AmountRow(label: l10n.payFare, amount: formatAmount(r.fare)),
                    AmountRow(label: l10n.payFareInclGst(formatAmount(r.gst)), amount: '', muted: true),
                    if (r.hasCancellationFee)
                      AmountRow(label: l10n.payCancellationFee, amount: formatAmount(r.cancellationFee)),
                    const Divider(),
                    AmountRow(label: l10n.payTotal, amount: formatAmount(r.total), emphasis: true),
                    const SizedBox(height: 8),
                    Text(
                      r.isPaid
                          ? l10n.detailPaidWith(l10n.paidWithLabel(r.paidWith ?? r.paymentMethod.name))
                          : l10n.detailPaymentPending(l10n.paymentMethodLabel(r.paymentMethod)),
                      key: const Key('detail-payment'),
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RateOutcome { rated, alreadyRated }

class _RateSheet extends ConsumerStatefulWidget {
  const _RateSheet({required this.ride});

  final Ride ride;

  @override
  ConsumerState<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<_RateSheet> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(rideApiProvider).rate(widget.ride.id, stars: _stars, comment: _comment.text);
      if (mounted) Navigator.pop(context, _RateOutcome.rated);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_RATED') {
        Navigator.pop(context, _RateOutcome.alreadyRated);
        return;
      }
      setState(() {
        _sending = false;
        _error = l10n.common.errorMessage(e);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = l10n.common.errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.rateTitle, style: text.titleLarge, textAlign: TextAlign.center),
          if (widget.ride.driver?.name != null)
            Text(l10n.rateSubtitle(widget.ride.driver!.name!), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          StarRating(
            value: _stars,
            onChanged: _sending ? null : (n) => setState(() => _stars = n),
            semanticLabel: (n) => l10n.rateStars(n),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('rate-comment'),
            controller: _comment,
            enabled: !_sending,
            maxLines: 2,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: l10n.rateCommentLabel, counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            key: const Key('rate-submit'),
            label: l10n.rateSubmit,
            loading: _sending,
            onPressed: _stars == 0 ? null : _submit,
          ),
        ],
      ),
    );
  }
}
