import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';

/// `38½` in inches or `96.5` in cm, with Bangla digits when [bangla].
String formatLength(Length value, MeasureUnit unit, {bool bangla = false}) =>
    unit == MeasureUnit.inch
    ? value.toInchFraction(bangla: bangla)
    : value.toCm(bangla: bangla);

/// Signed difference: `+2`, `-½`, or `0`.
String formatDelta(Length delta, MeasureUnit unit, {bool bangla = false}) {
  if (delta.mm10 == 0) return DigitFormatter.format('0', bangla: bangla);
  final sign = delta.mm10 > 0 ? '+' : '-';
  return '$sign${formatLength(delta.abs, unit, bangla: bangla)}';
}
