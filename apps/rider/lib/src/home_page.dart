import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'router.dart';
import 'strings.dart';

/// Home (SPEC §11): map centred on GPS (Connaught Place + prompt when
/// denied), nearby cars every 10 s, "Where to?" entry.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  GeoPoint? _mapCentre;
  int _recenter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // SPEC §11: on resume always re-check the active ride (and the GPS fix,
    // in case permission was just granted in Settings).
    if (state == AppLifecycleState.resumed) {
      ref.read(activeRideProvider.notifier).refresh();
      ref.invalidate(myLocationProvider);
    }
  }

  void _whereTo(GeoPoint here) {
    final l10n = AppLocalizations.of(context);
    ref.read(bookingDraftProvider.notifier).setPickup(
          RidePlace(lat: here.lat, lng: here.lng, address: l10n.homeCurrentLocation),
        );
    context.push(Routes.search);
  }

  /// A recent place: current location → there, straight to Confirm.
  void _goTo(GeoPoint here, RidePlace drop) {
    final l10n = AppLocalizations.of(context);
    ref.read(bookingDraftProvider.notifier)
      ..setPickup(RidePlace(lat: here.lat, lng: here.lng, address: l10n.homeCurrentLocation))
      ..setDrop(drop);
    ref.read(recentPlacesProvider.notifier).add(drop);
    context.push(Routes.confirm);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = ref.watch(myLocationProvider);
    ref.listen(myLocationProvider, (prev, next) {
      // First real fix: move the map from the fallback to the rider.
      if (prev?.value?.point == null && next.value?.point != null) {
        setState(() {
          _mapCentre = null;
          _recenter++;
        });
      }
    });
    final user = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user : null));
    final recents = ref.watch(recentPlacesProvider);
    final fix = location.value;
    final here = fix?.pointOrDefault ?? MapConfig.connaughtPlace;
    final centre = _mapCentre ?? here;
    final cars = ref.watch(nearbyDriversProvider(nearbyKey(centre))).value ?? const [];
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);

    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(
        children: [
          Positioned.fill(
            child: RideMap(
              spec: RideMapSpec(
                center: here,
                recenter: _recenter,
                myLocation: fix?.point != null,
                padding: const EdgeInsets.only(bottom: 240),
                onCameraIdle: (c) => setState(() => _mapCentre = c),
                markers: [
                  for (final car in cars)
                    MapMarkerSpec(
                      id: 'car-${car.driverId}',
                      point: GeoPoint(car.lat, car.lng),
                      kind: MapMarkerKind.car,
                      heading: car.heading,
                    ),
                ],
              ),
            ),
          ),
          // Floating controls instead of an app bar, so the map breathes.
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Builder(
                          builder: (context) => FloatingCircleButton(
                            icon: Icons.menu_rounded,
                            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                        const Spacer(),
                        FloatingCircleButton(
                          icon: Icons.my_location_rounded,
                          tooltip: l10n.homeCurrentLocation,
                          onPressed: () {
                            setState(() {
                              _mapCentre = null;
                              _recenter++;
                            });
                            ref.invalidate(myLocationProvider);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (fix != null && (fix.denied || fix.serviceOff))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _LocationPrompt(
                        onSettings: () => ref.read(locationSourceProvider).openSettings(),
                        onRetry: () => ref.invalidate(myLocationProvider),
                      ),
                    )
                  else if (fix != null && fix.unavailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Material(
                        color: Colors.transparent,
                        child: InfoBanner(
                          key: const Key('location-unavailable'),
                          message: l10n.homeLocationUnavailable,
                          tone: BannerTone.info,
                          icon: Icons.gps_not_fixed_rounded,
                          action: TextButton(
                            onPressed: () => ref.invalidate(myLocationProvider),
                            child: Text(l10n.retry),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SheetPanel(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user?.name != null ? l10n.homeGreeting(user!.name!) : l10n.appTitle,
                        style: text.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _CarsPill(count: cars.length),
                  ],
                ),
                const SizedBox(height: 14),
                Material(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('where-to'),
                    onTap: () => _whereTo(here),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          IconBadge(icon: Icons.search_rounded, size: 36, filled: true),
                          const SizedBox(width: 12),
                          Expanded(child: Text(l10n.homeWhereTo, style: text.titleMedium)),
                          Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recents.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => ActionChip(
                        avatar: Icon(Icons.history_rounded, size: 18, color: colors.ink),
                        label: Text(
                          recents[i].address.split(',').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () => _goTo(here, recents[i]),
                      ),
                    ),
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

/// "3 cars nearby" with a live dot.
class _CarsPill extends StatelessWidget {
  const _CarsPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return StatusPill(
      label: l10n.homeNearbyCars(count),
      color: count > 0 ? colors.success : scheme.onSurfaceVariant,
      icon: Icons.circle,
    );
  }
}

class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt({required this.onSettings, required this.onRetry});

  final VoidCallback onSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InfoBanner(
        message: l10n.homeLocationDenied,
        tone: BannerTone.warning,
        icon: Icons.location_off_rounded,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextButton(onPressed: onRetry, child: Text(l10n.homeAllowLocation)),
            TextButton(onPressed: onSettings, child: Text(l10n.homeOpenSettings)),
          ],
        ),
      ),
    );
  }
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user : null));
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    void open(String route) {
      Navigator.of(context).pop();
      context.push(route);
    }

    Widget item(IconData icon, String label, VoidCallback onTap, {Key? key, Color? color}) => ListTile(
          key: key,
          leading: Icon(icon, color: color ?? scheme.onSurface),
          title: Text(label, style: text.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.w600)),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        );

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: BoxDecoration(gradient: colors.gradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Row(
                  children: [
                    InitialsAvatar(name: user?.name, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? '', style: text.titleLarge?.copyWith(color: Colors.white),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(IndianPhone.format(user?.phone ?? ''),
                              style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          item(Icons.history_rounded, l10n.menuHistory, () => open(Routes.history), key: const Key('menu-history')),
          item(Icons.person_outline_rounded, l10n.menuProfile, () => open(Routes.profile)),
          item(Icons.support_agent_rounded, l10n.menuHelp, () => open(Routes.help)),
          item(Icons.privacy_tip_outlined, l10n.menuPrivacy, () => open(Routes.privacy)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Divider()),
          item(Icons.logout_rounded, l10n.menuLogout, () => _logout(context, ref)),
          item(Icons.delete_forever_rounded, l10n.menuDeleteAccount, () => _delete(context, ref), color: scheme.error),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(context, l10n.logoutConfirmTitle, l10n.logoutConfirmBody, l10n.menuLogout);
    if (ok) await ref.read(sessionProvider.notifier).logout();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      context,
      l10n.deleteConfirmTitle,
      l10n.deleteConfirmBody,
      l10n.deleteConfirmAction,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
    } catch (e) {
      // e.g. 409 ACTIVE_RIDE: the server explains why.
      messenger.showSnackBar(SnackBar(content: Text(l10n.common.errorMessage(e))));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String action,
      {bool destructive = false}) async {
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error)
                : null,
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
