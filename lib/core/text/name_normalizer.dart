import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Normalization used for searching and duplicate checks (TD §7.1).
///
/// Names are stored as typed (trimmed, single-spaced); [normalize] produces
/// the search key: Unicode NFC (which also unifies Bangla ড়/ঢ়/য় typed as
/// one precomposed letter or as base + nukta), lower case, Latin digits, no
/// zero-width joiners, collapsed whitespace.
class NameNormalizer {
  const NameNormalizer._();

  static final RegExp _zeroWidth = RegExp('[​‌‍⁠﻿]');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Display form: trimmed with internal whitespace collapsed, NFC.
  static String clean(String input) =>
      unorm.nfc(input).replaceAll(_spaces, ' ').trim();

  /// Search key for [input].
  static String normalize(String input) => DigitFormatter.toLatin(
    clean(input).replaceAll(_zeroWidth, '').toLowerCase(),
  );
}
