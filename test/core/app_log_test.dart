import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/logging/app_log.dart';

void main() {
  tearDown(() => AppLog.sink = null);

  test('redacts phone numbers and e-mail addresses', () {
    expect(AppLog.redact('call 01712345678 now'), 'call <number> now');
    expect(AppLog.redact('+880 1712-345678'), '<number>');
    expect(AppLog.redact('mail rahim@example.com'), 'mail <email>');
    expect(AppLog.redact('order 42 ok'), 'order 42 ok');
  });

  test('all levels go through redaction', () {
    final lines = <String>[];
    AppLog.sink = (level, tag, message) => lines.add('$tag:$message');
    AppLog.i('t', 'phone 01712345678');
    AppLog.w('t', 'x@y.com');
    AppLog.e('t', 'failed', StateError('secret 01712345678'));
    expect(lines.join('|'), isNot(contains('0171')));
    expect(lines.join('|'), isNot(contains('x@y.com')));
    // The error object's message (which may hold PII) is never logged.
    expect(lines.last, 't:failed: StateError');
  });

  group('Result', () {
    test('ok and err', () {
      const ok = Result<int>.ok(2);
      const err = Result<int>.err(Failure('x.y'));
      expect(ok.valueOrNull, 2);
      expect(err.failureOrNull?.code, 'x.y');
      expect(ok.map((v) => v * 3).valueOrNull, 6);
      expect(err.map((v) => v * 3).isOk, isFalse);
      expect(ok.when(ok: (v) => 'v$v', err: (f) => f.code), 'v2');
      expect(err.when(ok: (v) => 'v$v', err: (f) => f.code), 'x.y');
    });
  });
}
