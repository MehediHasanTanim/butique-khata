import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// One point of a trend line.
class TrendPoint {
  const TrendPoint({required this.date, required this.value});

  final String date;

  /// Inches or centimetres, as a double for plotting only.
  final double value;
}

/// Builds the plot data for [fieldKey] from [versions] (any order): oldest
/// first, error versions excluded, and only versions that have the field.
List<TrendPoint> trendPoints(
  List<Measurement> versions,
  String fieldKey,
  MeasureUnit unit,
) {
  final sorted =
      versions
          .where(
            (m) =>
                m.status == MeasurementStatus.active &&
                m.values.containsKey(fieldKey),
          )
          .toList()
        ..sort((a, b) {
          final byDate = a.takenOn.compareTo(b.takenOn);
          return byDate != 0 ? byDate : a.version.compareTo(b.version);
        });
  return [
    for (final m in sorted)
      TrendPoint(
        date: m.takenOn,
        value: unit == MeasureUnit.inch
            ? m.values[fieldKey]!.inches
            : m.values[fieldKey]!.mm10 / 100,
      ),
  ];
}

/// Line chart of one field over time (H-4).
class MeasurementTrendScreen extends ConsumerStatefulWidget {
  const MeasurementTrendScreen({
    required this.customerId,
    required this.garmentKey,
    super.key,
  });

  final String customerId;
  final String garmentKey;

  @override
  ConsumerState<MeasurementTrendScreen> createState() =>
      _MeasurementTrendScreenState();
}

class _MeasurementTrendScreenState
    extends ConsumerState<MeasurementTrendScreen> {
  String? _fieldKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final garment = ref.watch(garmentByKeyProvider(widget.garmentKey)).value;
    if (garment == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.trendTitle)),
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
      appBar: AppBar(title: Text(l10n.trendTitle)),
      body: versions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
        data: (list) {
          // Fields measured at least twice.
          final fields = [
            for (final f in garment.fields)
              if (list.where((m) => m.values.containsKey(f.key)).length >= 2) f,
          ];
          if (fields.isEmpty) {
            return EmptyState(
              icon: Icons.show_chart,
              title: l10n.trendNeedTwo,
              body: '',
            );
          }
          final selected = fields.firstWhere(
            (f) => f.key == _fieldKey,
            orElse: () => fields.first,
          );
          final unit = list.first.unit;
          final points = trendPoints(list, selected.key, unit);
          final first = Clock.parseDate(points.first.date);
          double x(TrendPoint p) =>
              Clock.parseDate(p.date).difference(first).inDays.toDouble();
          final spots = [for (final p in points) FlSpot(x(p), p.value)];
          final minY = points
              .map((p) => p.value)
              .reduce((a, b) => a < b ? a : b);
          final maxY = points
              .map((p) => p.value)
              .reduce((a, b) => a > b ? a : b);
          final pad = ((maxY - minY) * 0.3).clamp(1.0, 100.0);
          final maxX = spots.last.x == 0 ? 1.0 : spots.last.x;
          final scheme = Theme.of(context).colorScheme;

          String valueText(double v) => formatLength(
            unit == MeasureUnit.inch
                ? Length.fromInches(_toFraction(v))
                : Length.fromMm10((v * 100).round()),
            unit,
            bangla: bangla,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final f in fields)
                    ChoiceChip(
                      key: ValueKey('trend-${f.key}'),
                      label: Text(f.label(lang)),
                      selected: f.key == selected.key,
                      onSelected: (_) => setState(() => _fieldKey = f.key),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 260,
                child: LineChart(
                  key: const ValueKey('trend-chart'),
                  LineChartData(
                    minY: minY - pad,
                    maxY: maxY + pad,
                    minX: 0,
                    maxX: maxX,
                    gridData: const FlGridData(drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (value, meta) => Text(
                            valueText(value),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: maxX,
                          getTitlesWidget: (value, meta) {
                            final date = Clock.toDateString(
                              first.add(Duration(days: value.round())),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                formatStoredDate(date, lang),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touched) => [
                          for (final t in touched)
                            LineTooltipItem(
                              '${valueText(t.y)}\n${formatStoredDate(Clock.toDateString(first.add(Duration(days: t.x.round()))), lang)}',
                              TextStyle(color: scheme.onInverseSurface),
                            ),
                        ],
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: false,
                        barWidth: 3,
                        color: scheme.primary,
                        dotData: const FlDotData(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Nearest eighth, for axis labels only.
  Fraction _toFraction(double inches) =>
      Fraction((inches * 8).round().clamp(0, 100000), 8);
}
