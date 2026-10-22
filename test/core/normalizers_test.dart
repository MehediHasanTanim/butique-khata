import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';

void main() {
  group('PhoneNormalizer', () {
    const bd = '+8801712345678';
    final equivalent = [
      '01712-345678',
      '01712345678',
      '+8801712345678',
      '8801712345678',
      '+88 01712 345 678',
      '008801712345678',
      '1712345678',
      '০১৭১২৩৪৫৬৭৮',
      '  01712 345678  ',
    ];
    for (final input in equivalent) {
      test('"$input" → $bd', () {
        final number = PhoneNormalizer.parse(input);
        expect(number?.e164, bd);
        expect(number?.searchDigits, '01712345678');
      });
    }

    final invalid = [
      '',
      '   ',
      'abc',
      '0171234',
      '02-9555555',
      '01212345678',
      '+8801212345678',
      '+123',
      '123456789012345678',
    ];
    for (final input in invalid) {
      test('"$input" is rejected', () {
        expect(PhoneNormalizer.parse(input), isNull);
      });
    }

    test('foreign numbers need a plus sign', () {
      final uk = PhoneNormalizer.parse('+44 7700 900123');
      expect(uk?.e164, '+447700900123');
      expect(uk?.searchDigits, '447700900123');
      expect(PhoneNormalizer.parse('447700900123'), isNull);
    });

    test('equality is by E.164', () {
      expect(
        PhoneNormalizer.parse('01712345678'),
        PhoneNormalizer.parse('+8801712345678'),
      );
    });
  });

  group('NameNormalizer', () {
    final cases = <String, String>{
      '  Rahim   Uddin ': 'rahim uddin',
      'RAHIM': 'rahim',
      'রহিম  উদ্দিন': 'রহিম উদ্দিন',
      'Rahim 2': 'rahim 2',
      'রহিম ২': 'রহিম 2',
    };
    cases.forEach((input, expected) {
      test('"$input" → "$expected"', () {
        expect(NameNormalizer.normalize(input), expected);
      });
    });

    test('unifies precomposed and decomposed Bangla letters', () {
      const precomposed = '\u09DC';
      const decomposed = '\u09A1\u09BC';
      expect(precomposed.runes.length, 1);
      expect(decomposed.runes.length, 2);
      expect(
        NameNormalizer.normalize('আ$precomposed'),
        NameNormalizer.normalize('আ$decomposed'),
      );
      const o1 = '\u0995\u09CB';
      const o2 = '\u0995\u09C7\u09BE';
      expect(NameNormalizer.normalize(o1), NameNormalizer.normalize(o2));
    });

    test('strips zero-width joiners from the search key only', () {
      const typed = 'র‍যান';
      expect(NameNormalizer.normalize(typed), 'রযান');
    });

    test('clean keeps case and collapses whitespace', () {
      expect(NameNormalizer.clean('  Rahim \n Uddin '), 'Rahim Uddin');
    });
  });

  group('IdGenerator', () {
    test('UUIDv7 ids are unique and time ordered', () {
      const gen = UuidV7Generator();
      final ids = List.generate(500, (_) => gen.newId());
      expect(ids.toSet(), hasLength(500));
      expect(ids.first, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(ids.first.substring(14, 15), '7');
    });

    test('sequential ids', () {
      final gen = SequentialIdGenerator('c');
      expect([gen.newId(), gen.newId()], ['c-1', 'c-2']);
    });
  });
}
