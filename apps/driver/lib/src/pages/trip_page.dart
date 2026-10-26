import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ride_shared/ride_shared.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../earnings/earnings_providers.dart';
import '../providers.dart';
import '../router.dart';
import '../trip/cancel_reason.dart';

/// Trip screen (SPEC §12): Navigate to pickup → Arrived → OTP entry → Start
/// trip → Navigate to drop → End trip → Collect payment → Rate rider. Rider
/// name and masked phone (full phone after ARRIVED), Call, Cancel with a
/// reason picker, SOS.
class TripPage extends ConsumerStatefulWidget {
  const TripPage({super.key});

  static Uri navigationIntent(RidePlace p) => Uri.parse('google.navigation:q=${p.lat},${p.lng}');

  static Uri navigationFallback(RidePlace p) =>
      Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '${p.lat},${p.lng}'});

  @override
  ConsumerState<TripPage> createState() => _TripPageState();
}

class _TripPageState extends ConsumerState<TripPage> {
  final _otp = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _otpError = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  Future<void> _navigate(RidePlace to) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = _l10n.tripNavigateFailed;
    try {
      if (await launchUrl(TripPage.navigationIntent(to), mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    try {
      if (await launchUrl(TripPage.navigationFallback(to), mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  Future<void> _call(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (e) {
      debugPrint('dialer unavailable: $e');
    }
  }

  /// Call the rider through the Aavagaman number: the server rings this phone
  /// first, then the rider; neither sees the other's number (D-058).
  Future<void> _callViaApp(Ride ride) async {
    final l10n = _l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final call = await ref.read(rideApiProvider).requestCall(ride.id, driver: true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.callConnecting(IndianPhone.format(call.via)))));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.callFailed)));
    }
  }

  /// Bridge when the server offers it, else the dialer once the number is revealed.
  VoidCallback? _callAction(Ride ride) {
    final rider = ride.rider;
    if (rider == null) return null;
    if (rider.canBridge) return () => _callViaApp(ride);
    if (rider.canCall) return () => _call(rider.phone!);
    return null;
  }

  /// Latest fix from the online feed, else a one-off GPS read.
  Future<GeoPoint?> _position() async {
    final last = ref.read(presenceProvider).lastFix;
    if (last != null) return GeoPoint(last.lat, last.lng);
    final fix = await ref.read(locationFeedProvider).currentFix();
    return fix == null ? null : GeoPoint(fix.lat, fix.lng);
  }

