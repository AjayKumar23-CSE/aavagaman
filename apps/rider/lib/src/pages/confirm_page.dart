import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

/// Confirm (SPEC §11): pickup/drop on the map, fare range, payment method
/// (Cash default / Pay online), out-of-area drop notice, Book.
class ConfirmPage extends ConsumerStatefulWidget {
  const ConfirmPage({super.key});

  @override
  ConsumerState<ConfirmPage> createState() => _ConfirmPageState();
}

class _ConfirmPageState extends ConsumerState<ConfirmPage> {
  bool _booking = false;
  String? _error;
  String? _notice;

  Future<void> _book(FareEstimate estimate) async {
    final l10n = AppLocalizations.of(context);
    final draft = ref.read(bookingDraftProvider);
    if (!draft.complete) return;
    setState(() {
      _booking = true;
      _error = null;
      _notice = null;
    });
    try {
      final option = estimate.option(draft.vehicleType);
      await ref
          .read(activeRideProvider.notifier)
          .book(
            pickup: draft.pickup!,
            drop: draft.drop!,
            fareConfigId: option.fareConfigId,
            vehicleType: option.vehicleType,
            paymentMethod: draft.payment,
          );
      // The router sends us to /ride as soon as the active ride is set.
      if (mounted) context.go(Routes.ride);
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'FARE_CONFIG_INVALID':
          ref.invalidate(fareEstimateProvider);
          setState(() => _notice = l10n.confirmFareChanged);
        case 'ACTIVE_RIDE_EXISTS':
          await ref.read(activeRideProvider.notifier).refresh();
          if (mounted) setState(() => _error = e.displayMessage);
        default:
          setState(() => _error = l10n.common.errorMessage(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = l10n.common.errorMessage(e));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(bookingDraftProvider);
    final estimate = ref.watch(fareEstimateProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pickup = draft.pickup;
    final drop = draft.drop;

    if (pickup == null || drop == null) {
      // Deep link without a draft: start over.
      return Scaffold(
        appBar: AppBar(title: Text(l10n.confirmTitle)),
        body: Center(
          child: FilledButton(onPressed: () => context.go(Routes.home), child: Text(l10n.backToHome)),
        ),
      );
    }

    final points = [GeoPoint(pickup.lat, pickup.lng), GeoPoint(drop.lat, drop.lng)];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.confirmTitle)),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: RideMap(
              spec: RideMapSpec(
                center: points.first,
                fitPoints: points,
                interactive: false,
                markers: [
                  MapMarkerSpec(id: 'pickup', point: points[0], kind: MapMarkerKind.pickup),
                  MapMarkerSpec(id: 'drop', point: points[1], kind: MapMarkerKind.drop),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                children: [
                  // Pickup and drop stay put; only the fares and payment scroll.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: RoutePoints(
                      pickup: pickup.address,
                      drop: drop.address,
                      pickupLabel: l10n.confirmPickup,
                      dropLabel: l10n.confirmDrop,
                      changeLabel: l10n.confirmChange,
                      onChangePickup: () => context.push(Routes.pickFor('pickup')),
                      onChangeDrop: () => context.push(Routes.search),
                    ),
                  ),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      children: [
                        estimate.when(
                          loading: () => SoftCard(
                            shadow: false,
                            child: Row(
                              children: [
                                const RouteLoader(size: 22, stroke: 2.5),
                                const SizedBox(width: 12),
                                Text(l10n.confirmEstimating, style: text.bodyLarge),
                              ],
                            ),
                          ),
                          error: (e, _) => ErrorBanner(
                            message: l10n.common.errorMessage(e),
                            retryLabel: l10n.retry,
                            onRetry: () => ref.invalidate(fareEstimateProvider),
                          ),
                          data: (est) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  l10n.confirmTripMeta(formatDistance(est.distanceM), formatMinutes(est.durationS)),
                                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                              for (final opt in est.options) ...[
                                _VehicleOption(
                                  option: opt,
                                  selected: opt.vehicleType == est.option(draft.vehicleType).vehicleType,
                                  label: vehicleLabel(l10n, opt.vehicleType),
                                  seats: l10n.vehicleSeats(opt.seats),
                                  onTap: _booking
                                      ? null
                                      : () => ref.read(bookingDraftProvider.notifier).setVehicleType(opt.vehicleType),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (!est.dropInArea) ...[
                                const SizedBox(height: 12),
                                KeyedSubtree(
                                  key: const Key('out-of-area'),
                                  child: InfoBanner(message: l10n.confirmOutOfArea, tone: BannerTone.warning),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionTitle(l10n.confirmPayment),
                        SegmentedButton<PaymentMethod>(
                          segments: [
                            ButtonSegment(
                              value: PaymentMethod.cash,
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(l10n.confirmPayCash),
                            ),
                            ButtonSegment(
                              value: PaymentMethod.online,
                              icon: const Icon(Icons.qr_code_2_rounded),
                              label: Text(l10n.confirmPayOnline),
                            ),
                          ],
                          selected: {draft.payment},
                          onSelectionChanged: _booking
                              ? null
                              : (s) => ref.read(bookingDraftProvider.notifier).setPayment(s.first),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // The Book button stays put; only the sheet above it scrolls.
      bottomNavigationBar: Material(
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_notice != null) ...[
                  InfoBanner(message: _notice!, tone: BannerTone.info),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[ErrorBanner(message: _error!), const SizedBox(height: 12)],
                PrimaryButton(
                  label: l10n.confirmBook,
                  loading: _booking,
                  onPressed: estimate.hasValue && !estimate.isLoading ? () => _book(estimate.value!) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vehicle class names (D-056).
String vehicleLabel(AppLocalizations l10n, VehicleType t) => switch (t) {
  VehicleType.bike => l10n.vehicleBike,
  VehicleType.auto => l10n.vehicleAuto,
  VehicleType.mini => l10n.vehicleMini,
  VehicleType.sedan => l10n.vehicleSedan,
};

/// One selectable vehicle class with its fare range.
class _VehicleOption extends StatelessWidget {
  const _VehicleOption({
    required this.option,
    required this.selected,
    required this.label,
    required this.seats,
    required this.onTap,
  });

  final FareOption option;
  final bool selected;
  final String label;
  final String seats;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: SoftCard(
        key: Key('vehicle-${option.vehicleType.wire}'),
        onTap: onTap,
        borderColor: selected ? scheme.primary : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconBadge(icon: option.vehicleType.icon, size: 44, color: selected ? scheme.primary : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(seats, style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatFareRange(option.fareMin, option.fareMax),
              key: selected ? const Key('fare-range') : null,
              style: (selected ? text.titleLarge : text.titleMedium)?.copyWith(
                color: selected ? colors.onAccentContainer : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
