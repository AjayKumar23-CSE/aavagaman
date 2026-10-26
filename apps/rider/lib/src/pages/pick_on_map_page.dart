import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';

/// "Set location on map": drag the map under a fixed pin, optionally name
/// the place, confirm. Used for the drop (default) or the pickup.
class PickOnMapPage extends ConsumerStatefulWidget {
  const PickOnMapPage({super.key, this.forPickup = false, this.initialAddress});

  final bool forPickup;
  final String? initialAddress;

  @override
  ConsumerState<PickOnMapPage> createState() => _PickOnMapPageState();
}

class _PickOnMapPageState extends ConsumerState<PickOnMapPage> {
  late final _address = TextEditingController(text: widget.initialAddress ?? '');
  GeoPoint? _centre;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  GeoPoint _start() {
    final draft = ref.read(bookingDraftProvider);
    final existing = widget.forPickup ? draft.pickup : draft.drop;
    if (existing != null) return GeoPoint(existing.lat, existing.lng);
    return ref.read(myLocationProvider).value?.pointOrDefault ?? MapConfig.connaughtPlace;
  }

  void _confirm(GeoPoint start) {
    final l10n = AppLocalizations.of(context);
    final p = _centre ?? start;
    final typed = _address.text.trim();
    final place = RidePlace(
      lat: p.lat,
      lng: p.lng,
      address: typed.isNotEmpty
          ? typed
          : l10n.pickPinnedAddress(p.lat.toStringAsFixed(5), p.lng.toStringAsFixed(5)),
    );
    final draft = ref.read(bookingDraftProvider.notifier);
    if (widget.forPickup) {
      draft.setPickup(place);
      context.pop();
    } else {
      draft.setDrop(place);
      ref.read(recentPlacesProvider.notifier).add(place);
      // Replace the search screen so Back from Confirm returns Home.
      context.pop();
      context.pushReplacement(Routes.confirm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final start = _start();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.forPickup ? l10n.pickTitlePickup : l10n.pickTitleDrop)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: RideMap(
                    spec: RideMapSpec(
                      center: start,
                      zoom: 16,
                      myLocation: true,
                      onCameraIdle: (c) => setState(() => _centre = c),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 36),
                      child: Icon(Icons.location_on,
                          size: 44, color: widget.forPickup ? Colors.green.shade700 : scheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.pickHint, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('pick-address'),
                    controller: _address,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 300,
                    decoration: InputDecoration(labelText: l10n.pickAddressLabel, counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(label: l10n.pickConfirm, onPressed: () => _confirm(start)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
