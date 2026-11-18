import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

/// Which of the two fields the search results fill.
enum _Field { pickup, drop }

/// Plan your ride (SPEC §11 "Set drop"), laid out like Ola/Uber: the pickup
/// field starts on the rider's current location and follows the GPS until
/// the rider picks another place; the drop field has the focus. Places
/// Autocomplete with a 400 ms debounce and a 3-character minimum, recent
/// places, and "Set location on map" work for whichever field is active.
/// Without a Places key the rider types an address and pins it.
class SetDropPage extends ConsumerStatefulWidget {
  const SetDropPage({super.key});

  static const debounce = Duration(milliseconds: 400);
  static const minChars = 3;

  @override
  ConsumerState<SetDropPage> createState() => _SetDropPageState();
}

class _SetDropPageState extends ConsumerState<SetDropPage> {
  final _pickupQuery = TextEditingController();
  final _dropQuery = TextEditingController();
  final _pickupFocus = FocusNode();
  final _dropFocus = FocusNode();
  var _sessionToken = newPlacesSessionToken();
  var _field = _Field.drop;

  /// The pickup is the GPS position (set on Home) and moves with new fixes
  /// until the rider chooses something else.
  bool _pickupFromGps = true;

  /// Home's recent-place chip without a fix: the drop is set, only the
  /// pickup is missing, so choosing one goes straight to Confirm.
  bool _dropPreset = false;
  bool _initialised = false;
  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  bool _resolving = false;
  String? _error;
  int _request = 0;

  TextEditingController get _query => _field == _Field.pickup ? _pickupQuery : _dropQuery;

