import 'package:tailor_khata/core/l10n/digit_formatter.dart';

/// An exact non-negative rational number, used for inch measurements typed as
/// whole numbers, fractions (`1/2`, `½`) or decimals.
class Fraction {
  factory Fraction(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
    }
    if (numerator < 0) {
      throw ArgumentError.value(numerator, 'numerator', 'must be >= 0');
    }
    final divisor = numerator == 0 ? denominator : _gcd(numerator, denominator);
    return Fraction._(numerator ~/ divisor, denominator ~/ divisor);
  }

  const Fraction._(this.numerator, this.denominator);

  factory Fraction.whole(int value) => Fraction(value, 1);

  final int numerator;
  final int denominator;

  static const Map<String, Fraction> _unicode = {
    '½': Fraction._(1, 2),
    '¼': Fraction._(1, 4),
    '¾': Fraction._(3, 4),
    '⅛': Fraction._(1, 8),
    '⅜': Fraction._(3, 8),
    '⅝': Fraction._(5, 8),
    '⅞': Fraction._(7, 8),
    '⅓': Fraction._(1, 3),
    '⅔': Fraction._(2, 3),
  };

  /// Parses user input such as `38`, `38.5`, `38 1/2`, `38½`, `½` or `3/4`.
  ///
  /// Bangla digits are accepted. Returns null when the text is not a valid
  /// non-negative number.
  static Fraction? tryParse(String input) {
    var text = DigitFormatter.toLatin(input).trim();
    if (text.isEmpty) return null;

    var extra = Fraction._(0, 1);
    for (final entry in _unicode.entries) {
      if (text.endsWith(entry.key)) {
        extra = entry.value;
        text = text.substring(0, text.length - entry.key.length).trim();
        if (text.isEmpty) return extra;
        final whole = int.tryParse(text);
        if (whole == null || whole < 0) return null;
        return extra + Fraction.whole(whole);
      }
    }

    final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(text);
    if (mixed != null) {
      final denominator = int.parse(mixed.group(3)!);
      if (denominator == 0) return null;
      return Fraction.whole(int.parse(mixed.group(1)!)) +
          Fraction(int.parse(mixed.group(2)!), denominator);
    }

    final simple = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(text);
    if (simple != null) {
      final denominator = int.parse(simple.group(2)!);
      if (denominator == 0) return null;
      return Fraction(int.parse(simple.group(1)!), denominator);
    }

    final decimal = RegExp(r'^(\d*)\.?(\d*)$').firstMatch(text);
    if (decimal != null) {
      final whole = decimal.group(1)!;
      final fractional = decimal.group(2)!;
      if (whole.isEmpty && fractional.isEmpty) return null;
      if (fractional.length > 6) return null;
      final scale = _pow10(fractional.length);
      final scaled =
          int.parse(whole.isEmpty ? '0' : whole) * scale +
          (fractional.isEmpty ? 0 : int.parse(fractional));
      return Fraction(scaled, scale);
    }
    return null;
  }

  Fraction operator +(Fraction other) => Fraction(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  double toDouble() => numerator / denominator;

  @override
  bool operator ==(Object other) =>
      other is Fraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';

  static int _gcd(int a, int b) {
    var x = a;
    var y = b;
    while (y != 0) {
      final t = y;
      y = x % y;
      x = t;
    }
    return x;
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
