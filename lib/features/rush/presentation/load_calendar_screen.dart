import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/presentation/rush_labels.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Orders due on one calendar day, for the day sheet.
final dayOrdersProvider = FutureProvider.autoDispose
    .family<List<OrderSummary>, String>((ref, date) {
      // Refresh when any order changes.
      ref.watch(rushItemsProvider);
      return ref
          .watch(orderRepositoryProvider)
          .deliveriesPage(from: date, to: date, limit: 200);
    });

Color levelColor(LoadLevel level, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (level) {
    LoadLevel.green => dark ? const Color(0xFF1B5E20) : const Color(0xFFC8E6C9),
    LoadLevel.amber => dark ? const Color(0xFF8D5A00) : const Color(0xFFFFE0B2),
    LoadLevel.red => dark ? const Color(0xFF8E1B1B) : const Color(0xFFFFCDD2),
  };
}

/// Each day from today to the deadline coloured by how full the plan is, with
/// the number of garments due that day (E-3). Tap a day for its orders.
class LoadCalendarScreen extends ConsumerWidget {
  const LoadCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final plan = ref.watch(rushPlanProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.calTitle)),
      body: plan == null
          ? (ref.watch(activeSeasonProvider).value == null
                ? EmptyState(
                    icon: Icons.calendar_month_outlined,
                    title: l10n.rushEmptyTitle,
                    body: l10n.rushEmptyBody,
                  )
                : const Center(child: CircularProgressIndicator()))
          : _CalendarBody(plan: plan),
    );
  }
}

class _CalendarBody extends ConsumerWidget {
  const _CalendarBody({required this.plan});

  final RushPlan plan;

  /// Saturday-first column of a date (Saturday = 0 … Friday = 6).
  static int _column(DateTime d) => (d.weekday + 1) % 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final theme = Theme.of(context);
    final byDate = {for (final d in plan.days) d.date: d};

    final first = Clock.parseDate(plan.days.first.date);
    final last = Clock.parseDate(plan.days.last.date);
    // Start on the Saturday on or before the first day.
    final start = DateTime(first.year, first.month, first.day - _column(first));

    final rows = <Widget>[];
    String? month;
    for (
      var week = start;
      !week.isAfter(last);
      week = DateTime(week.year, week.month, week.day + 7)
    ) {
      final firstInRow =
          [
            for (var i = 0; i < 7; i++)
              DateTime(week.year, week.month, week.day + i),
          ].firstWhere(
            (d) => byDate.containsKey(Clock.toDateString(d)),
            orElse: () => week,
          );
      final label = DateFormat('MMMM y', lang).format(firstInRow);
      if (label != month) {
        month = label;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              DigitFormatter.format(label, bangla: bangla),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayCell(
                    day:
                        byDate[Clock.toDateString(
                          DateTime(week.year, week.month, week.day + i),
                        )],
                    date: DateTime(week.year, week.month, week.day + i),
                    bangla: bangla,
                    onTap: (day) => _openDay(context, ref, day),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget legend(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
    final brightness = theme.brightness;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              legend(
                levelColor(LoadLevel.green, brightness),
                l10n.calLegendGreen,
              ),
              legend(
                levelColor(LoadLevel.amber, brightness),
                l10n.calLegendAmber,
              ),
              legend(levelColor(LoadLevel.red, brightness), l10n.calLegendRed),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            l10n.calCapacityDay(
              formatGarments(plan.season.dailyCapacity, bangla: bangla),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          child: Row(
            children: [
              for (final weekday in const [6, 7, 1, 2, 3, 4, 5])
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayLabel(l10n, weekday),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ...rows,
      ],
    );
  }

  void _openDay(BuildContext context, WidgetRef ref, DayLoad day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DaySheet(day: day),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.bangla,
    required this.onTap,
  });

  final DayLoad? day;
  final DateTime date;
  final bool bangla;
  final void Function(DayLoad) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = day;
    if (d == null) return const SizedBox(height: 64);
    final closed = !d.isWorkingDay;
    final background = closed
        ? theme.colorScheme.surfaceContainerHighest
        : levelColor(d.level, theme.brightness);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        key: ValueKey('cal-${d.date}'),
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(d),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DigitFormatter.format('${date.day}', bangla: bangla),
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  if (d.dueUnits > 0)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        formatGarments(d.dueUnits, bangla: bangla),
                        key: ValueKey('cal-due-${d.date}'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day});

  final DayLoad day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final theme = Theme.of(context);
    final orders = ref.watch(dayOrdersProvider(day.date)).value ?? const [];
    final spare = day.slack;
    final spareText = spare >= 0
        ? l10n.calSpare(spare ~/ 100)
        : l10n.calOverBy(((-spare) / 100).ceil());

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              DigitFormatter.format(
                l10n.calDueOn(formatStoredDate(day.date, lang)),
                bangla: bangla,
              ),
              key: const ValueKey('day-sheet-title'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              [
                if (!day.isWorkingDay) l10n.calClosed,
                DigitFormatter.format(spareText, bangla: bangla),
              ].join(' · '),
              key: const ValueKey('day-sheet-spare'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: spare < 0 ? theme.colorScheme.error : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.calNoOrders, textAlign: TextAlign.center),
            )
          else
            for (final o in orders) OrderTile(summary: o),
        ],
      ),
    );
  }
}
