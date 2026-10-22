import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';

void main() {
  group('DigitFormatter', () {
    test('converts to Bangla and back', () {
      expect(DigitFormatter.toBangla('Tk 1,250.50'), 'Tk ১,২৫০.৫০');
      expect(DigitFormatter.toLatin('৩৮½'), '38½');
    });

    test('format respects the flag', () {
      expect(DigitFormatter.format('12', bangla: false), '12');
      expect(DigitFormatter.format('12', bangla: true), '১২');
    });
  });

  group('Money', () {
    test('integer arithmetic has no drift', () {
      var total = Money.zero;
      for (var i = 0; i < 1000; i++) {
        total += const Money(10);
      }
      expect(total, const Money(10000));
      expect(
        Money.sum([const Money.taka(5), const Money(50)]),
        const Money(550),
      );
    });

    test('groups with lakh/crore style', () {
      expect(const Money.taka(0).format(), '৳0');
      expect(const Money.taka(999).format(), '৳999');
      expect(const Money.taka(1000).format(), '৳1,000');
      expect(const Money.taka(123456).format(), '৳1,23,456');
      expect(const Money.taka(12345678).format(), '৳1,23,45,678');
    });

    test('shows poisha only when non-zero and handles negatives', () {
      expect(const Money(125050).format(), '৳1,250.50');
      expect(const Money(-2500).format(), '-৳25');
      expect(const Money(5).format(symbol: false), '0.05');
    });

    test('Bangla digits', () {
      expect(const Money.taka(123456).format(bangla: true), '৳১,২৩,৪৫৬');
    });

    test('comparison and sign helpers', () {
      expect(const Money(5) < const Money(6), isTrue);
      expect(const Money(-1).isNegative, isTrue);
      expect(-const Money(5), const Money(-5));
    });
  });

  group('Fraction.tryParse', () {
    test('whole numbers and decimals', () {
      expect(Fraction.tryParse('38'), Fraction.whole(38));
      expect(Fraction.tryParse('38.5'), Fraction(77, 2));
      expect(Fraction.tryParse('.25'), Fraction(1, 4));
      expect(Fraction.tryParse('৩৮'), Fraction.whole(38));
    });

    test('fractions and mixed numbers', () {
      expect(Fraction.tryParse('1/2'), Fraction(1, 2));
      expect(Fraction.tryParse('38 1/2'), Fraction(77, 2));
      expect(Fraction.tryParse('38½'), Fraction(77, 2));
      expect(Fraction.tryParse('½'), Fraction(1, 2));
      expect(Fraction.tryParse('9 ⅛'), Fraction(73, 8));
    });

    test('rejects garbage', () {
      expect(Fraction.tryParse(''), isNull);
      expect(Fraction.tryParse('abc'), isNull);
      expect(Fraction.tryParse('1/0'), isNull);
      expect(Fraction.tryParse('-3'), isNull);
      expect(Fraction.tryParse('.'), isNull);
    });
  });

  group('Length', () {
    test('38½ inches is 9779 units (38.5 x 254)', () {
      final length = Length.fromInches(Fraction.tryParse('38½')!);
      expect(length.mm10, 9779);
      expect(length.toInchFraction(), '38½');
    });

    test('round-trips every eighth for common range', () {
      for (var eighths = 0; eighths <= 60 * 8; eighths++) {
        final length = Length.fromInches(Fraction(eighths, 8));
        final shown = length.toInchFraction();
        final parsed = Fraction.tryParse(shown);
        expect(parsed, Fraction(eighths, 8), reason: 'eighths=$eighths');
      }
    });

    test('rounds display to nearest eighth without altering the value', () {
      const length = Length.fromMm10(9785);
      expect(length.toInchFraction(), '38½');
      expect(length.mm10, 9785);
    });

    test('whole inches have no fraction glyph', () {
      expect(Length.fromInches(Fraction.whole(40)).toInchFraction(), '40');
      expect(Length.fromInches(Fraction(1, 2)).toInchFraction(), '½');
      expect(Length.zero.toInchFraction(), '0');
    });

    test('quarter denominators', () {
      expect(
        Length.fromInches(Fraction(1, 8)).toInchFraction(denominator: 4),
        '¼',
      );
      expect(
        Length.fromInches(Fraction(7, 16)).toInchFraction(denominator: 4),
        '½',
      );
    });

    test('centimetres are exact', () {
      expect(const Length.fromCmTenths(965).toCm(), '96.5');
      expect(Length.fromInches(Fraction.whole(10)).toCm(), '25.4');
    });

    test('Bangla digits', () {
      expect(
        Length.fromInches(Fraction.tryParse('38½')!)
            .toInchFraction(bangla: true),
        '৩৮½',
      );
    });

    test('arithmetic and ordering', () {
      const a = Length.fromMm10(100);
      const b = Length.fromMm10(40);
      expect(a - b, const Length.fromMm10(60));
      expect(a > b, isTrue);
      expect((b - a).abs, const Length.fromMm10(60));
    });

    test('invalid denominators throw', () {
      expect(
        () => Length.zero.toInchFraction(denominator: 3),
        throwsArgumentError,
      );
    });
  });

  group('Clock', () {
    test('FixedClock is deterministic and formats dates', () {
      final clock = FixedClock(DateTime(2026, 3, 5, 10));
      expect(clock.today(), '2026-03-05');
      clock.advance(const Duration(days: 30));
      expect(clock.today(), '2026-04-04');
    });

    test('parseDate validates', () {
      expect(Clock.parseDate('2026-03-05'), DateTime(2026, 3, 5));
      expect(() => Clock.parseDate('5/3/2026'), throwsFormatException);
    });
  });
}
