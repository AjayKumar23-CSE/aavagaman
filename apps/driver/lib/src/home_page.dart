import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';

import '../l10n/app_localizations.dart';
import 'earnings/earnings_providers.dart';
import 'pages/pending_page.dart';
import 'presence/permissions.dart';
import 'providers.dart';
import 'router.dart';
import 'widgets.dart';

/// Home (SPEC §12): Online/Offline switch, status, today's earnings. Keeps polling the profile so a suspension or a document
/// problem shows up.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver, ProfilePolling<HomePage> {
  bool _resumed = false;

  /// Bumped by the locate button to move the map back to the driver.
  int _recenter = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resumed) return;
    _resumed = true;
    final l10n = AppLocalizations.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // An accept that failed while the offer popup was up lands here.
      _showOfferError(ref.read(offerProvider).error);
      // The foreground service may have outlived the UI: rejoin it.
      ref
          .read(presenceProvider.notifier)
          .resumeIfServiceRunning(
            notificationTitle: l10n.onlineNotificationTitle,
            notificationBody: l10n.onlineNotificationBody,
          );
    });
  }

  void _showOfferError(String? error) {
    if (error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    ref.read(offerProvider.notifier).clearError();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) ref.read(activeRideProvider.notifier).refresh();
  }

  Future<void> _toggle(bool on) async {
    final l10n = AppLocalizations.of(context);
    final presence = ref.read(presenceProvider.notifier);
    await presence.setOnline(
      on,
      notificationTitle: l10n.onlineNotificationTitle,
      notificationBody: l10n.onlineNotificationBody,
    );
    if (!mounted || !on || !ref.read(presenceProvider).isOnline) return;
    // One-time battery-optimisation guide after the first successful go-online.
    final seen = await ref.read(batteryGuideSeenProvider.future).catchError((_) => true);
    if (mounted && !seen) context.push(Routes.battery);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final presence = ref.watch(presenceProvider);
    final profile = ref.watch(driverProfileProvider).value;
    final ride = ref.watch(activeRideProvider).value;
    final today = ref.watch(driverEarningsProvider(EarningsPeriod.today)).value;
    final name = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.name : null)) ?? profile?.name;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    ref.listen(offerProvider.select((s) => s.error), (_, error) => _showOfferError(error));

    final (icon, title, hint) = switch (presence.phase) {
      PresencePhase.offline => (Icons.power_settings_new, l10n.homeStatusOffline, l10n.homeOfflineHint),
      PresencePhase.goingOnline => (Icons.hourglass_top, l10n.homeStatusGoingOnline, l10n.homeOfflineHint),
      PresencePhase.goingOffline => (Icons.hourglass_bottom, l10n.homeStatusGoingOffline, l10n.homeOnlineHint),
      PresencePhase.online when presence.reconnecting => (
        Icons.wifi_off,
        l10n.homeStatusReconnecting,
        l10n.homeReconnectingHint,
      ),
      PresencePhase.online => (Icons.radar, l10n.homeStatusOnline, l10n.homeOnlineHint),
    };
    final canGoOnline = profile?.canGoOnline ?? false;
    final switchEnabled = !presence.busy && !presence.onTrip && (presence.wantOnline || canGoOnline);
    final live = presence.isOnline && !presence.reconnecting;
    final colors = AppColors.of(context);
    final onCard = live ? Colors.white : scheme.onSurface;
    final onCardMuted = live ? Colors.white.withValues(alpha: 0.85) : scheme.onSurfaceVariant;

    // While online the service streams fixes; offline, one fix places the map.
    final fix = presence.lastFix ?? ref.watch(driverHereProvider).value;
    final here = fix == null ? MapConfig.connaughtPlace : GeoPoint(fix.lat, fix.lng);

    return Scaffold(
      drawer: const DriverDrawer(),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RideMap(
                    spec: RideMapSpec(
                      center: here,
                      recenter: _recenter,
                      myLocation: fix != null,
                      padding: const EdgeInsets.only(bottom: 24),
                      markers: [
                        // The car shows only while riders can see this driver.
                        if (live && fix != null)
                          MapMarkerSpec(id: 'me', point: here, kind: MapMarkerKind.car, heading: fix.heading ?? 0),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
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
                            key: const Key('locate'),
                            icon: Icons.my_location_rounded,
                            tooltip: l10n.homeLocate,
                            onPressed: () {
                              setState(() => _recenter++);
                              if (presence.lastFix == null) ref.invalidate(driverHereProvider);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusSheet)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, -4)),
                ],
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  if (name != null) ...[
                    Text(l10n.homeGreeting(name), style: text.headlineMedium),
                    const SizedBox(height: 16),
                  ],
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      gradient: live ? colors.gradient : null,
                      color: live ? null : scheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                      border: live ? null : Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: live ? colors.gradientEnd.withValues(alpha: 0.35) : colors.shadow,
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(18, 18, 10, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBadge(icon: icon, size: 52, color: live ? Colors.white : scheme.onSurfaceVariant),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    key: const Key('presence-status'),
                                    style: text.titleLarge?.copyWith(color: onCard),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(hint, style: text.bodySmall?.copyWith(color: onCardMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Theme(
                          data: Theme.of(context).copyWith(
                            switchTheme: live
                                ? SwitchThemeData(
                                    thumbColor: const WidgetStatePropertyAll(Colors.white),
                                    trackColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.35)),
                                    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                                  )
                                : null,
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              key: const Key('online-switch'),
                              contentPadding: const EdgeInsets.only(left: 2),
                              title: Text(l10n.homeSwitchLabel, style: text.titleMedium?.copyWith(color: onCard)),
                              value: presence.wantOnline,
                              onChanged: switchEnabled ? _toggle : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (presence.onTrip && ride != null) ...[
                    const SizedBox(height: 12),
                    InfoBanner(
                      message: l10n.homeOnTripHint,
                      icon: Icons.directions_car_rounded,
                      action: TextButton(onPressed: () => context.go(Routes.trip), child: Text(l10n.homeViewTrip)),
                    ),
                  ],
                  for (final p in presence.problems) ...[const SizedBox(height: 12), _ProblemBanner(problem: p)],
                  if (presence.serverMessage != null) ...[
                    const SizedBox(height: 12),
                    ErrorBanner(message: presence.serverMessage!),
                  ],
                  if (profile != null && !profile.canGoOnline) ...[
                    const SizedBox(height: 12),
                    InfoBanner(
                      message: l10n.homeDocsAttention,
                      tone: BannerTone.warning,
                      action: TextButton(
                        onPressed: () => context.push(Routes.documents),
                        child: Text(l10n.homeDocsAction),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SoftCard(
                    onTap: () => context.push(Routes.earnings),
                    child: Row(
                      children: [
                        IconBadge(icon: Icons.account_balance_wallet_rounded, color: colors.accent, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.homeTodayEarnings, style: text.titleSmall),
                              Text(l10n.homeEarningsNote, style: text.bodySmall),
                            ],
                          ),
                        ),
                        Text(
                          today == null
                              ? l10n.homeEarningsUnavailable
                              : l10n.homeEarningsSummary(formatAmount(today.net), l10n.earningsTrips(today.rides)),
                          key: const Key('home-earnings'),
                          style: text.titleMedium,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.history_rounded,
                          label: l10n.menuHistory,
                          onTap: () => context.push(Routes.history),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickTile(
                          icon: Icons.battery_saver_rounded,
                          label: l10n.homeBatteryMenu,
                          onTap: () => context.push(Routes.battery),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SoftCard(
    onTap: onTap,
    shadow: false,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        IconBadge(icon: icon, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 2)),
      ],
    ),
  );
}

class _ProblemBanner extends ConsumerWidget {
  const _ProblemBanner({required this.problem});

  final PermissionProblem problem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gate = ref.read(permissionGateProvider);
    final message = switch (problem) {
      PermissionProblem.serviceOff => l10n.homeLocationServiceOff,
      PermissionProblem.locationDenied => l10n.homeLocationDenied,
      PermissionProblem.backgroundDenied => l10n.homeBackgroundLocationDenied,
      PermissionProblem.notificationsDenied => l10n.homeNotificationsDenied,
    };
    return ErrorBanner(
      message: message,
      retryLabel: l10n.homeOpenSettings,
      onRetry: problem == PermissionProblem.serviceOff ? gate.openLocationSettings : gate.openAppSettings,
    );
  }
}
