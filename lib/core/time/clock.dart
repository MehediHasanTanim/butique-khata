/// Time source, injectable so tests and the capacity engine are deterministic.
abstract class Clock {
  DateTime now();

  /// Today's calendar date as `YYYY-MM-DD` in device-local time.
  String today() => toDateString(now());

  static String toDateString(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Parses a `YYYY-MM-DD` string; throws [FormatException] if malformed.
  static DateTime parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw FormatException('Invalid date', value);
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
}

class SystemClock extends Clock {
  @override
  DateTime now() => DateTime.now();
}

class FixedClock extends Clock {
  FixedClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}
