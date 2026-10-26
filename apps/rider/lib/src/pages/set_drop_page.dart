import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

/// Set drop (SPEC §11): Places Autocomplete with a 400 ms debounce and a
/// 3-character minimum, recent places, and "Set location on map". Works
/// without a Places key by letting the rider type an address and pin it.
class SetDropPage extends ConsumerStatefulWidget {
  const SetDropPage({super.key});

  static const debounce = Duration(milliseconds: 400);
  static const minChars = 3;

  @override
  ConsumerState<SetDropPage> createState() => _SetDropPageState();
}

class _SetDropPageState extends ConsumerState<SetDropPage> {
  final _query = TextEditingController();
  final _sessionToken = newPlacesSessionToken();
  Timer? _debounce;
  List<PlaceSuggestion> _results = const [];
  bool _searching = false;
  bool _resolving = false;
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
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

  void _choose(RidePlace place) {
    ref.read(bookingDraftProvider.notifier).setDrop(place);
    ref.read(recentPlacesProvider.notifier).add(place);
    if (mounted) context.pushReplacement(Routes.confirm);
  }

  void _setOnMap() {
    final typed = _query.text.trim();
    context.push(Routes.pickFor('drop', address: typed.isEmpty ? null : typed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final places = ref.watch(placesApiProvider);
    final recents = ref.watch(recentPlacesProvider);
    final q = _query.text.trim();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('search-field'),
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _query.clear();
                          _onChanged('');
                        },
                      ),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) {
                if (!places.isAvailable && q.isNotEmpty) _setOnMap();
              },
            ),
          ),
          if (!places.isAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.searchUnavailable, style: Theme.of(context).textTheme.bodySmall),
                  ),
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
                ListTile(
                  key: const Key('set-on-map'),
                  leading: Icon(Icons.pin_drop_outlined, color: scheme.primary),
                  title: Text(
                    q.isNotEmpty && !places.isAvailable ? l10n.searchUseTyped(q) : l10n.searchSetOnMap,
                  ),
                  onTap: _resolving ? null : _setOnMap,
                ),
                if (places.isAvailable && q.isNotEmpty && q.length < SetDropPage.minChars)
                  ListTile(
                    leading: const Icon(Icons.keyboard),
                    title: Text(l10n.searchMinChars),
                    enabled: false,
                  ),
                if (places.isAvailable && q.length >= SetDropPage.minChars && !_searching && _results.isEmpty && _error == null)
                  ListTile(leading: const Icon(Icons.search_off), title: Text(l10n.searchNoResults), enabled: false),
                for (final s in _results)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(s.primaryText),
                    subtitle: s.secondaryText.isEmpty ? null : Text(s.secondaryText, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: _resolving ? null : () => _pick(s),
                  ),
                if (q.isEmpty && recents.isNotEmpty) ...[
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
