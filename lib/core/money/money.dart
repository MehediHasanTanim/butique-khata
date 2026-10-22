import 'package:tailor_khata/core/l10n/digit_formatter.dart';

/// An amount of money in poisha (1 BDT = 100 poisha).
///
/// Arithmetic is integer-only so totals and dues can never drift (TD §5.4).
/// Negative values are valid (refunds, credit).
class Money implements Comparable<Money> {
  const Money(this.poisha);

  /// Builds an amount from whole taka.
  const Money.taka(int taka) : poisha = taka * 100;

  static const Money zero = Money(0);

  final int poisha;

  Money operator +(Money other) => Money(poisha + other.poisha);
  Money operator -(Money other) => Money(poisha - other.poisha);
  Money operator -() => Money(-poisha);
  Money operator *(int factor) => Money(poisha * factor);

  bool operator <(Money other) => poisha < other.poisha;
  bool operator <=(Money other) => poisha <= other.poisha;
  bool operator >(Money other) => poisha > other.poisha;
  bool operator >=(Money other) => poisha >= other.poisha;

  bool get isZero => poisha == 0;
  bool get isNegative => poisha < 0;
  bool get isPositive => poisha > 0;

  Money get abs => Money(poisha.abs());

  /// Sums [amounts]; an empty iterable gives [zero].
  static Money sum(Iterable<Money> amounts) =>
      amounts.fold(zero, (total, amount) => total + amount);

  /// Formats with South Asian (lakh/crore) grouping, e.g. `৳12,34,567`.
  ///
  /// Poisha are shown only when non-zero. Set [bangla] to use Bangla digits.
  String format({bool bangla = false, bool symbol = true}) {
    final absolute = poisha.abs();
    final taka = absolute ~/ 100;
    final paisa = absolute % 100;
    var text = groupSouthAsian(taka);
    if (paisa != 0) {
      text = '$text.${paisa.toString().padLeft(2, '0')}';
    }
    text = DigitFormatter.format(text, bangla: bangla);
    final prefix = symbol ? '৳' : '';
    return '${isNegative ? '-' : ''}$prefix$text';
  }

  /// Groups [value] as `1,23,45,678` (last three digits, then pairs).
  static String groupSouthAsian(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final parts = <String>[];
    var rest = head;
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$tail';
  }

  @override
  int compareTo(Money other) => poisha.compareTo(other.poisha);

  @override
  bool operator ==(Object other) => other is Money && other.poisha == poisha;

  @override
  int get hashCode => poisha.hashCode;

  @override
  String toString() => 'Money($poisha poisha)';
}
