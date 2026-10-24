import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

/// 2026-03-10 is a Tuesday.
const today = '2026-03-10';

Season season({
  String target = '2026-03-15',
  int capacity = 10,
  int mask = WorkingDays.all,
  Set<String> closed = const {},
}) => Season(
  id: 's',
  name: 'Eid',
  kind: SeasonKind.eidFitr,
  targetDate: target,
  dailyCapacity: capacity,
  workingDaysMask: mask,
  closedDates: closed,
);

CapacityEngine engine({
  String target = '2026-03-15',
  int capacity = 10,
  int mask = WorkingDays.all,
  Set<String> closed = const {},
  String now = today,
}) => CapacityEngine(
  season: season(
    target: target,
    capacity: capacity,
    mask: mask,
    closed: closed,
  ),
  today: now,
);

void main() {
  group('calendar basics', () {
    test('date arithmetic and working days', () {
      final e = engine();
      expect(e.indexOf('2026-03-10'), 0);
      expect(e.indexOf('2026-03-15'), 5);
      expect(e.indexOf('2026-03-01'), 0, reason: 'late work starts today');
      expect(e.dateAt(3), '2026-03-13');
      expect(e.isWorkingDay('2026-03-13'), isTrue);
    });

    test('weekly days off and closed dates have no capacity', () {
      // Friday (weekday 5) off.
      final mask = WorkingDays.toggle(WorkingDays.all, 5);
      final e = engine(mask: mask, closed: {'2026-03-14'});
      expect(e.capacityOn('2026-03-13'), 0, reason: 'Friday');
      expect(e.capacityOn('2026-03-14'), 0, reason: 'closed date');
      expect(e.capacityOn('2026-03-12'), 10);
    });

    test('season days left', () {
      final s = season(target: '2026-03-15');
      expect(s.daysLeft('2026-03-10'), 5);
      expect(s.daysLeft('2026-03-15'), 0);
      expect(s.daysLeft('2026-03-20'), -5);
      expect(s.daysLeft('2026-02-28'), 15, reason: 'across month end');
    });
  });

  group('day loads (E-3)', () {
    test('cumulative capacity versus promises with colour levels', () {
      final e = engine();
      final days = e.days(const [
        WorkLoad('2026-03-12', 28), // cum cap 30 → slack 2 → amber
        WorkLoad('2026-03-15', 50), // total 78 vs cap 60 → red
      ]);
      expect(days, hasLength(6));
      expect(days.first.date, '2026-03-10');
      expect(days.last.date, '2026-03-15');
      expect(days[0].level, LoadLevel.green);
      expect(days[2].cumulativeCapacity, 30);
      expect(days[2].cumulativeDemand, 28);
      expect(days[2].slack, 2);
      expect(days[2].level, LoadLevel.amber);
      expect(days[2].dueUnits, 28);
      expect(days[3].level, LoadLevel.green, reason: 'slack 12 of 40');
      expect(days[5].slack, -18);
      expect(days[5].level, LoadLevel.red);
    });

    test('exactly full is amber, not red', () {
      final days = engine().days(const [WorkLoad('2026-03-12', 30)]);
      expect(days[2].slack, 0);
      expect(days[2].level, LoadLevel.amber);
    });

    test('late orders are due today and can make today red', () {
      final days = engine().days(const [WorkLoad('2026-03-01', 25)]);
      expect(days[0].dueUnits, 25);
      expect(days[0].level, LoadLevel.red);
      expect(days[1].level, LoadLevel.red); // 25 vs 20
      expect(days[2].level, LoadLevel.amber); // 25 vs 30: 17% spare
      expect(days[3].level, LoadLevel.green); // 25 vs 40
    });

    test('closed days are flagged and add no capacity', () {
      final mask = WorkingDays.toggle(WorkingDays.all, 3); // Wednesday off
      final days = engine(mask: mask).days(const []);
      expect(days[1].date, '2026-03-11');
      expect(days[1].isWorkingDay, isFalse);
      expect(days[1].capacityUnits, 0);
      expect(days[1].cumulativeCapacity, 10);
      expect(days[2].cumulativeCapacity, 20);
    });

    test('an empty plan is all green', () {
      expect(
        engine().days(const []).map((d) => d.level),
        everyElement(LoadLevel.green),
      );
    });

    test('target today gives one day; target in the past gives none', () {
      expect(engine(target: today).days(const []), hasLength(1));
      expect(engine(target: '2026-03-01').days(const []), hasLength(1));
    });
  });

  group('room before the target (E-6)', () {
    test('spare capacity by the target date', () {
      final e = engine();
      expect(e.roomUnits(const []), 60);
      expect(e.roomUnits(const [WorkLoad('2026-03-15', 45)]), 15);
      expect(e.roomUnits(const [WorkLoad('2026-03-15', 70)]), -10);
    });

    test('work due after the target does not use up target room... but counts later', () {
      final e = engine();
      // Due 3 days after Eid: the room by Eid counts only what is due by then.
      expect(e.roomUnits(const [WorkLoad('2026-03-18', 25)]), 60);
    });

    test('equals the last day slack', () {
      final e = engine();
      const work = [WorkLoad('2026-03-12', 20), WorkLoad('2026-03-14', 7)];
      expect(e.roomUnits(work), e.days(work).last.slack);
    });
  });

  group('earliestSafeDate (S5-03, E-5)', () {
    test('an empty shop can promise tomorrow', () {
      expect(engine().earliestSafeDate(const [], 1), '2026-03-11');
    });

    test('lead time moves the earliest date', () {
      expect(
        engine().earliestSafeDate(const [], 1, minLeadDays: 3),
        '2026-03-13',
      );
      expect(
        engine().earliestSafeDate(const [], 1, minLeadDays: 0),
        '2026-03-10',
      );
    });

    test('a full book leaves no safe date for the last units (acceptance)', () {
      // 6 working days × 10 = 60 units of capacity by the target day.
      final e = engine();
      const work = [WorkLoad('2026-03-15', 50)];
      expect(e.earliestSafeDate(work, 10), '2026-03-11');
      expect(e.earliestSafeDate(work, 11), isNull);
      expect(e.earliestSafeDate(const [WorkLoad('2026-03-15', 60)], 1), isNull);
    });

    test(
      'is the first day where cumulative capacity covers cumulative demand',
      () {
        final e = engine();
        // 30 units due on the 12th use all capacity up to then.
        const work = [WorkLoad('2026-03-12', 30)];
        expect(e.earliestSafeDate(work, 5), '2026-03-13');
        // A heavier request needs a later day: slack on the 13th is only 10.
        expect(e.earliestSafeDate(work, 12), '2026-03-14');
        expect(e.earliestSafeDate(work, 20), '2026-03-14');
        expect(e.earliestSafeDate(work, 21), '2026-03-15');
        expect(e.earliestSafeDate(work, 31), isNull);
      },
    );

    test('skips days off', () {
      final mask = WorkingDays.toggle(WorkingDays.all, 5); // Friday off
      final e = engine(mask: mask, target: '2026-03-20', now: '2026-03-12');
      // The 13th is a Friday: not offered even though capacity is plentiful.
      expect(e.earliestSafeDate(const [], 1), '2026-03-14');
    });

    test('skips closed dates', () {
      final e = engine(closed: {'2026-03-11'});
      expect(e.earliestSafeDate(const [], 1), '2026-03-12');
    });

    test('late orders push the answer out', () {
      final e = engine();
      const late = [WorkLoad('2026-03-01', 25)];
      // slack: -15, -5, 5 (on the 12th), 15, ...
      expect(e.earliestSafeDate(late, 5), '2026-03-12');
      expect(e.earliestSafeDate(late, 15), '2026-03-13');
    });

    test('work promised beyond the target still constrains', () {
      final e = engine(target: '2026-03-12'); // 3 working days = 30
      // Heavy work due after the target: a promise for the 12th must leave
      // room for it too.
      const work = [WorkLoad('2026-03-14', 45)]; // cap by 14th = 50
      expect(e.earliestSafeDate(work, 5), '2026-03-11');
      expect(e.earliestSafeDate(work, 6), isNull);
    });

    test('nothing is offered when the target is today or past', () {
      expect(engine(target: today).earliestSafeDate(const [], 1), isNull);
      expect(
        engine(target: '2026-03-01').earliestSafeDate(const [], 1),
        isNull,
      );
    });

    test('isDateSafe agrees', () {
      final e = engine();
      const work = [WorkLoad('2026-03-12', 30)];
      expect(e.isDateSafe(work, 5, '2026-03-12'), isFalse);
      expect(e.isDateSafe(work, 5, '2026-03-13'), isTrue);
      expect(e.isDateSafe(const [], 60, '2026-03-15'), isTrue);
      expect(e.isDateSafe(const [], 61, '2026-03-15'), isFalse);
    });
  });

  group('properties (S5-04)', () {
    final random = Random(2026);

    Season randomSeason() {
      var mask = random.nextInt(127) + 1;
      if (random.nextInt(4) == 0) mask = WorkingDays.all;
      final target = DateTime(2026, 3, 10 + random.nextInt(40));
      final closed = <String>{
        for (var i = 0; i < random.nextInt(4); i++)
          Clock.toDateString(DateTime(2026, 3, 10 + random.nextInt(40))),
      };
      return season(
        target: Clock.toDateString(target),
        capacity: 1 + random.nextInt(30),
        mask: mask,
        closed: closed,
      );
    }

    List<WorkLoad> randomWork() => [
      for (var i = 0; i < random.nextInt(12); i++)
        WorkLoad(
          Clock.toDateString(DateTime(2026, 3, 5 + random.nextInt(50))),
          1 + random.nextInt(40),
        ),
    ];

    /// Brute force: is promising [units] on day index [from] OK?
    bool brute(CapacityEngine e, List<WorkLoad> work, int units, int from) {
      var horizon = e.indexOf(e.season.targetDate);
      for (final w in work) {
        horizon = max(horizon, e.indexOf(w.date));
      }
      horizon = max(horizon, from);
      var cap = 0;
      var dem = 0;
      for (var i = 0; i <= horizon; i++) {
        cap += e.capacityOn(e.dateAt(i));
        for (final w in work) {
          if (e.indexOf(w.date) == i) dem += w.units;
        }
        if (i >= from && dem + units > cap) return false;
      }
      return true;
    }

    test('a returned date is safe, working, and the earliest such', () {
      for (var round = 0; round < 400; round++) {
        final s = randomSeason();
        final e = CapacityEngine(season: s, today: today);
        final work = randomWork();
        final units = 1 + random.nextInt(60);
        final lead = random.nextInt(4);
        final date = e.earliestSafeDate(work, units, minLeadDays: lead);
        final last = e.indexOf(s.targetDate);

        if (date != null) {
          final idx = e.indexOf(date);
          expect(e.isWorkingDay(date), isTrue, reason: 'round $round');
          expect(idx, greaterThanOrEqualTo(lead));
          expect(idx, lessThanOrEqualTo(last));
          expect(brute(e, work, units, idx), isTrue, reason: 'round $round');
          for (var i = lead; i < idx; i++) {
            if (!e.isWorkingDay(e.dateAt(i))) continue;
            expect(
              brute(e, work, units, i),
              isFalse,
              reason: 'round $round: day $i should not be safe',
            );
          }
        } else {
          for (var i = lead; i <= last; i++) {
            if (!e.isWorkingDay(e.dateAt(i))) continue;
            expect(
              brute(e, work, units, i),
              isFalse,
              reason: 'round $round: day $i was safe but none returned',
            );
          }
        }
      }
    });

    test('accepting the suggested date never overbooks anything new', () {
      for (var round = 0; round < 300; round++) {
        final s = randomSeason();
        final e = CapacityEngine(season: s, today: today);
        final work = randomWork();
        final before = e.days(work);
        final units = 1 + random.nextInt(30);
        final date = e.earliestSafeDate(work, units);
        if (date == null) continue;
        final after = e.days([...work, WorkLoad(date, units)]);
        final from = e.indexOf(date);
        for (var i = from; i < after.length; i++) {
          // Days that were fine stay fine (not red) from the new date on.
          if (before[i].level != LoadLevel.red) {
            expect(
              after[i].level,
              isNot(LoadLevel.red),
              reason: 'round $round day $i',
            );
          }
          expect(after[i].slack, before[i].slack - units);
        }
        for (var i = 0; i < from && i < after.length; i++) {
          expect(
            after[i].slack,
            before[i].slack,
            reason: 'earlier days unchanged',
          );
        }
      }
    });

    test('more capacity never makes the date later', () {
      for (var round = 0; round < 300; round++) {
        final s = randomSeason();
        final work = randomWork();
        final units = 1 + random.nextInt(40);
        final low = CapacityEngine(
          season: s,
          today: today,
        ).earliestSafeDate(work, units);
        final high = CapacityEngine(
          season: s.copyWith(
            dailyCapacity: s.dailyCapacity + 1 + random.nextInt(10),
          ),
          today: today,
        ).earliestSafeDate(work, units);
        if (low != null) {
          expect(high, isNotNull, reason: 'round $round');
          expect(
            high!.compareTo(low),
            lessThanOrEqualTo(0),
            reason: 'round $round',
          );
        }
      }
    });

    test('more work never makes the date earlier', () {
      for (var round = 0; round < 300; round++) {
        final s = randomSeason();
        final e = CapacityEngine(season: s, today: today);
        final work = randomWork();
        final units = 1 + random.nextInt(30);
        final base = e.earliestSafeDate(work, units);
        final more = e.earliestSafeDate([
          ...work,
          WorkLoad(
            Clock.toDateString(DateTime(2026, 3, 10 + random.nextInt(40))),
            1 + random.nextInt(30),
          ),
        ], units);
        if (base == null) {
          expect(more, isNull, reason: 'round $round');
        } else if (more != null) {
          expect(
            more.compareTo(base),
            greaterThanOrEqualTo(0),
            reason: 'round $round',
          );
        }
      }
    });

    test('a bigger request is never earlier than a smaller one', () {
      for (var round = 0; round < 200; round++) {
        final s = randomSeason();
        final e = CapacityEngine(season: s, today: today);
        final work = randomWork();
        final small = 1 + random.nextInt(20);
        final big = small + 1 + random.nextInt(30);
        final a = e.earliestSafeDate(work, small);
        final b = e.earliestSafeDate(work, big);
        if (a == null) {
          expect(b, isNull);
        } else if (b != null) {
          expect(b.compareTo(a), greaterThanOrEqualTo(0));
        }
      }
    });

    test('the sum of per-day dues equals the work promised by the target', () {
      for (var round = 0; round < 100; round++) {
        final s = randomSeason();
        final e = CapacityEngine(season: s, today: today);
        final work = randomWork();
        final days = e.days(work);
        final expected = work
            .where((w) => e.indexOf(w.date) <= e.indexOf(s.targetDate))
            .fold(0, (a, w) => a + w.units);
        expect(days.fold(0, (a, d) => a + d.dueUnits), expected);
        expect(days.last.cumulativeDemand, expected);
      }
    });
  });

  group('performance (S5-04)', () {
    test('60 days and 2,000 items answer in well under 300 ms', () {
      final random = Random(5);
      final s = season(target: '2026-05-09', capacity: 3000);
      final e = CapacityEngine(season: s, today: today);
      final work = [
        for (var i = 0; i < 2000; i++)
          WorkLoad(
            Clock.toDateString(DateTime(2026, 3, 10 + random.nextInt(60))),
            50 + random.nextInt(200),
          ),
      ];
      // Best of fifteen, so a busy test machine does not fail a fast function.
      var best = 1 << 30;
      late List<DayLoad> days;
      late String? safe;
      late int room;
      for (var run = 0; run < 15; run++) {
        final watch = Stopwatch()..start();
        days = e.days(work);
        safe = e.earliestSafeDate(work, 100);
        room = e.roomUnits(work);
        watch.stop();
        if (watch.elapsedMilliseconds < best) best = watch.elapsedMilliseconds;
      }
      expect(days, hasLength(61));
      expect(best, lessThan(300));
      expect(safe == null || safe.compareTo(today) > 0, isTrue);
      expect(room, days.last.slack);
    });
  });

  group('StageProgress', () {
    test('finished garments need no more capacity', () {
      expect(StageProgress.remainingUnits(100, 'received'), 100);
      expect(StageProgress.remainingUnits(100, 'cut'), 80);
      expect(StageProgress.remainingUnits(250, 'stitching'), 100);
      expect(StageProgress.remainingUnits(100, 'finishing'), 20);
      expect(StageProgress.remainingUnits(100, 'ready'), 0);
      expect(StageProgress.remainingUnits(100, 'delivered'), 0);
    });
  });

  group('WorkingDays', () {
    test('toggle and test weekdays', () {
      var mask = WorkingDays.all;
      expect(WorkingDays.isWorking(mask, 7), isTrue);
      mask = WorkingDays.toggle(mask, 7);
      expect(WorkingDays.isWorking(mask, 7), isFalse);
      expect(WorkingDays.isWorking(mask, 1), isTrue);
      expect(WorkingDays.toggle(mask, 7), WorkingDays.all);
    });
  });
}
