import 'package:tailor_khata/core/l10n/digit_formatter.dart';

/// A phone number in canonical form.
class PhoneNumber {
  const PhoneNumber({required this.e164, required this.searchDigits});

  /// `+8801712345678`.
  final String e164;

  /// Digits used for substring search: the national form with leading zero
  /// for Bangladesh (`01712345678`), otherwise the digits of [e164].
  final String searchDigits;

  @override
  bool operator ==(Object other) => other is PhoneNumber && other.e164 == e164;

  @override
  int get hashCode => e164.hashCode;

  @override
  String toString() => e164;
}

/// Bangladesh-aware phone normalization (TD §5.8).
class PhoneNormalizer {
  const PhoneNormalizer._();

  /// `01[3-9]` followed by 8 digits.
  static final RegExp _bdNational = RegExp(r'^01[3-9]\d{8}$');

  /// Returns the canonical number, or null when [input] is not a plausible
  /// phone number. An empty string is also null (callers treat empty as
  /// "no phone").
  ///
  /// Accepted Bangladesh forms: `01712-345678`, `01712 345 678`,
  /// `+8801712345678`, `8801712345678`, `008801712345678`, `1712345678`.
  /// Other numbers must start with `+` and hold 8–15 digits.
  static PhoneNumber? parse(String input) {
    final trimmed = DigitFormatter.toLatin(input).trim();
    if (trimmed.isEmpty) return null;
    final hasPlus = trimmed.startsWith('+');
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('00') && !hasPlus) {
      digits = digits.substring(2);
      return _fromInternational(digits);
    }
    if (hasPlus) return _fromInternational(digits);
    if (digits.startsWith('880')) return _fromInternational(digits);

    var national = digits;
    if (national.length == 10 && national.startsWith('1')) {
      national = '0$national';
    }
    if (_bdNational.hasMatch(national)) return _bd(national);
    return null;
  }

  static PhoneNumber? _fromInternational(String digits) {
    if (digits.startsWith('880')) {
      final national = '0${digits.substring(3)}';
      return _bdNational.hasMatch(national) ? _bd(national) : null;
    }
    if (digits.length < 8 || digits.length > 15) return null;
    return PhoneNumber(e164: '+$digits', searchDigits: digits);
  }

  static PhoneNumber _bd(String national) =>
      PhoneNumber(e164: '+88$national', searchDigits: national);
}
