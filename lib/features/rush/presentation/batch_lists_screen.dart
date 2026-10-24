import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Garments grouped by stage and type ("37 Panjabi to cut"), with a one-tap
/// move of a whole group to the next stage (E-8).
class BatchListsScreen extends ConsumerStatefulWidget {
  const BatchListsScreen({super.key});

  @override
  ConsumerState<BatchListsScreen> createState() => _BatchListsScreenState();
}

class _BatchListsScreenState extends ConsumerState<BatchListsScreen> {
  bool _onlyTarget = false;

  static const _stages = [
    OrderStatus.received,
    OrderStatus.cut,
    OrderStatus.stitching,
    OrderStatus.finishing,
    OrderStatus.ready,
  ];

  Future<void> _move({
    required String garmentId,
    required String garmentName,
    required OrderStatus from,
    required OrderStatus to,
    required int count,
    required String? toDate,
  }) async {
    final l10n = AppL10n.of(context);
    final bangla = ref.read(useBanglaDigitsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          DigitFormatter.format(
            l10n.batchConfirmTitle(count, garmentName, to.label(l10n)),
            bangla: bangla,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            key: const ValueKey('batch-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = await ref
        .read(rushRepositoryProvider)
        .itemIds(garmentId, from, toDate: toDate);
    final moved = await ref.read(orderRepositoryProvider).moveItems(ids, to);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          DigitFormatter.format(l10n.batchMoved(moved), bangla: bangla),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final theme = Theme.of(context);
    final season = ref.watch(activeSeasonProvider).value;
    final toDate = _onlyTarget ? season?.targetDate : null;
    final counts = ref.watch(stageCountsProvider(toDate)).value ?? const [];
    final garments = ref.watch(garmentsProvider).value ?? const [];
    String n(int v) => DigitFormatter.format('$v', bangla: bangla);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.batchTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (season != null)
            SwitchListTile(
              key: const ValueKey('batch-only-target'),
              title: Text(
                DigitFormatter.format(
                  l10n.batchOnlyDueByTarget(
                    formatStoredDate(season.targetDate, lang),
                  ),
                  bangla: bangla,
                ),
              ),
              value: _onlyTarget,
              onChanged: (v) => setState(() => _onlyTarget = v),
            ),
          if (counts.isEmpty)
            SizedBox(
              height: 360,
              child: EmptyState(
                icon: Icons.checklist_outlined,
                title: l10n.batchNothing,
                body: l10n.batchNothingBody,
              ),
            ),
          for (final stage in _stages)
            if (counts.any((c) => c.status == stage)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Text(
                  '${stage.label(l10n)} · ${n(counts.where((c) => c.status == stage).fold(0, (a, c) => a + c.garments))}',
                  key: ValueKey('batch-stage-${stage.name}'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final c in counts.where((c) => c.status == stage))
                Builder(
                  builder: (context) {
                    final garment = garments
                        .where((g) => g.id == c.garmentTypeId)
                        .firstOrNull;
                    final name = garment?.label(lang) ?? '';
                    final next = stage.next;
                    return Padding(
                      key: ValueKey('batch-${stage.name}-${garment?.key}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: theme.textTheme.titleMedium),
                                Text(
                                  DigitFormatter.format(
                                    l10n.batchGarmentsAt(c.garments),
                                    bangla: bangla,
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          if (next != null && next != OrderStatus.delivered)
                            Flexible(
                              child: FilledButton.tonal(
                                key: ValueKey(
                                  'batch-move-${stage.name}-${garment?.key}',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () => _move(
                                  garmentId: c.garmentTypeId,
                                  garmentName: name,
                                  from: stage,
                                  to: next,
                                  count: c.garments,
                                  toDate: toDate,
                                ),
                                child: Text(
                                  l10n.batchMove(next.label(l10n)),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
        ],
      ),
    );
  }
}
