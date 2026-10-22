import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_diff.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Timeline of every saved version of one garment for one customer (H-2).
class MeasurementHistoryScreen extends ConsumerStatefulWidget {
  const MeasurementHistoryScreen({
    required this.customerId,
    required this.garmentKey,
    super.key,
  });

  final String customerId;
  final String garmentKey;

  @override
  ConsumerState<MeasurementHistoryScreen> createState() =>
      _MeasurementHistoryScreenState();
}

class _MeasurementHistoryScreenState
    extends ConsumerState<MeasurementHistoryScreen> {
  bool _includeErrors = false;

  Future<void> _markError(Measurement m) async {
    final l10n = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.markErrorTitle),
        content: Text(l10n.markErrorBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionConfirm),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(measurementRepositoryProvider).markError(m.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final garmentAsync = ref.watch(garmentByKeyProvider(widget.garmentKey));
    final garment = garmentAsync.value;

    if (garment == null) {
      return Scaffold(
        appBar: AppBar(),
        body: garmentAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(child: Text(l10n.errorGenericTitle)),
      );
    }

    final versions = ref.watch(
      measurementVersionsProvider((
        customerId: widget.customerId,
        garmentTypeId: garment.id,
        includeErrors: _includeErrors,
      )),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle(garment.label(lang))),
        actions: [
          IconButton(
            tooltip: l10n.compareTitle,
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => context.push(
              AppRoutes.compare(widget.customerId, widget.garmentKey),
            ),
          ),
          IconButton(
            tooltip: l10n.trendTitle,
            icon: const Icon(Icons.show_chart),
            onPressed: () => context.push(
              AppRoutes.trend(widget.customerId, widget.garmentKey),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(
          AppRoutes.measure(widget.customerId, widget.garmentKey),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.newMeasurements),
      ),
      body: Column(
        children: [
          SwitchListTile(
            dense: true,
            title: Text(l10n.includeErrors),
            value: _includeErrors,
            onChanged: (value) => setState(() => _includeErrors = value),
          ),
          Expanded(
            child: versions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.history,
                    title: l10n.historyEmpty,
                    body: '',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final m = list[index];
                    final previous = list
                        .skip(index + 1)
                        .where((o) => o.status == MeasurementStatus.active)
                        .firstOrNull;
                    final isLatest =
                        m.status == MeasurementStatus.active &&
                        list
                            .take(index)
                            .every((o) => o.status != MeasurementStatus.active);
                    return _VersionCard(
                      key: ValueKey('version-${m.id}'),
                      measurement: m,
                      previous: previous,
                      garment: garment,
                      isLatest: isLatest,
                      onCompareWithPrevious: previous == null
                          ? null
                          : () => context.push(
                              AppRoutes.compare(
                                widget.customerId,
                                widget.garmentKey,
                                earlierId: previous.id,
                                laterId: m.id,
                              ),
                            ),
                      onMarkError: () => _markError(m),
                      onRestore: () =>
                          ref.read(measurementRepositoryProvider).restore(m.id),
                      onFit: (outcome) => ref
                          .read(measurementRepositoryProvider)
                          .setFitOutcome(m.id, outcome),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _Action { compare, fitConfirmed, fitAltered, fitClear, markError, restore }

class _VersionCard extends ConsumerWidget {
  const _VersionCard({
    required this.measurement,
    required this.previous,
    required this.garment,
    required this.isLatest,
    required this.onCompareWithPrevious,
    required this.onMarkError,
    required this.onRestore,
    required this.onFit,
    super.key,
  });

  final Measurement measurement;
  final Measurement? previous;
  final GarmentInfo garment;
  final bool isLatest;
  final VoidCallback? onCompareWithPrevious;
  final VoidCallback onMarkError;
  final VoidCallback onRestore;
  final ValueChanged<FitOutcome?> onFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final isError = measurement.status == MeasurementStatus.error;
    final unit = measurement.unit;

    final order = garment.fields.map((f) => f.key).toList();
    final labelOf = {for (final f in garment.fields) f.key: f.label(lang)};

    // Summary of what changed versus the previous active version.
    String summary;
    Widget? biggest;
    if (previous == null) {
      summary = l10n.firstEntry;
    } else {
      final changes = diffMeasurements(
        previous!.values,
        measurement.values,
        order: order,
      ).where((d) => d.isChange).toList();
      if (changes.isEmpty) {
        summary = l10n.noChangeFromPrevious;
      } else {
        summary = DigitFormatter.format(
          l10n.changedFromPrevious(changes.length),
          bangla: bangla,
        );
        final numeric = changes.where((d) => d.delta != null).toList()
          ..sort((a, b) => b.delta!.abs.mm10.compareTo(a.delta!.abs.mm10));
        if (numeric.isNotEmpty) {
          final top = numeric.first;
          biggest = Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              l10n.largestChange(
                labelOf[top.key] ?? top.key,
                formatDelta(top.delta!, unit, bangla: bangla),
              ),
            ),
          );
        }
      }
    }

    final fitLabel = switch (measurement.fitOutcome) {
      FitOutcome.confirmed => l10n.fitConfirmed,
      FitOutcome.altered => l10n.fitAltered,
      null => null,
    };

    final shown = garment.fields.where(
      (f) => measurement.values.containsKey(f.key),
    );

    return Opacity(
      opacity: isError ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DigitFormatter.format(
                        l10n.versionOn(
                          measurement.version,
                          formatStoredDate(measurement.takenOn, lang),
                        ),
                        bangla: bangla,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<_Action>(
                    key: ValueKey('menu-${measurement.id}'),
                    onSelected: (action) {
                      switch (action) {
                        case _Action.compare:
                          onCompareWithPrevious?.call();
                        case _Action.fitConfirmed:
                          onFit(FitOutcome.confirmed);
                        case _Action.fitAltered:
                          onFit(FitOutcome.altered);
                        case _Action.fitClear:
                          onFit(null);
                        case _Action.markError:
                          onMarkError();
                        case _Action.restore:
                          onRestore();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onCompareWithPrevious != null)
                        PopupMenuItem(
                          value: _Action.compare,
                          child: Text(l10n.compareWithPrevious),
                        ),
                      if (!isError) ...[
                        PopupMenuItem(
                          value: _Action.fitConfirmed,
                          child: Text(l10n.fitConfirmed),
                        ),
                        PopupMenuItem(
                          value: _Action.fitAltered,
                          child: Text(l10n.fitAltered),
                        ),
                        if (measurement.fitOutcome != null)
                          PopupMenuItem(
                            value: _Action.fitClear,
                            child: Text(l10n.fitClear),
                          ),
                        PopupMenuItem(
                          value: _Action.markError,
                          child: Text(l10n.markError),
                        ),
                      ] else
                        PopupMenuItem(
                          value: _Action.restore,
                          child: Text(l10n.restoreVersion),
                        ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  if (isLatest)
                    _Badge(l10n.versionLabelLatest, scheme.primaryContainer),
                  if (isError) _Badge(l10n.errorBadge, scheme.errorContainer),
                  if (fitLabel != null)
                    _Badge(
                      fitLabel,
                      measurement.fitOutcome == FitOutcome.confirmed
                          ? const Color(0xFFC8E6C9)
                          : scheme.tertiaryContainer,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              ?biggest,
              if (measurement.note != null && measurement.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    measurement.note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final f in shown)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${f.label(lang)} '
                          '${formatLength(measurement.values[f.key]!, unit, bangla: bangla)}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
