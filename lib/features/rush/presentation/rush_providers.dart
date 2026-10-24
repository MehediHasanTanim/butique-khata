import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/features/rush/data/drift_rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/domain/rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

final rushRepositoryProvider = Provider<RushRepository>(
  (ref) => DriftRushRepository(ref.watch(appDatabaseProvider)),
);

/// The season to plan against today, or null when none is set up.
final activeSeasonProvider = StreamProvider.autoDispose<Season?>((ref) {
  final today = ref.watch(clockProvider).today();
  return ref.watch(rushRepositoryProvider).watchActiveSeason(today);
});

/// All seasons that are switched on (for the setup list).
final seasonsProvider = StreamProvider.autoDispose<List<Season>>(
  (ref) => ref.watch(rushRepositoryProvider).watchSeasons(),
);

final rushItemsProvider = StreamProvider.autoDispose<List<RushItem>>(
  (ref) => ref.watch(rushRepositoryProvider).watchOpenItems(),
);

/// Garments per type and stage, for orders due by [toDate] (all when null).
final stageCountsProvider = StreamProvider.autoDispose
    .family<List<StageCount>, String?>(
      (ref, toDate) =>
          ref.watch(rushRepositoryProvider).watchStageCounts(toDate: toDate),
    );

/// Everything the Eid-rush screens need, computed once per change.
class RushPlan {
  RushPlan({required this.season, required this.today, required this.items})
    : engine = CapacityEngine(season: season, today: today),
      work = [
        for (final i in items)
          if (i.remainingWork.units > 0) i.remainingWork,
      ];

  final Season season;
  final String today;
  final List<RushItem> items;
  final CapacityEngine engine;

  /// Remaining work per promised day.
  final List<WorkLoad> work;

  late final List<DayLoad> days = engine.days(work);

  /// Capacity left by the target date, in work units ×100; negative when
  /// overbooked (E-6).
  late final int roomUnits = engine.roomUnits(work);

  int get daysLeft => season.daysLeft(today);

  /// Earliest day a new order of [units] can be promised, or null.
  String? safeDate(int units) => engine.earliestSafeDate(work, units);

  bool isSafe(int units, String date) => engine.isDateSafe(work, units, date);
}

/// The plan for the active season, or null when there is no season or the
/// data is still loading.
final rushPlanProvider = Provider.autoDispose<RushPlan?>((ref) {
  final season = ref.watch(activeSeasonProvider).value;
  final items = ref.watch(rushItemsProvider).value;
  if (season == null || items == null) return null;
  return RushPlan(
    season: season,
    today: ref.watch(clockProvider).today(),
    items: items,
  );
});
