import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';

/// The number a tailor is currently typing on the measurement keypad (M-2).
///
/// Immutable; every key returns a new value. Rules:
/// * inches: up to 3 whole digits, then either a decimal (2 places) or one
///   fraction key (⅛ ¼ ⅜ ½ ⅝ ¾ ⅞), which ends the number;
/// * centimetres: up to 3 whole digits and one decimal place; no fractions.
class MeasurementInput {
  const MeasurementInput({
    required this.unit,
    this.whole = '',
    this.decimals,
    this.eighths = 0,
  });

  const MeasurementInput.empty(MeasureUnit unit) : this(unit: unit);

  static const int maxWholeDigits = 3;

  final MeasureUnit unit;
  final String whole;

  /// Digits after the decimal point; null when no point was typed.
  final String? decimals;

  /// Fraction in eighths (0 = none, 4 = ½).
  final int eighths;

  bool get isEmpty => whole.isEmpty && decimals == null && eighths == 0;

  bool get canAddFraction =>
      unit == MeasureUnit.inch && decimals == null && eighths == 0;

  bool get canAddDecimal => decimals == null && eighths == 0;

  int get _maxDecimals => unit == MeasureUnit.inch ? 2 : 1;

  /// True when typing more would not change the result: a fraction was
  /// entered, or the last allowed decimal digit is in.
  bool get isComplete =>
      eighths != 0 || (decimals != null && decimals!.length >= _maxDecimals);

  MeasurementInput digit(int d) {
    assert(d >= 0 && d <= 9);
    if (eighths != 0) return this;
    final next = d.toString();
    if (decimals != null) {
      if (decimals!.length >= _maxDecimals) return this;
      return _copy(decimals: decimals! + next);
    }
    if (whole == '0') return _copy(whole: next);
    if (whole.length >= maxWholeDigits) return this;
    return _copy(whole: whole + next);
  }

  MeasurementInput decimalPoint() {
    if (!canAddDecimal) return this;
    return _copy(whole: whole.isEmpty ? '0' : whole, decimals: '');
  }

  /// Sets the fraction in [eighthsValue] eighths (1–7). Ignored in cm mode.
  MeasurementInput fraction(int eighthsValue) {
    assert(eighthsValue >= 1 && eighthsValue <= 7);
    if (!canAddFraction) return this;
    return _copy(eighths: eighthsValue);
  }

  MeasurementInput backspace() {
    if (eighths != 0) return _copy(eighths: 0);
    if (decimals != null) {
      return decimals!.isEmpty
          ? MeasurementInput(unit: unit, whole: whole)
          : _copy(decimals: decimals!.substring(0, decimals!.length - 1));
    }
    if (whole.isEmpty) return this;
    return _copy(whole: whole.substring(0, whole.length - 1));
  }

  /// The typed value, or null when nothing has been typed.
  Length? get length {
    if (isEmpty) return null;
    final w = int.parse(whole.isEmpty ? '0' : whole);
    if (unit == MeasureUnit.cm) {
      final tenth = (decimals == null || decimals!.isEmpty)
          ? 0
          : int.parse(decimals![0]);
      return Length.fromCmTenths(w * 10 + tenth);
    }
    if (decimals != null) {
      final fraction = Fraction.tryParse('$w.${decimals!}');
      return fraction == null ? null : Length.fromInches(fraction);
    }
    return Length.fromInches(Fraction.whole(w) + Fraction(eighths, 8));
  }

  static const _glyphs = {
    1: '⅛',
    2: '¼',
    3: '⅜',
    4: '½',
    5: '⅝',
    6: '¾',
    7: '⅞',
  };

  /// What the field shows while typing, in ASCII digits (e.g. `38½`, `9.`).
  String get text {
    final b = StringBuffer(whole);
    if (decimals != null) b.write('.${decimals!}');
    if (eighths != 0) b.write(_glyphs[eighths]);
    return b.toString();
  }

  MeasurementInput _copy({String? whole, String? decimals, int? eighths}) =>
      MeasurementInput(
        unit: unit,
        whole: whole ?? this.whole,
        decimals: decimals ?? this.decimals,
        eighths: eighths ?? this.eighths,
      );

  @override
  bool operator ==(Object other) =>
      other is MeasurementInput &&
      other.unit == unit &&
      other.whole == whole &&
      other.decimals == decimals &&
      other.eighths == eighths;

  @override
  int get hashCode => Object.hash(unit, whole, decimals, eighths);
}
