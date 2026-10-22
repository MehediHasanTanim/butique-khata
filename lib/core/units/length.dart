import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/units/fraction.dart';

/// A measured length stored as an integer count of 0.1 mm (TD §4.1, §5.3).
///
/// 1 inch = 254 units, so inch fractions and centimetres are both exact and
/// no floating-point comparison is ever needed. Display rounding never
/// changes the stored value.
class Length implements Comparable<Length> {
  const Length.fromMm10(this.mm10);

  /// Builds a length from an exact inch [fraction] (e.g. `38 1/2`).
  factory Length.fromInches(Fraction fraction) => Length.fromMm10(
    _roundDiv(fraction.numerator * mm10PerInch, fraction.denominator),
  );

  /// Builds a length from centimetres given as tenths of a centimetre
  /// (`965` → 96.5 cm). 1 cm = 100 units.
  const Length.fromCmTenths(int tenths) : mm10 = tenths * 10;

  static const int mm10PerInch = 254;
  static const Length zero = Length.fromMm10(0);

  final int mm10;

  Length operator +(Length other) => Length.fromMm10(mm10 + other.mm10);
  Length operator -(Length other) => Length.fromMm10(mm10 - other.mm10);
  bool operator <(Length other) => mm10 < other.mm10;
  bool operator >(Length other) => mm10 > other.mm10;
  Length get abs => Length.fromMm10(mm10.abs());

  /// Whole eighths of an inch, rounded to the nearest (for display).
  int _roundedParts(int denominator) =>
      _roundDiv(mm10.abs() * denominator, mm10PerInch);

  /// Formats as inches rounded to the nearest 1/[denominator], using vulgar
  /// fraction glyphs where one exists: `38½`, `9¼`, `40`.
  ///
  /// [denominator] must be a power of two between 1 and 16.
  String toInchFraction({int denominator = 8, bool bangla = false}) {
    if (denominator < 1 ||
        denominator > 16 ||
        denominator & (denominator - 1) != 0) {
      throw ArgumentError.value(denominator, 'denominator');
    }
    final parts = _roundedParts(denominator);
    final whole = parts ~/ denominator;
    final fraction = Fraction(parts % denominator, denominator);
    final sign = mm10 < 0 && parts != 0 ? '-' : '';
    final fractionText = fraction.numerator == 0
        ? ''
        : _fractionGlyph(fraction);
    final wholeText = (whole == 0 && fractionText.isNotEmpty)
        ? ''
        : whole.toString();
    final text =
        '$sign${DigitFormatter.format(wholeText, bangla: bangla)}$fractionText';
    return text.isEmpty ? DigitFormatter.format('0', bangla: bangla) : text;
  }

  /// Formats as centimetres with [decimals] decimal places (0 or 1 are exact).
  String toCm({int decimals = 1, bool bangla = false}) {
    final value = (mm10 / 100).toStringAsFixed(decimals);
    return DigitFormatter.format(value, bangla: bangla);
  }

  /// Inches as a double, for charts only. Never use for comparison.
  double get inches => mm10 / mm10PerInch;

  @override
  int compareTo(Length other) => mm10.compareTo(other.mm10);

  @override
  bool operator ==(Object other) => other is Length && other.mm10 == mm10;

  @override
  int get hashCode => mm10.hashCode;

  @override
  String toString() => 'Length($mm10 x0.1mm)';

  static int _roundDiv(int numerator, int denominator) =>
      (numerator * 2 + denominator) ~/ (denominator * 2);

  static String _fractionGlyph(Fraction fraction) {
    const glyphs = {
      '1/2': '½',
      '1/4': '¼',
      '3/4': '¾',
      '1/8': '⅛',
      '3/8': '⅜',
      '5/8': '⅝',
      '7/8': '⅞',
    };
    return glyphs[fraction.toString()] ??
        ' ${fraction.numerator}/${fraction.denominator}';
  }
}