  @override
  void initState() {
    super.initState();
    _pickupFocus.addListener(() => _onFocus(_Field.pickup, _pickupFocus));
    _dropFocus.addListener(() => _onFocus(_Field.drop, _dropFocus));
    // A fix may already be in while Home had none.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _followGps(ref.read(myLocationProvider).value?.point);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final draft = ref.read(bookingDraftProvider);
    // Home only sets a pickup from a real fix, so a pickup here is either the
    // GPS one or one the rider chose earlier (e.g. on Confirm).
    final pickup = draft.pickup;
    _pickupFromGps = pickup == null || pickup.address == AppLocalizations.of(context).homeCurrentLocation;
    _pickupQuery.text = pickup?.address ?? '';
    _dropPreset = draft.drop != null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupQuery.dispose();
    _dropQuery.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  /// Moves a GPS pickup to [point]; leaves a chosen pickup alone.
  void _followGps(GeoPoint? point) {
    if (!_pickupFromGps || point == null) return;
    final place = RidePlace(lat: point.lat, lng: point.lng, address: AppLocalizations.of(context).homeCurrentLocation);
    ref.read(bookingDraftProvider.notifier).setPickup(place);
    if (!_pickupFocus.hasFocus) _pickupQuery.text = place.address;
  }

  void _onFocus(_Field field, FocusNode node) {
    if (node.hasFocus) {
      _debounce?.cancel();
      setState(() {
        _field = field;
        _results = const [];
        _searching = false;
        // _error stays: "Set your pickup location first." moves the focus here.
      });
      if (field == _Field.pickup) {
        // Typing replaces the shown address.
        _pickupQuery.selection = TextSelection(baseOffset: 0, extentOffset: _pickupQuery.text.length);
      }
    } else if (field == _Field.pickup) {
      // Leaving the field without choosing keeps the current pickup.
      _pickupQuery.text = ref.read(bookingDraftProvider).pickup?.address ?? '';
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final places = ref.read(placesApiProvider);
    final q = value.trim();
    if (!places.isAvailable || q.length < SetDropPage.minChars) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(SetDropPage.debounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_request;
    try {
      final results = await ref.read(placesApiProvider).autocomplete(q, sessionToken: _sessionToken);
      if (!mounted || id != _request) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _searching = false;
        _error = AppLocalizations.of(context).common.errorMessage(e);
      });
    }
  }

  Future<void> _pick(PlaceSuggestion s) async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final d = await ref.read(placesApiProvider).details(s.placeId, sessionToken: _sessionToken);
      // Details ends the Places session; the other field starts a new one.
      _sessionToken = newPlacesSessionToken();
      if (!mounted) return;
      setState(() => _resolving = false);
      _choose(RidePlace(lat: d.lat, lng: d.lng, address: d.address.isEmpty ? s.fullText : d.address));
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = AppLocalizations.of(context).common.errorMessage(e);
        });
      }
    }
  }

  void _choose(RidePlace place) => _field == _Field.pickup ? _choosePickup(place) : _chooseDrop(place);

  void _choosePickup(RidePlace place, {bool fromGps = false}) {
    _pickupFromGps = fromGps;
    ref.read(bookingDraftProvider.notifier).setPickup(place);
    if (!fromGps) ref.read(recentPlacesProvider.notifier).add(place);
    _pickupQuery.text = place.address;
    setState(() {
      _results = const [];
      _error = null;
    });
    // Pickup done: on to the drop (or Confirm, when the drop came from Home).
    if (_dropPreset && ref.read(bookingDraftProvider).drop != null && _dropQuery.text.trim().isEmpty) {
      _toConfirm();
    } else {
      _dropFocus.requestFocus();
    }
  }

  void _chooseDrop(RidePlace place) {
    ref.read(bookingDraftProvider.notifier).setDrop(place);
    ref.read(recentPlacesProvider.notifier).add(place);
    if (ref.read(bookingDraftProvider).pickup == null) {
      _askForPickup();
      return;
    }
    _toConfirm();
  }

  void _toConfirm() {
    if (mounted) context.pushReplacement(Routes.confirm);
  }

  void _askForPickup() {
    setState(() => _error = AppLocalizations.of(context).searchPickupNeeded);
    _pickupFocus.requestFocus();
  }

  void _useCurrentLocation(GeoPoint point) => _choosePickup(
    RidePlace(lat: point.lat, lng: point.lng, address: AppLocalizations.of(context).homeCurrentLocation),
    fromGps: true,
  );

  Future<void> _setOnMap() async {
    final typed = _query.text.trim();
    if (_field == _Field.drop) {
      // The map picker goes straight on to Confirm, which needs a pickup.
      if (ref.read(bookingDraftProvider).pickup == null) {
        _askForPickup();
        return;
      }
      context.push(Routes.pickFor('drop', address: typed.isEmpty ? null : typed));
      return;
    }
    final before = ref.read(bookingDraftProvider).pickup;
    final pinnedTyped = typed.isEmpty || typed == before?.address ? null : typed;
    await context.push(Routes.pickFor('pickup', address: pinnedTyped));
    if (!mounted) return;
    final after = ref.read(bookingDraftProvider).pickup;
    if (after != null && after != before) {
      _choosePickup(after);
    } else {
      _pickupQuery.text = before?.address ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final places = ref.watch(placesApiProvider);
    final recents = ref.watch(recentPlacesProvider);
    final location = ref.watch(myLocationProvider);
    final pickup = ref.watch(bookingDraftProvider.select((d) => d.pickup));
    ref.listen(myLocationProvider, (_, next) => _followGps(next.value?.point));
    final q = _query.text.trim();
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final editingPickup = _field == _Field.pickup;
    final gps = location.value?.point;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                // Green pickup dot, line, red drop square, as on Confirm.
                Column(
                  children: [
                    Icon(Icons.circle, size: 12, color: colors.success),
                    Container(width: 2, height: 40, color: scheme.outlineVariant),
                    Icon(Icons.square_rounded, size: 12, color: scheme.error),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('pickup-field'),
                        controller: _pickupQuery,
                        focusNode: _pickupFocus,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: pickup == null && location.isLoading ? l10n.searchLocating : l10n.searchPickupHint,
                          isDense: true,
                        ),
                        onChanged: _onChanged,
                        onSubmitted: (_) {
                          if (!places.isAvailable && _pickupQuery.text.trim().isNotEmpty) _setOnMap();
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('search-field'),
                        controller: _dropQuery,
                        focusNode: _dropFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: l10n.searchHint,
                          isDense: true,
                          suffixIcon: _dropQuery.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _dropQuery.clear();
                                    _onChanged('');
                                  },
                                ),
                        ),
                        onChanged: _onChanged,
                        onSubmitted: (_) {
                          if (!places.isAvailable && _dropQuery.text.trim().isNotEmpty) _setOnMap();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!places.isAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.searchUnavailable, style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ErrorBanner(message: _error!),
            ),
          if (_searching || _resolving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (editingPickup && gps != null)
                  ListTile(
                    key: const Key('use-current-location'),
                    leading: Icon(Icons.my_location_rounded, color: scheme.primary),
                    title: Text(l10n.searchUseCurrentLocation),
                    onTap: _resolving ? null : () => _useCurrentLocation(gps),
                  ),
                ListTile(
                  key: const Key('set-on-map'),
                  leading: Icon(Icons.pin_drop_outlined, color: scheme.primary),
                  title: Text(
                    q.isNotEmpty && !places.isAvailable && !(editingPickup && q == pickup?.address)
                        ? l10n.searchUseTyped(q)
                        : l10n.searchSetOnMap,
                  ),
                  onTap: _resolving ? null : _setOnMap,
                ),
                if (places.isAvailable && q.isNotEmpty && q.length < SetDropPage.minChars)
                  ListTile(leading: const Icon(Icons.keyboard), title: Text(l10n.searchMinChars), enabled: false),
                if (places.isAvailable &&
                    q.length >= SetDropPage.minChars &&
                    !_searching &&
                    _results.isEmpty &&
                    _error == null)
                  ListTile(leading: const Icon(Icons.search_off), title: Text(l10n.searchNoResults), enabled: false),
                for (final s in _results)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(s.primaryText),
                    subtitle: s.secondaryText.isEmpty
                        ? null
                        : Text(s.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: _resolving ? null : () => _pick(s),
                  ),
                if ((q.isEmpty || (editingPickup && q == pickup?.address)) && recents.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(l10n.searchRecent, style: Theme.of(context).textTheme.labelLarge),
                  ),
                  for (final p in recents)
                    ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(p.address, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _choose(p),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
