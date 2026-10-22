/// Converts between Latin (0-9) and Bangla (০-৯) digits.
///
/// Storage and parsing always use ASCII digits; Bangla digits are applied
/// only at the presentation boundary (TD §7.2).
class DigitFormatter {
  const DigitFormatter._();

  static const String _bangla = '০১২৩৪৫৬৭৮৯';

  /// Replaces every ASCII digit in [input] with its Bangla equivalent.
  static String toBangla(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x30 && rune <= 0x39) {
        buffer.write(_bangla[rune - 0x30]);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Replaces every Bangla digit in [input] with its ASCII equivalent so user
  /// input typed on a Bangla keyboard can be parsed.
  static String toLatin(String input) {
    final buffer = StringBuffer();
    for (final char in input.split('')) {
      final index = _bangla.indexOf(char);
      buffer.write(index >= 0 ? index.toString() : char);
    }
    return buffer.toString();
  }

  /// Applies Bangla digits only when [bangla] is true.
  static String format(String input, {required bool bangla}) =>
      bangla ? toBangla(input) : input;
}
