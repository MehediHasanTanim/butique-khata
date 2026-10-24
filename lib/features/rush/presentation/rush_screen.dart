import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/rush/domain/capacity_engine.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Eid-rush overview: countdown, how full the plan is, garments by stage,
/// and the planning tools (E-1, E-2, E-6).
class RushScreen extends ConsumerWidget {
  const RushScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final season = ref.watch(activeSeasonProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rushTitle),
        actions: [
          if (season.value != null)
            IconButton(
              key: const ValueKey('rush-edit'),
              tooltip: l10n.rushEditSeason,
              icon: const Icon(Icons.tune),
              onPressed: () =>
                  context.push(AppRoutes.rushSetup(seasonId: season.value!.id)),
            ),
        ],
      ),
      body: season.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
        data: (value) => value == null
            ? EmptyState(
                icon: Icons.local_fire_department_outlined,
                title: l10n.rushEmptyTitle,
                body: l10n.rushEmptyBody,
                action: PrimaryButton(
                  key: const ValueKey('rush-setup'),
                  label: l10n.rushSetupButton,
                  icon: Icons.add,
                  onPressed: () => context.push(AppRoutes.rushSetup()),
                ),
              )
            : const _RushBoard(),
      ),
    );
  }
}

class _RushBoard extends ConsumerWidget {
  const _RushBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final plan = ref.watch(rushPlanProvider);
    if (plan == null) return const Center(child: CircularProgressIndicator());

    final season = plan.season;
    final counts =
        ref.watch(stageCountsProvider(season.targetDate)).value ?? const [];
    int garmentsAt(OrderStatus s) =>
        counts.where((c) => c.status == s).fold(0, (a, c) => a + c.garments);

    final last = plan.days.isEmpty ? null : plan.days.last;
    final used = last?.cumulativeDemand ?? 0;
    final total = last?.cumulativeCapacity ?? 0;
    final room = plan.roomUnits;
    final level = last?.level ?? LoadLevel.green;
    final color = switch (level) {
      LoadLevel.green => const Color(0xFF2E7D32),
      LoadLevel.amber => const Color(0xFFEF6C00),
      LoadLevel.red => theme.colorScheme.error,
    };
    String n(int v) => DigitFormatter.format('$v', bangla: bangla);

    final roomText = room >= 100
        ? l10n.rushRoom(room ~/ 100)
        : room >= 0
        ? l10n.rushFull
        : l10n.rushOver(((-room) / 100).ceil());

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(season.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  DigitFormatter.format(
                    l10n.rushDaysLeft(plan.daysLeft),
                    bangla: bangla,
                  ),
                  key: const ValueKey('rush-days-left'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  DigitFormatter.format(
                    l10n.rushReadyBy(formatStoredDate(season.targetDate, lang)),
                    bangla: bangla,
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DigitFormatter.format(roomText, bangla: bangla),
                  key: const ValueKey('rush-room'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: total == 0 ? 1 : (used / total).clamp(0, 1).toDouble(),
                  minHeight: 10,
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.rushCapacityLine(
                    DigitFormatter.format(
                      (used / 100).toStringAsFixed(0),
                      bangla: bangla,
                    ),
                    DigitFormatter.format(
                      (total / 100).toStringAsFixed(0),
                      bangla: bangla,
                    ),
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SectionHeader(l10n.rushByStage),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [
                OrderStatus.received,
                OrderStatus.cut,
                OrderStatus.stitching,
                OrderStatus.finishing,
                OrderStatus.ready,
              ])
                Chip(
                  key: ValueKey('stage-${s.name}'),
                  label: Text('${s.label(l10n)}  ${n(garmentsAt(s))}'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            l10n
                .rushNotCut(garmentsAt(OrderStatus.received))
                .replaceAllMapped(
                  RegExp(r'\d+'),
                  (m) => DigitFormatter.format(m[0]!, bangla: bangla),
                ),
            key: const ValueKey('rush-not-cut'),
            style: theme.textTheme.titleMedium,
          ),
        ),
        SectionHeader(l10n.rushTools),
        _ToolTile(
          keyName: 'rush-open-calendar',
          icon: Icons.calendar_month_outlined,
          title: l10n.rushOpenCalendar,
          subtitle: l10n.rushOpenCalendarSub,
          onTap: () => context.push(AppRoutes.rushCalendar),
        ),
        _ToolTile(
          keyName: 'rush-open-batches',
          icon: Icons.checklist_outlined,
          title: l10n.rushOpenBatches,
          subtitle: l10n.rushOpenBatchesSub,
          onTap: () => context.push(AppRoutes.rushBatches),
        ),
        _ToolTile(
          keyName: 'rush-open-list',
          icon: Icons.format_list_numbered,
          title: l10n.rushOpenList,
          subtitle: l10n.rushOpenListSub,
          onTap: () => context.push(AppRoutes.rushList),
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey(keyName),
    minTileHeight: 64,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
