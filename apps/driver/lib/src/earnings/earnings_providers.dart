import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ride_shared/ride_shared.dart';

/// `GET /driver/earnings?period=today|week` (SPEC §12 Earnings). Invalidated
/// when a trip is paid so Home and the Earnings screen pick up the new trip.
final driverEarningsProvider = FutureProvider.autoDispose.family<DriverEarnings, EarningsPeriod>((ref, period) {
  final userId = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
  if (userId == null) return DriverEarnings.empty(period);
  return ref.watch(rideApiProvider).driverEarnings(period);
}, retry: (_, _) => null);

/// `GET /driver/rides?page=&limit=` (SPEC §12 Trip history), newest first,
/// loaded a page at a time.
final driverHistoryProvider = AsyncNotifierProvider.autoDispose<DriverHistoryController, RidePages>(
  DriverHistoryController.new,
  retry: (_, _) => null,
);

class DriverHistoryController extends AsyncNotifier<RidePages> {
  static const pageSize = 20;

  @override
  Future<RidePages> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s is SessionLoggedIn ? s.user.id : null));
    if (userId == null) return const RidePages();
    return const RidePages().append(await ref.read(rideApiProvider).driverHistory(page: 1, limit: pageSize));
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.loadingMore || !cur.hasMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      state = AsyncData(cur.append(await ref.read(rideApiProvider).driverHistory(page: cur.page + 1, limit: pageSize)));
    } catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false, error: e));
    }
  }

  /// Pull to refresh: reload page 1, keeping the list on failure.
  Future<void> reload() async {
    try {
      state = AsyncData(
        const RidePages().append(await ref.read(rideApiProvider).driverHistory(page: 1, limit: pageSize)),
      );
    } catch (e) {
      if (state.value == null) state = AsyncError(e, StackTrace.current);
    }
  }
}
