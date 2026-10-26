import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';

/// Full-screen list of open ride requests (SPEC §12, D-055): one card per
/// ride with pickup, drop, distance to pickup, fare range, its own countdown
/// ring to `expires_at`, and Accept / Reject.
class OfferPage extends ConsumerWidget {
  const OfferPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(offerProvider);
    final offers = state.offers;
    if (offers.isEmpty) return const Scaffold(body: SizedBox.shrink()); // router leaves

    ref.listen(offerProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      ref.read(offerProvider.notifier).clearError();
    });

    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    const onDark = Colors.white;

    return Scaffold(
      backgroundColor: colors.ink,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.gradientEnd, colors.ink],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.offersTitle(offers.length),
                      key: const Key('offers-title'),
                      style: text.titleLarge?.copyWith(color: onDark),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: offers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final offer = offers[i];
                    return _OfferCard(
                      key: ValueKey('offer-${offer.rideId}'),
                      offer: offer,
                      accepting: state.acceptingId == offer.rideId,
                      enabled: !state.accepting,
                      onAccept: () async {
                        final ride = await ref.read(offerProvider.notifier).accept(offer.rideId);
                        if (ride != null && context.mounted) context.go(Routes.trip);
                      },
                      onReject: () => ref.read(offerProvider.notifier).reject(offer.rideId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  const _OfferCard({
    super.key,
    required this.offer,
    required this.accepting,
    required this.enabled,
    required this.onAccept,
    required this.onReject,
  });

  final RideOffer offer;
  final bool accepting;
  final bool enabled;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  late int _total;
  late int _left;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Count down from the offer's own expiry; afterwards the ring is driven by ticks.
    _left = widget.offer.remaining().inSeconds;
    _total = max(_left, 1);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left > 0) setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final offer = widget.offer;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final id = offer.rideId;

    return SoftCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RingProgress(
                value: _left / _total,
                size: 64,
                stroke: 6,
                color: colors.accent,
                track: colors.accent.withValues(alpha: 0.15),
                child: Text(
                  '$_left',
                  key: Key('offer-countdown-$id'),
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusPill(
                      icon: Icons.near_me_rounded,
                      label: l10n.offerDistance(
                        offer.distanceToPickupM == null ? '—' : formatDistance(offer.distanceToPickupM!),
                      ),
                      color: scheme.primary,
                    ),
                    StatusPill(
                      icon: Icons.currency_rupee_rounded,
                      label: l10n.offerFare(formatFareRange(offer.estFareMin, offer.estFareMax)),
                      color: colors.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RoutePoints(
            pickup: offer.pickup.address,
            drop: offer.dropAddress,
            pickupLabel: l10n.offerPickup,
            dropLabel: l10n.offerDrop,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: Key('offer-reject-$id'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: widget.enabled ? widget.onReject : null,
                  child: Text(l10n.offerReject),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: Key('offer-accept-$id'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: widget.enabled ? widget.onAccept : null,
                  icon: const Icon(Icons.check_rounded, size: 22),
                  label: Text(widget.accepting ? l10n.offerAccepting : l10n.offerAccept),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
