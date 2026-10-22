import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_diff.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Side-by-side comparison of any two versions with the differences
/// highlighted (H-3).
class MeasurementCompareScreen extends ConsumerStatefulWidget {
  const MeasurementCompareScreen({
    required this.customerId,
    required this.garmentKey,
    this.earlierId,
    this.laterId,
    super.key,
  });

  final String customerId;
  final String garmentKey;
  final String? earlierId;
  final String? laterId;

  @override
  ConsumerState<MeasurementCompareScreen> createState() =>
      _MeasurementCompareScreenState();
}

class _MeasurementCompareScreenState
    extends ConsumerState<MeasurementCompareScreen> {
  String? _a;
  String? _b;
  bool _changedOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final garment = ref.watch(garmentByKeyProvider(widget.garmentKey)).value;

    if (garment == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.compareTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final versions = ref.watch(
      measurementVersionsProvider((
        customerId: widget.customerId,
        garmentTypeId: garment.id,
        includeErrors: false,
      )),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.compareTitle)),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
        data: (list) {
          if (list.length < 2) {
            return EmptyState(
              icon: Icons.compare_arrows,
              title: l10n.compareNeedTwo,
              body: '',
            );
          }
          Measurement? find(String? id) =>
              list.where((m) => m.id == id).firstOrNull;
          // Default: latest vs the one before it (list is newest first).
          final later = find(_b ?? widget.laterId) ?? list[0];
          final earlier =
              find(_a ?? widget.earlierId) ??
              list.where((m) => m.id != later.id).first;

          final deltas = diffMeasurements(
            earlier.values,
            later.values,
            order: garment.fields.map((f) => f.key).toList(),
          );
          final shown = _changedOnly
              ? deltas.where((d) => d.isChange).toList()
              : deltas;
          final labelOf = {
            for (final f in garment.fields) f.key: f.label(lang),
          };
          final unit = later.unit;

          String versionText(Measurement m) => DigitFormatter.format(
            l10n.versionOn(m.version, formatStoredDate(m.takenOn, lang)),
            bangla: bangla,
          );

          Widget picker(
            String label,
            Measurement current,
            ValueChanged<String> onChanged,
            Key key,
          ) {
            return Expanded(
              child: DropdownButtonFormField<String>(
                key: key,
                initialValue: current.id,
                isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (final m in list)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(
                        versionText(m),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onChanged(id);
                },
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    picker(
                      l10n.compareEarlier,
                      earlier,
                      (id) => setState(() => _a = id),
                      const ValueKey('pick-earlier'),
                    ),
                    const SizedBox(width: 8),
                    picker(
                      l10n.compareLater,
                      later,
                      (id) => setState(() => _b = id),
                      const ValueKey('pick-later'),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                title: Text(l10n.compareChangedOnly),
                value: _changedOnly,
                onChanged: (value) => setState(() => _changedOnly = value),
              ),
              const Divider(height: 1),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: Icons.check_circle_outline,
                        title: l10n.compareNoChanges,
                        body: '',
                      )
                    : ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final d = shown[index];
                          return _CompareRow(
                            key: ValueKey('cmp-${d.key}'),
                            label: labelOf[d.key] ?? d.key,
                            delta: d,
                            unit: unit,
                            bangla: bangla,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.delta,
    required this.unit,
    required this.bangla,
    super.key,
  });

  final String label;
  final FieldDelta delta;
  final MeasureUnit unit;
  final bool bangla;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String show(Length? v) =>
        v == null ? '—' : formatLength(v, unit, bangla: bangla);

    final changed = delta.isChange;
    final (String? tag, Color? tagColor) = switch (delta.kind) {
      DeltaKind.added => (l10n.compareAdded, scheme.primary),
      DeltaKind.removed => (l10n.compareRemoved, scheme.error),
      DeltaKind.changed => (
        formatDelta(delta.delta!, unit, bangla: bangla),
        delta.delta!.mm10 > 0 ? scheme.primary : scheme.error,
      ),
      DeltaKind.same => (null, null),
    };

    return Container(
      color: changed ? scheme.tertiaryContainer.withValues(alpha: 0.45) : null,
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: changed ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              show(delta.before),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 16),
          ),
          Expanded(
            flex: 2,
            child: Text(
              show(delta.after),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: tag == null
                ? null
                : Text(
                    tag,
                    key: ValueKey('delta-${delta.key}'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tagColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
