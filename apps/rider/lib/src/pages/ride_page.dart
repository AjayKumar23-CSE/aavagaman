import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';
import '../strings.dart';

/// Finding → Assigned / En route → Trip in progress → Fare & payment → Rate
/// (SPEC §11). Owns the screen while `activeRideProvider` has a ride;
/// re-checks on resume.
class RidePage extends ConsumerStatefulWidget {
  const RidePage({super.key});

  /// Matching deadline (SPEC §9.4).
  static const searchWindow = Duration(minutes: 2);

  /// Rider cancellation is free within this window after accept (SPEC §9.5).
  static const freeCancelWindow = Duration(minutes: 2);

  @override
  ConsumerState<RidePage> createState() => _RidePageState();
}

class _RidePageState extends ConsumerState<RidePage> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) ref.read(activeRideProvider.notifier).refresh();
  }

  Future<void> _cancel(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final searching = ride.isSearching;
    final lateCancel =
        !searching &&
        ride.acceptedAt != null &&
        DateTime.now().difference(ride.acceptedAt!) > RidePage.freeCancelWindow;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(searching ? l10n.findingCancelTitle : l10n.assignedCancelTitle),
        content: Text(
          [
            searching ? l10n.findingCancelBody : l10n.assignedCancelBody,
            if (lateCancel) l10n.assignedCancelFeeWarning,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.findingKeep)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(l10n.findingConfirmCancel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final cancelled = await ref.read(activeRideProvider.notifier).cancel();
      final fee = cancelled.cancellationFee ?? 0;
      messenger.showSnackBar(
        SnackBar(
          content: Text(fee > 0 ? l10n.rideCancelledWithFee(formatAmount(fee)) : l10n.rideCancelled),
          duration: Duration(seconds: fee > 0 ? 6 : 4),
        ),
      );
    } catch (e) {
      // 409 RIDE_NOT_CANCELLABLE once the trip started.
      messenger.showSnackBar(SnackBar(content: Text(l10n.common.errorMessage(e))));
    }
  }

  /// SOS (SPEC §11): confirm → dial 112 → `POST /rides/:id/sos` → toast.
  /// Call the driver through the Aavagaman number: the server rings this
  /// phone first, then the driver; neither sees the other's number (D-058).
  Future<void> _callViaApp(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final call = await ref.read(rideApiProvider).requestCall(ride.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.callConnecting(IndianPhone.format(call.via)))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.common.errorMessage(e))));
    }
  }

  Future<void> _sos(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.sos, color: Theme.of(context).colorScheme.error, size: 40),
        title: Text(l10n.sosTitle),
        content: Text(l10n.sosBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(
            key: const Key('sos-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size(0, 40),
            ),
            child: Text(l10n.sosConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final car = ref.read(driverPositionProvider);
    final fix = await ref.read(locationSourceProvider).current();
    final at = fix.point ?? (car != null ? GeoPoint(car.lat, car.lng) : GeoPoint(ride.pickup.lat, ride.pickup.lng));
    final result = await ref.read(sosFlowProvider).raise(rideId: ride.id, at: at);
    messenger.showSnackBar(
      SnackBar(content: Text(result.alerted ? l10n.sosAlerted : l10n.sosFailed), duration: const Duration(seconds: 6)),
    );
  }

  /// Share trip (SPEC §11): the public `/share/:token` page.
  Future<void> _share(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = ride.shareToken;
    if (token == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.shareUnavailable)));
      return;
    }
    final url = ref.read(appConfigProvider).shareUrl(token);
    final ok = await ref.read(shareSheetProvider)(text: l10n.shareText(url), subject: l10n.shareSubject);
    if (!ok && mounted) messenger.showSnackBar(SnackBar(content: Text(l10n.shareUnavailable)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = ref.watch(activeRideProvider);
    final ride = active.value;
    if (ride == null) {
      return Scaffold(
        body: Center(
          child: active.hasError
              ? ErrorBanner(
                  message: l10n.rideLoadFailed,
                  retryLabel: l10n.retry,
                  onRetry: () => ref.invalidate(activeRideProvider),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final actions = _RideActions(
      onShare: () => _share(ride),
      onSos: () => _sos(ride),
      onCancel: () => _cancel(ride),
      onCall: () => _callViaApp(ride),
    );
    final body = switch (ride.status) {
      RideStatus.requested => _FindingView(ride: ride, onCancel: actions.onCancel),
      RideStatus.accepted || RideStatus.arrived => _AssignedView(ride: ride, actions: actions),
      RideStatus.started => _TripView(ride: ride, actions: actions),
      RideStatus.completed => _PaymentView(key: ValueKey('pay-${ride.id}'), ride: ride),
      RideStatus.paid => _RateView(key: ValueKey('rate-${ride.id}'), ride: ride),
      _ => _StatusView(ride: ride),
    };
    final rt = ref.watch(realtimeStatusProvider).value;
    return Scaffold(
      body: Column(
        children: [
          if (rt == RealtimeStatus.reconnecting) StatusStrip(l10n.reconnecting),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _RideActions {
  const _RideActions({required this.onShare, required this.onSos, required this.onCancel, required this.onCall});

  final VoidCallback onShare;
  final VoidCallback onSos;
  final VoidCallback onCancel;

  /// Bridged call through the Aavagaman number (D-058).
  final VoidCallback onCall;
}

Future<void> _call(String phone) async {
  try {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (e) {
    debugPrint('dialer unavailable: $e');
  }
}

// ----------------------------------------------------------------- finding

class _FindingView extends StatefulWidget {
  const _FindingView({required this.ride, required this.onCancel});

  final Ride ride;
  final VoidCallback onCancel;

  @override
  State<_FindingView> createState() => _FindingViewState();
}

class _FindingViewState extends State<_FindingView> {
  /// Seconds already spent searching when this view appeared (resume case),
  /// then advanced by the timer so the countdown never reads the wall clock.
  late int _elapsed = widget.ride.requestedAt == null
      ? 0
      : DateTime.now().difference(widget.ride.requestedAt!).inSeconds.clamp(0, RidePage.searchWindow.inSeconds);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed++));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final secs = (RidePage.searchWindow.inSeconds - _elapsed).clamp(0, RidePage.searchWindow.inSeconds);
    final progress = (secs / RidePage.searchWindow.inSeconds).clamp(0.0, 1.0);
    final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final pickup = GeoPoint(widget.ride.pickup.lat, widget.ride.pickup.lng);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: RideMap(
            spec: RideMapSpec(
              center: pickup,
              interactive: false,
              markers: [MapMarkerSpec(id: 'pickup', point: pickup, kind: MapMarkerKind.pickup)],
            ),
          ),
        ),
        SheetPanel(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RingProgress(
              pin: true,
              gradient: [AppColors.of(context).gradientStart, Brand.freshGreen],
              value: progress,
              size: 104,
              stroke: 8,
              child: Text(clock, key: const Key('finding-countdown'), style: text.titleLarge),
            ),
            const SizedBox(height: 18),
            Text(l10n.findingTitle, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              secs == 0 ? l10n.findingStillLooking : l10n.findingSubtitle,
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_on, size: 16, color: scheme.error),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.ride.drop.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton(key: const Key('cancel-ride'), onPressed: widget.onCancel, child: Text(l10n.findingCancel)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- assigned

class _AssignedView extends ConsumerWidget {
  const _AssignedView({required this.ride, required this.actions});

  final Ride ride;
  final _RideActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final position = ref.watch(driverPositionProvider);
    final driver = ride.driver;
    final arrived = ride.status == RideStatus.arrived;
    final pickup = GeoPoint(ride.pickup.lat, ride.pickup.lng);
    final car = position == null ? null : GeoPoint(position.lat, position.lng);

    return Column(
      children: [
        Expanded(
          child: RideMap(
            spec: RideMapSpec(
              center: pickup,
              fitPoints: [pickup, ?car],
              markers: [
                MapMarkerSpec(id: 'pickup', point: pickup, kind: MapMarkerKind.pickup),
                if (car != null)
                  MapMarkerSpec(id: 'driver', point: car, kind: MapMarkerKind.car, heading: position!.heading),
              ],
            ),
          ),
        ),
        SheetPanel(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(arrived ? l10n.assignedArrived : l10n.assignedOnTheWay, style: text.titleLarge),
                      if (!arrived)
                        Text(
                          position?.etaS != null
                              ? l10n.assignedEta(formatMinutes(position!.etaS!))
                              : l10n.assignedEtaUnknown,
                          key: const Key('eta'),
                          style: text.bodyMedium,
                        ),
                    ],
                  ),
                ),
                if (arrived)
                  StatusPill(
                    label: l10n.statusLabelArrived,
                    color: AppColors.of(context).success,
                    icon: Icons.check_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (driver != null) _DriverRow(driver: driver),
            if (ride.tripOtp != null) ...[const SizedBox(height: 14), _OtpCard(otp: ride.tripOtp!)],
            const SizedBox(height: 16),
            _ActionRow(driver: driver, actions: actions),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('cancel-ride'),
              onPressed: actions.onCancel,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              child: Text(l10n.assignedCancel),
            ),
          ],
        ),
      ],
    );
  }
}

/// The 4-digit trip OTP, large on saffron (SPEC §9.6).
class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.otp});

  final String otp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(color: colors.accentContainer, borderRadius: BorderRadius.circular(AppTheme.radius)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.assignedOtpLabel, style: text.labelMedium?.copyWith(color: colors.onAccentContainer)),
                const SizedBox(height: 2),
                Text(l10n.assignedOtpHint, style: text.bodySmall?.copyWith(color: colors.onAccentContainer)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            otp.split('').join(' '),
            key: const Key('trip-otp'),
            style: text.headlineMedium?.copyWith(color: colors.onAccentContainer, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------- trip in progress

/// STARTED (SPEC §11 In-progress): the trip track and a guide line to the
/// drop, the drop marker, the live car, Call / Share / SOS. No cancel: the
/// server answers 409 from STARTED.
class _TripView extends ConsumerWidget {
  const _TripView({required this.ride, required this.actions});

  final Ride ride;
  final _RideActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final position = ref.watch(driverPositionProvider);
    final track = ref.watch(driverTrackProvider);
    final pickup = GeoPoint(ride.pickup.lat, ride.pickup.lng);
    final drop = GeoPoint(ride.drop.lat, ride.drop.lng);
    final car = position == null ? null : GeoPoint(position.lat, position.lng);
    final driver = ride.driver;

    return Column(
      children: [
        Expanded(
          child: RideMap(
            spec: RideMapSpec(
              center: car ?? pickup,
              fitPoints: [car ?? pickup, drop],
              markers: [
                MapMarkerSpec(id: 'pickup', point: pickup, kind: MapMarkerKind.pickup),
                MapMarkerSpec(id: 'drop', point: drop, kind: MapMarkerKind.drop),
                if (car != null)
                  MapMarkerSpec(id: 'driver', point: car, kind: MapMarkerKind.car, heading: position!.heading),
              ],
              polylines: [
                MapPolylineSpec(id: 'track', points: [pickup, ...track, ?car]),
                MapPolylineSpec(id: 'route', points: [car ?? pickup, drop], dashed: true),
              ],
            ),
          ),
        ),
        SheetPanel(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.tripTitle, key: const Key('trip-title'), style: text.titleLarge),
                ),
                if (ride.estFareMin != null && ride.estFareMax != null)
                  StatusPill(
                    label: formatFareRange(ride.estFareMin!, ride.estFareMax!),
                    color: AppColors.of(context).accent,
                    icon: Icons.currency_rupee_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.tripHeading(ride.drop.address),
                    style: text.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (driver != null) _DriverRow(driver: driver, compact: true),
            const SizedBox(height: 16),
            _ActionRow(driver: driver, actions: actions),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- fare & payment

enum _PayPhase { cash, idle, ordering, checkout, verifying, failed, unavailable }

/// COMPLETED (SPEC §11 End, §15): fare breakdown from the receipt; cash →
/// wait for the driver's confirmation (`payment:status paid`); online →
/// order → Razorpay Checkout → verify, with retry or switch to cash.
class _PaymentView extends ConsumerStatefulWidget {
  const _PaymentView({super.key, required this.ride});

  final Ride ride;

  @override
  ConsumerState<_PaymentView> createState() => _PaymentViewState();
}

class _PaymentViewState extends ConsumerState<_PaymentView> {
  late _PayPhase _phase = widget.ride.paymentMethod == PaymentMethod.online ? _PayPhase.idle : _PayPhase.cash;
  String? _message;

  /// A Razorpay order exists: the driver's cash confirmation is held back
  /// for a few minutes (409 PAYMENT_PENDING), so tell the rider.
  bool _orderCreated = false;

  void _set(_PayPhase phase, [String? message]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  Future<void> _payOnline() async {
    final l10n = AppLocalizations.of(context);
    final ride = widget.ride;
    final payments = ref.read(paymentsApiProvider);
    final user = ref.read(sessionProvider.select((s) => s is SessionLoggedIn ? s.user : null));
    _set(_PayPhase.ordering);
    final PaymentOrder order;
    try {
      order = await payments.createOrder(ride.id);
      _orderCreated = true;
    } on ApiException catch (e) {
      switch (e.code) {
        case 'PAYMENTS_UNAVAILABLE':
          _set(_PayPhase.unavailable, l10n.payUnavailable);
        case 'RIDE_NOT_PAYABLE':
          // Already paid (cash confirmed meanwhile, or a webhook): re-sync.
          await ref.read(activeRideProvider.notifier).refresh();
          _set(_PayPhase.failed, e.message);
        default:
          _set(_PayPhase.failed, l10n.common.errorMessage(e));
      }
      return;
    } catch (e) {
      _set(_PayPhase.failed, l10n.common.errorMessage(e));
      return;
    }
    if (!mounted) return;
    _set(_PayPhase.checkout);
    final outcome = await ref
        .read(razorpayLauncherProvider)
        .checkout(
          RazorpayCheckout(
            order: order,
            contact: user?.phone ?? '',
            email: user?.email,
            name: l10n.appTitle,
            description: l10n.payDescription(ride.drop.address),
          ),
        );
    if (!mounted) return;
    switch (outcome) {
      case RazorpaySuccess(:final result):
        _set(_PayPhase.verifying);
        try {
          await payments.verify(ride.id, result);
          ref.read(activeRideProvider.notifier).markPaid();
        } catch (e) {
          debugPrint('payment verify failed: $e');
          // The webhook / poll job still confirms a captured payment.
          _set(_PayPhase.failed, l10n.payVerifyFailed);
        }
      case RazorpayFailure(:final cancelled, :final message):
        _set(_PayPhase.failed, cancelled ? l10n.payCancelled : (message ?? l10n.payFailedBody));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ride = widget.ride;
    final receipt = ref.watch(receiptProvider(ride.id));
    final due = receipt.value?.total ?? ride.dueAmount ?? 0;
    final amount = formatAmount(due);
    final driver = ride.driver;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        HeroPanel(
          child: Column(
            children: [
              const SizedBox(height: 8),
              const IconBadge(icon: Icons.flag_rounded, color: Colors.white, size: 64),
              const SizedBox(height: 14),
              Text(
                l10n.payTitle,
                key: const Key('status-title'),
                style: text.headlineSmall?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                ride.drop.address,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SoftCard(
                child: receipt.when(
                  loading: () => const Center(
                    child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FareLines.fromRide(ride),
                      const SizedBox(height: 8),
                      ErrorBanner(
                        message: l10n.payReceiptFailed,
                        retryLabel: l10n.retry,
                        onRetry: () => ref.invalidate(receiptProvider(ride.id)),
                      ),
                    ],
                  ),
                  data: (r) => _FareLines.fromReceipt(r),
                ),
              ),
              const SizedBox(height: 20),
              ..._paymentSection(l10n, text, scheme, amount),
              const SizedBox(height: 20),
              if (driver != null) SoftCard(shadow: false, child: _DriverRow(driver: driver, compact: true)),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _paymentSection(AppLocalizations l10n, TextTheme text, ColorScheme scheme, String amount) {
    switch (_phase) {
      case _PayPhase.cash:
        final colors = AppColors.of(context);
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.accentContainer,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              children: [
                Icon(Icons.payments_rounded, color: colors.onAccentContainer, size: 28),
                const SizedBox(height: 8),
                Text(
                  l10n.payCashInstruction(amount),
                  key: const Key('pay-cash'),
                  style: text.titleLarge?.copyWith(color: colors.onAccentContainer),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colors.onAccentContainer),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        l10n.payCashWaiting,
                        style: text.bodyMedium?.copyWith(color: colors.onAccentContainer),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_orderCreated) ...[
            const SizedBox(height: 8),
            Text(l10n.payCashAfterOnlineNote, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ];
      case _PayPhase.idle:
        return [
          PrimaryButton(key: const Key('pay-online'), label: l10n.payOnlineButton(amount), onPressed: _payOnline),
        ];
      case _PayPhase.ordering:
      case _PayPhase.checkout:
        return [PrimaryButton(label: l10n.payOnlineOpening, onPressed: null, loading: true)];
      case _PayPhase.verifying:
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(l10n.payOnlineVerifying, style: text.bodyMedium),
            ],
          ),
        ];
      case _PayPhase.failed:
      case _PayPhase.unavailable:
        return [
          ErrorBanner(message: _message ?? l10n.payFailedBody),
          const SizedBox(height: 12),
          if (_phase == _PayPhase.failed)
            PrimaryButton(key: const Key('pay-retry'), label: l10n.payRetry, onPressed: _payOnline),
          TextButton(
            key: const Key('pay-switch-cash'),
            onPressed: () => _set(_PayPhase.cash),
            child: Text(l10n.paySwitchToCash),
          ),
        ];
    }
  }
}

/// Fare / GST / cancellation fee / total lines, from the receipt or (when
/// it failed to load) from the ride itself.
class _FareLines extends StatelessWidget {
  const _FareLines({required this.fare, required this.gst, required this.fee, required this.total, this.stats});

  factory _FareLines.fromReceipt(RideReceipt r) => _FareLines(
    fare: r.fare,
    gst: r.gst,
    fee: r.cancellationFee,
    total: r.total,
    stats: r.distanceM != null && r.durationS != null ? (r.distanceM!, r.durationS!) : null,
  );

  factory _FareLines.fromRide(Ride ride) => _FareLines(
    fare: ride.finalFare ?? 0,
    gst: null,
    fee: ride.cancellationFee ?? 0,
    total: ride.dueAmount ?? 0,
    stats: ride.actualDistanceM != null && ride.actualDurationS != null
        ? (ride.actualDistanceM!, ride.actualDurationS!)
        : null,
  );

  final double fare;
  final double? gst;
  final double fee;
  final double total;
  final (int, int)? stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.payTripStats(formatDistance(stats!.$1), formatClock(stats!.$2)), style: text.bodySmall),
          ),
        AmountRow(label: l10n.payFare, amount: formatAmount(fare)),
        if (gst != null) AmountRow(label: l10n.payFareInclGst(formatAmount(gst!)), amount: '', muted: true),
        if (fee > 0) AmountRow(label: l10n.payCancellationFee, amount: formatAmount(fee)),
        const Divider(),
        AmountRow(label: l10n.payTotal, amount: formatAmount(total), emphasis: true),
      ],
    );
  }
}

// -------------------------------------------------------------------- rate

/// PAID (SPEC §11 Rating): stars + optional comment, Skip allowed.
class _RateView extends ConsumerStatefulWidget {
  const _RateView({super.key, required this.ride});

  final Ride ride;

  @override
  ConsumerState<_RateView> createState() => _RateViewState();
}

class _RateViewState extends ConsumerState<_RateView> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _finish({String? toast}) {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(activeRideProvider.notifier).dismiss();
    ref.invalidate(rideHistoryProvider);
    context.go(Routes.home);
    if (toast != null) messenger.showSnackBar(SnackBar(content: Text(toast)));
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(rideApiProvider).rate(widget.ride.id, stars: _stars, comment: _comment.text);
      ref.read(ratedRidesProvider.notifier).add(widget.ride.id);
      if (mounted) _finish(toast: l10n.rateThanks);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_RATED') {
        ref.read(ratedRidesProvider.notifier).add(widget.ride.id);
        _finish();
        return;
      }
      setState(() => _error = l10n.common.errorMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = l10n.common.errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final driver = widget.ride.driver;
    final due = widget.ride.dueAmount;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        HeroPanel(
          child: Column(
            children: [
              const SizedBox(height: 8),
              const IconBadge(icon: Icons.check_rounded, color: Colors.white, size: 64),
              const SizedBox(height: 14),
              Text(
                l10n.statusPaid,
                key: const Key('status-title'),
                style: text.headlineSmall?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              if (due != null) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.ratePaidAmount(formatAmount(due)),
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (driver != null) Center(child: InitialsAvatar(name: driver.name, radius: 32)),
              const SizedBox(height: 14),
              Text(l10n.rateTitle, style: text.titleLarge, textAlign: TextAlign.center),
              if (driver?.name != null)
                Text(l10n.rateSubtitle(driver!.name!), textAlign: TextAlign.center, style: text.bodyMedium),
              const SizedBox(height: 16),
              StarRating(
                value: _stars,
                onChanged: _sending ? null : (n) => setState(() => _stars = n),
                semanticLabel: (n) => l10n.rateStars(n),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('rate-comment'),
                controller: _comment,
                enabled: !_sending,
                maxLines: 3,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.rateCommentLabel,
                  counterText: '',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(message: _error!)],
              const SizedBox(height: 20),
              PrimaryButton(
                key: const Key('rate-submit'),
                label: l10n.rateSubmit,
                loading: _sending,
                onPressed: _stars == 0 ? null : _submit,
              ),
              TextButton(
                key: const Key('rate-skip'),
                onPressed: _sending ? null : () => _finish(),
                child: Text(l10n.rateSkip),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ shared

class _DriverRow extends StatelessWidget {
  const _DriverRow({required this.driver, this.compact = false});

  final RideDriver driver;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Row(
      children: [
        InitialsAvatar(name: driver.name, radius: compact ? 20 : 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driver.name ?? '',
                style: compact ? text.titleSmall : text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (driver.rating != null) ...[
                    Icon(Icons.star_rounded, size: 16, color: colors.accent),
                    const SizedBox(width: 2),
                    Text(driver.rating!.toStringAsFixed(1), style: text.labelMedium),
                    const SizedBox(width: 8),
                  ],
                  if (driver.vehicle != null)
                    Flexible(
                      child: Text(
                        driver.vehicle!.label,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (driver.vehicle != null) ...[
          const SizedBox(width: 10),
          KeyedSubtree(key: const Key('plate'), child: PlateBadge(driver.vehicle!.regNumber)),
        ],
      ],
    );
  }
}

/// Call · Share trip · SOS.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.driver, required this.actions});

  final RideDriver? driver;
  final _RideActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final driver = this.driver;
    // Masked calling (server bridges, numbers stay private) beats the dialer.
    final bridge = driver?.canBridge ?? false;
    final canCall = bridge || (driver?.canCall ?? false);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Tooltip(
          message: bridge
              ? l10n.assignedCallViaHint
              : canCall
              ? l10n.assignedCall
              : l10n.assignedCallHint,
          child: ActionCircle(
            key: const Key('call'),
            icon: Icons.call_rounded,
            label: l10n.assignedCall,
            onPressed: !canCall
                ? null
                : bridge
                ? actions.onCall
                : () => _call(driver!.phone!),
            color: AppColors.of(context).success,
          ),
        ),
        ActionCircle(
          key: const Key('share'),
          icon: Icons.ios_share_rounded,
          label: l10n.assignedShare,
          onPressed: actions.onShare,
        ),
        ActionCircle(
          key: const Key('sos'),
          icon: Icons.sos_rounded,
          label: l10n.assignedSos,
          onPressed: actions.onSos,
          color: Theme.of(context).colorScheme.error,
          filled: true,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ status

/// CANCELLED / NO_DRIVER: the outcome, then *Back to home*.
class _StatusView extends ConsumerWidget {
  const _StatusView({required this.ride});

  final Ride ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, body) = switch (ride.status) {
      RideStatus.noDriver => (Icons.search_off, l10n.statusNoDriver, l10n.statusNoDriverBody),
      _ => (Icons.cancel_outlined, l10n.rideCancelled, l10n.statusCancelledBody),
    };

    return SafeArea(
      child: EmptyState(
        icon: icon,
        color: scheme.error,
        title: title,
        body: [
          body,
          if (ride.status == RideStatus.cancelled && ride.cancelReason != null)
            l10n.statusCancelledReason(ride.cancelReason!),
          if (ride.status == RideStatus.cancelled && (ride.cancellationFee ?? 0) > 0)
            l10n.statusCancellationFee(formatAmount(ride.cancellationFee!)),
        ].join('\n'),
        action: FilledButton(
          key: const Key('dismiss-ride'),
          onPressed: () {
            ref.read(activeRideProvider.notifier).dismiss();
            context.go(Routes.home);
          },
          child: Text(l10n.backToHome),
        ),
      ),
    );
  }
}
