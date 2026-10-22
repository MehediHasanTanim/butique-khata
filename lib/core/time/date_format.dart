import 'package:intl/intl.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/clock.dart';

/// Formats a stored `YYYY-MM-DD` date for display, e.g. `5 Mar 2026` /
/// `৫ মার্চ ২০২৬`. Falls back to the raw text if it cannot be parsed.
String formatStoredDate(String ymd, String languageCode) {
  try {
    final date = Clock.parseDate(ymd);
    final text = DateFormat.yMMMd(languageCode).format(date);
    return DigitFormatter.format(text, bangla: languageCode == 'bn');
  } on FormatException {
    return ymd;
  }
}