  /// Runs a trip call; the returned ride replaces the current one.
  Future<void> _run(Future<Ride> Function() call, {bool otp = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _otpError = false;
    });
    try {
      ref.read(activeRideProvider.notifier).set(await call());
      _otp.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.displayMessage;
        _otpError = otp && e.code.startsWith('OTP_');
      });
      if (otp) _otp.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Trip calls that send the driver's position.
  Future<void> _runAt(Future<Ride> Function(GeoPoint at) call, {bool otp = false}) async {
    final at = await _position();
    if (!mounted) return;
    if (at == null) {
      setState(() => _error = _l10n.tripLocationUnavailable);
      return;
    }
    await _run(() => call(at), otp: otp);
  }

  Future<void> _arrived(Ride ride) =>
      _runAt((at) => ref.read(rideApiProvider).driverArrived(ride.id, lat: at.lat, lng: at.lng));

  Future<void> _start(Ride ride, String code) =>
      _runAt((at) => ref.read(rideApiProvider).driverStart(ride.id, otp: code, lat: at.lat, lng: at.lng), otp: true);

  Future<void> _end(Ride ride) async {
    final ok = await _confirm(_l10n.tripEndConfirmTitle, _l10n.tripEndConfirmBody, _l10n.tripEnd);
    if (!ok || !mounted) return;
    await _runAt((at) => ref.read(rideApiProvider).driverComplete(ride.id, lat: at.lat, lng: at.lng));
  }

  Future<void> _cashCollected(Ride ride) async {
    final amount = formatAmount(ride.dueAmount ?? 0);
    final ok = await _confirm(
      _l10n.paymentCashConfirmTitle,
      _l10n.paymentCashConfirmBody(amount),
      _l10n.paymentCashCollected,
    );
    if (!ok || !mounted) return;
    await _run(() => ref.read(rideApiProvider).driverCashCollected(ride.id));
  }

  Future<void> _cancel(Ride ride) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(ride: ride),
    );
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(rideApiProvider).driverCancel(ride.id, reason: reason);
      ref.read(activeRideProvider.notifier).cancelledByMe(result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.displayMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// SOS (SPEC §12): confirm → dial 112 → `POST /rides/:id/sos`.
  Future<void> _sos(Ride ride) async {
    final l10n = _l10n;
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.sosConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final at = await _position() ?? GeoPoint(ride.pickup.lat, ride.pickup.lng);
    final result = await ref.read(sosFlowProvider).raise(rideId: ride.id, at: at);
    messenger.showSnackBar(SnackBar(content: Text(result.alerted ? l10n.sosAlerted : l10n.sosFailed)));
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_l10n.cancel)),
            FilledButton(key: const Key('confirm'), onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  /// Leaves the ended trip: Home shows fresh earnings.
  void _finish() {
    ref.invalidate(driverEarningsProvider);
    ref.invalidate(driverHistoryProvider);
    ref.read(activeRideProvider.notifier).dismiss();
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final current = ref.watch(activeRideProvider).value;
    if (current == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final ride = current.ride;

    if (current.awaitingRating) return _RateRiderView(ride: ride, onDone: _finish);
    if (current.ended) return _EndedView(current: current, onDone: _finish);

    final (title, status) = switch (ride.status) {
      RideStatus.accepted => (l10n.tripTitle, l10n.tripStatusAccepted),
      RideStatus.arrived => (l10n.tripTitle, l10n.tripStatusArrived),
      RideStatus.started => (l10n.tripTitleOnTrip, l10n.tripStatusStarted),
      _ => (l10n.tripTitlePayment, l10n.tripStatusCompleted),
    };
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canCancel = ride.status == RideStatus.accepted || ride.status == RideStatus.arrived;

    final colors = AppColors.of(context);
    final step = switch (ride.status) {
      RideStatus.accepted || RideStatus.arrived => 0,
      RideStatus.started => 1,
      _ => 2,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: const Key('sos'),
              tooltip: l10n.sosTooltip,
              icon: const Icon(Icons.sos_rounded),
              style: IconButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
              ),
              onPressed: () => _sos(ride),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (ride.status != RideStatus.completed) ...[
            _TripMap(ride: ride, fix: ref.watch(presenceProvider.select((p) => p.lastFix))),
            const SizedBox(height: 16),
          ],
          _Steps(current: step, labels: [l10n.tripStepPickup, l10n.tripStepTrip, l10n.tripStepPayment]),
          const SizedBox(height: 16),
          Text(status, key: const Key('trip-status'), style: text.titleLarge),
          const SizedBox(height: 12),
          if (ride.status == RideStatus.completed)
            _PaymentView(ride: ride, busy: _busy, onCash: () => _cashCollected(ride))
          else ...[
            if (ride.rider != null) _RiderCard(rider: ride.rider!, onCall: _callAction(ride)),
            const SizedBox(height: 12),
            SoftCard(
              shadow: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RoutePoints(
                    pickup: ride.pickup.address,
                    drop: ride.drop.address,
                    pickupLabel: l10n.tripPickup,
                    dropLabel: l10n.tripDrop,
                  ),
                  if (ride.estFareMin != null && ride.estFareMax != null) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Icon(Icons.currency_rupee_rounded, size: 18, color: colors.accent),
                        const SizedBox(width: 8),
                        Text(
                          l10n.tripFare(formatFareRange(ride.estFareMin!, ride.estFareMax!)),
                          style: text.titleSmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (ride.status != RideStatus.arrived)
              OutlinedButton.icon(
                key: const Key('navigate'),
                onPressed: () => _navigate(ride.status == RideStatus.started ? ride.drop : ride.pickup),
                icon: const Icon(Icons.navigation_rounded),
                label: Text(ride.status == RideStatus.started ? l10n.tripNavigateToDrop : l10n.tripNavigate),
              ),
            if (ride.status == RideStatus.arrived)
              SoftCard(
                borderColor: scheme.primary.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.tripOtpLabel, style: text.titleMedium),
                    Text(l10n.tripOtpHint, style: text.bodySmall),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: OtpInput(
                        key: const Key('trip-otp'),
                        length: 4,
                        autofocus: false,
                        controller: _otp,
                        enabled: !_busy,
                        hasError: _otpError,
                        onCompleted: (code) => _start(ride, code),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(message: _error!)],
          const SizedBox(height: 16),
          switch (ride.status) {
            RideStatus.accepted => PrimaryButton(
              key: const Key('arrived'),
              label: l10n.tripArrived,
              loading: _busy,
              onPressed: () => _arrived(ride),
            ),
            RideStatus.arrived => PrimaryButton(
              key: const Key('start'),
              label: l10n.tripStart,
              loading: _busy,
              onPressed: () => _otp.text.length == 4 ? _start(ride, _otp.text) : setState(() => _otpError = true),
            ),
            RideStatus.started => PrimaryButton(
              key: const Key('end'),
              label: l10n.tripEnd,
              loading: _busy,
              onPressed: () => _end(ride),
            ),
            _ => const SizedBox.shrink(),
          },
          if (canCancel) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('cancel-ride'),
              onPressed: _busy ? null : () => _cancel(ride),
              child: Text(l10n.tripCancel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pickup · Trip · Payment progress strip.
class _Steps extends StatelessWidget {
  const _Steps({required this.current, required this.labels});

  final int current;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= current ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: text.labelSmall?.copyWith(color: i == current ? scheme.primary : scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({required this.rider, required this.onCall});

  final RideRider rider;

  /// Null while calling is locked (before ARRIVED without masked calling).
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          InitialsAvatar(name: rider.name, radius: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rider.name ?? l10n.tripRider,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    rider.canBridge
                        ? l10n.tripNumberPrivate
                        : rider.canCall
                        ? IndianPhone.format(rider.phone!)
                        : rider.phoneMasked,
                    if (rider.rating != null) '${rider.rating!.toStringAsFixed(1)} ★',
                  ].join(' · '),
                  key: const Key('rider-phone'),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Tooltip(
            message: rider.canBridge
                ? l10n.tripCallVia
                : onCall != null
                ? l10n.tripCall
                : l10n.tripCallHint,
            child: IconButton(
              key: const Key('call-rider'),
              icon: const Icon(Icons.call_rounded),
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                fixedSize: const Size(48, 48),
                backgroundColor: colors.success.withValues(alpha: 0.12),
                foregroundColor: colors.success,
                disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              onPressed: onCall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The driver's car and where it is heading: the pickup until the trip
/// starts, then the drop. Turn-by-turn stays in Google Maps (Navigate).
class _TripMap extends StatelessWidget {
  const _TripMap({required this.ride, required this.fix});

  final Ride ride;
  final DriverFix? fix;

  @override
  Widget build(BuildContext context) {
    final started = ride.status == RideStatus.started;
    final pickup = GeoPoint(ride.pickup.lat, ride.pickup.lng);
    final drop = GeoPoint(ride.drop.lat, ride.drop.lng);
    final target = started ? drop : pickup;
    final car = fix == null ? null : GeoPoint(fix!.lat, fix!.lng);
    return ClipRRect(
      key: const Key('trip-map'),
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: SizedBox(
        height: 220,
        child: RideMap(
          spec: RideMapSpec(
            center: car ?? target,
            interactive: false,
            fitPoints: [?car, target],
            markers: [
              if (!started) MapMarkerSpec(id: 'pickup', point: pickup, kind: MapMarkerKind.pickup),
              MapMarkerSpec(id: 'drop', point: drop, kind: MapMarkerKind.drop),
              if (car != null)
                MapMarkerSpec(id: 'car', point: car, kind: MapMarkerKind.car, heading: fix!.heading ?? 0),
            ],
            polylines: [
              if (car != null) MapPolylineSpec(id: 'to-target', points: [car, target], dashed: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collect payment (SPEC §12): final fare; "Cash collected" (confirm), or
/// "Waiting for online payment" until `payment:status` (with cash as the
/// fallback when the rider's online payment fails).
class _PaymentView extends StatelessWidget {
  const _PaymentView({required this.ride, required this.busy, required this.onCash});

  final Ride ride;
  final bool busy;
  final VoidCallback onCash;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final online = ride.paymentMethod == PaymentMethod.online;
    final fee = ride.cancellationFee ?? 0;
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: colors.gradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.paymentAmountDue,
                style: text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
              Text(
                formatAmount(ride.dueAmount ?? 0),
                key: const Key('amount-due'),
                style: text.displayMedium?.copyWith(color: Colors.white),
              ),
              if (ride.actualDistanceM != null && ride.actualDurationS != null)
                Text(
                  l10n.paymentTrip(formatDistance(ride.actualDistanceM!), formatMinutes(ride.actualDurationS!)),
                  style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              const SizedBox(height: 12),
              StatusPill(
                label: online ? l10n.paymentMethodOnline : l10n.paymentMethodCash,
                color: Colors.white,
                icon: online ? Icons.qr_code_2_rounded : Icons.payments_rounded,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SoftCard(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ride.finalFare != null) _AmountLine(l10n.paymentFare, ride.finalFare!),
              if (fee > 0) _AmountLine(l10n.paymentPreviousFee, fee),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (online) ...[
          Row(
            children: [
              const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.paymentWaitingOnline, key: const Key('waiting-online'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.paymentOnlineFallback, style: text.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('cash-collected'),
            onPressed: busy ? null : onCash,
            child: Text(l10n.paymentCashCollected),
          ),
        ] else
          PrimaryButton(
            key: const Key('cash-collected'),
            label: l10n.paymentCashCollected,
            loading: busy,
            onPressed: onCash,
          ),
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine(this.label, this.amount);

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(formatAmount(amount)),
    ],
  );
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.ride});

  final Ride ride;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  CancelReason? _reason;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// No-show only after waiting [noShowWait] at the pickup (SPEC §9.5).
  bool get _noShowAllowed {
    final arrivedAt = widget.ride.arrivedAt;
    return widget.ride.status == RideStatus.arrived &&
        arrivedAt != null &&
        DateTime.now().difference(arrivedAt) >= noShowWait;
  }

  String _label(AppLocalizations l10n, CancelReason r) => switch (r) {
    CancelReason.vehicleBreakdown => l10n.cancelReasonVehicleBreakdown,
    CancelReason.riderNotReachable => l10n.cancelReasonRiderNotReachable,
    CancelReason.riderNoShow => l10n.cancelReasonRiderNoShow,
    CancelReason.wrongPickup => l10n.cancelReasonWrongPickup,
    CancelReason.other => l10n.cancelReasonOther,
  };

  String? get _wire {
    final r = _reason;
    if (r == null) return null;
    if (r != CancelReason.other) return r.wire;
    final note = _note.text.trim();
    return note.isEmpty ? null : '${r.wire}: $note';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.cancelTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cancelWarning, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final r in CancelReason.values)
              ListTile(
                key: Key('reason-${r.name}'),
                contentPadding: EdgeInsets.zero,
                enabled: r != CancelReason.riderNoShow || _noShowAllowed,
                leading: Icon(_reason == r ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(_label(l10n, r)),
                subtitle: r == CancelReason.riderNoShow && !_noShowAllowed
                    ? Text(l10n.cancelNoShowWait(noShowWait.inMinutes))
                    : null,
                onTap: () => setState(() => _reason = r),
              ),
            if (_reason == CancelReason.other)
              TextField(
                key: const Key('reason-note'),
                controller: _note,
                maxLength: 200,
                decoration: InputDecoration(hintText: l10n.cancelOtherHint),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancelKeep)),
        FilledButton(
          key: const Key('cancel-confirm'),
          onPressed: _wire == null ? null : () => Navigator.pop(context, _wire),
          child: Text(l10n.cancelConfirm),
        ),
      ],
    );
  }
}

class _EndedView extends StatelessWidget {
  const _EndedView({required this.current, required this.onDone});

  final DriverRide current;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ride = current.ride;
    final message = current.reassigned
        ? l10n.tripReassigned
        : current.cancelledByMe
        ? (ride.status == RideStatus.cancelled && ride.cancelledBy == CancelActor.driver
              ? l10n.tripNoShowCancelled
              : l10n.tripYouCancelled)
        : ride.status == RideStatus.cancelled && ride.cancelledBy == CancelActor.rider
        ? l10n.tripCancelledByRider
        : l10n.tripEnded;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tripTitle), automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: IconBadge(
                  icon: Icons.info_outline_rounded,
                  size: 88,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                key: const Key('trip-ended'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onDone, child: Text(l10n.backToHome)),
            ],
          ),
        ),
      ),
    );
  }
}

/// PAID: rate the rider (SPEC §12), skip allowed.
class _RateRiderView extends ConsumerStatefulWidget {
  const _RateRiderView({required this.ride, required this.onDone});

  final Ride ride;
  final VoidCallback onDone;

  @override
  ConsumerState<_RateRiderView> createState() => _RateRiderViewState();
}

class _RateRiderViewState extends ConsumerState<_RateRiderView> {
  int _stars = 0;
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(rideApiProvider).driverRate(widget.ride.id, stars: _stars);
      widget.onDone();
    } on ApiException catch (e) {
      if (e.code == 'ALREADY_RATED') return widget.onDone();
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.isNetwork ? AppLocalizations.of(context).rateFailed : e.displayMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final rider = widget.ride.rider;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroPanel(
            child: Column(
              children: [
                const SizedBox(height: 8),
                const IconBadge(icon: Icons.check_rounded, color: Colors.white, size: 64),
                const SizedBox(height: 14),
                Text(
                  l10n.paymentReceived,
                  key: const Key('payment-received'),
                  style: text.headlineSmall?.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (widget.ride.dueAmount != null)
                  Text(
                    formatAmount(widget.ride.dueAmount!),
                    style: text.headlineMedium?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(child: InitialsAvatar(name: rider?.name, radius: 32)),
                const SizedBox(height: 12),
                Text(
                  rider?.name == null ? l10n.rateTitle : '${l10n.rateTitle}\n${rider!.name}',
                  style: text.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Center(
                  child: StarRating(
                    key: const Key('stars'),
                    value: _stars,
                    onChanged: _sending ? null : (n) => setState(() => _stars = n),
                  ),
                ),
                if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(message: _error!)],
                const SizedBox(height: 24),
                PrimaryButton(
                  key: const Key('rate-submit'),
                  label: l10n.rateSubmit,
                  loading: _sending,
                  onPressed: _stars == 0 ? null : _submit,
                ),
                TextButton(
                  key: const Key('rate-skip'),
                  onPressed: _sending ? null : widget.onDone,
                  child: Text(l10n.rateSkip),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
