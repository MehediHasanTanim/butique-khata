import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_input.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_form_model.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_keypad.dart';

MeasurementInput typed(String keys, {MeasureUnit unit = MeasureUnit.inch}) {
  var input = MeasurementInput.empty(unit);
  for (final key in keys.split('')) {
    input = switch (key) {
      '.' => input.decimalPoint(),
      '<' => input.backspace(),
      '⅛' => input.fraction(1),
      '¼' => input.fraction(2),
      '⅜' => input.fraction(3),
      '½' => input.fraction(4),
      '⅝' => input.fraction(5),
      '¾' => input.fraction(6),
      '⅞' => input.fraction(7),
      _ => input.digit(int.parse(key)),
    };
  }
  return input;
}

const fields = [
  FieldTemplate(
    key: 'length',
    labelEn: 'Length',
    labelBn: 'লম্বা',
    sortOrder: 0,
    minMm10: 15 * 254,
    maxMm10: 60 * 254,
  ),
  FieldTemplate(
    key: 'chest',
    labelEn: 'Chest',
    labelBn: 'বুক',
    sortOrder: 1,
    minMm10: 20 * 254,
    maxMm10: 60 * 254,
  ),
  FieldTemplate(key: 'waist', labelEn: 'Waist', labelBn: 'কোমর', sortOrder: 2),
];

void main() {
  group('MeasurementInput (inches)', () {
    test('38 ½ is 9779 stored units', () {
      final input = typed('38½');
      expect(input.length!.mm10, 9779);
      expect(input.text, '38½');
    });

    test('every fraction key maps to the right eighth', () {
      const glyphs = ['⅛', '¼', '⅜', '½', '⅝', '¾', '⅞'];
      for (var i = 0; i < glyphs.length; i++) {
        final value = typed('40${glyphs[i]}').length!;
        expect(value.toInchFraction(), '40${glyphs[i]}', reason: glyphs[i]);
      }
    });

    test('fraction only: ½ is half an inch', () {
      expect(typed('½').length!.toInchFraction(), '½');
    });

    test('fraction ends the number; further digits are ignored', () {
      final input = typed('38½7');
      expect(input.text, '38½');
      expect(input.isComplete, isTrue);
    });

    test('decimals up to two places, no fraction after a decimal', () {
      final input = typed('38.257');
      expect(input.text, '38.25');
      expect(input.length!.mm10, 9652 + 64); // 38.25 in = 9715.5 → 9716
      expect(typed('38.').fraction(4).text, '38.');
      expect(typed('38.').canAddFraction, isFalse);
    });

    test('decimal point first becomes 0.', () {
      expect(typed('.5').text, '0.5');
    });

    test('limits whole digits and avoids leading zeros', () {
      expect(typed('12345').text, '123');
      expect(typed('007').text, '7');
    });

    test('only one decimal point', () {
      expect(typed('3.1.4').text, '3.14');
    });

    test('backspace removes fraction, then decimals, then digits', () {
      expect(typed('38½<').text, '38');
      expect(typed('38.25<').text, '38.2');
      expect(typed('38.<').text, '38');
      expect(typed('38<').text, '3');
      expect(typed('3<').isEmpty, isTrue);
      expect(typed('<<').isEmpty, isTrue);
    });

    test('empty input has no length', () {
      expect(MeasurementInput.empty(MeasureUnit.inch).length, isNull);
    });
  });

  group('MeasurementInput (cm)', () {
    test('one decimal, exact tenths', () {
      final input = typed('96.57', unit: MeasureUnit.cm);
      expect(input.text, '96.5');
      expect(input.length!.mm10, 9650);
      expect(input.isComplete, isTrue);
    });

    test('fractions are ignored', () {
      final input = typed('96½', unit: MeasureUnit.cm);
      expect(input.text, '96');
      expect(input.canAddFraction, isFalse);
    });
  });

  group('MeasurementFormModel', () {
    MeasurementFormModel model({bool autoAdvance = true}) =>
        MeasurementFormModel(fields: fields, autoAdvance: autoAdvance);

    test('typing, next and previous commit values', () {
      final m = model()
        ..digit(4)
        ..digit(2)
        ..next()
        ..digit(3)
        ..digit(8);
      expect(m.focusedIndex, 1);
      expect(m.displayAt(0), '42');
      expect(m.displayAt(1), '38');
      m.previous();
      expect(m.focusedIndex, 0);
      expect(m.toValues()['chest']!.toInchFraction(), '38');
    });

    test('a fraction auto-advances to the next field', () {
      final m = model()
        ..digit(4)
        ..digit(2)
        ..fraction(4);
      expect(m.focusedIndex, 1);
      expect(m.displayAt(0), '42½');
    });

    test('auto-advance can be turned off', () {
      final m = model(autoAdvance: false)
        ..digit(4)
        ..fraction(4);
      expect(m.focusedIndex, 0);
    });

    test('auto-advance does not run past the last field', () {
      final m = model()
        ..focus(2)
        ..digit(3)
        ..fraction(2);
      expect(m.focusedIndex, 2);
      expect(m.displayAt(2), '3¼');
    });

    test('typing over an existing value replaces it', () {
      final m = model()
        ..digit(4)
        ..digit(2)
        ..next()
        ..previous();
      expect(m.displayAt(0), '42');
      m.digit(5);
      expect(m.displayAt(0), '5');
    });

    test('backspace on a stored value clears the field', () {
      final m = model()
        ..digit(4)
        ..next()
        ..previous()
        ..backspace();
      expect(m.displayAt(0), isNull);
      expect(m.toValues(), isEmpty);
    });

    test('backspace while typing deletes one key', () {
      final m = model()
        ..digit(4)
        ..digit(2)
        ..backspace();
      expect(m.displayAt(0), '4');
    });

    test('tapping another field commits typing', () {
      final m = model()
        ..digit(4)
        ..focus(2);
      expect(m.focusedIndex, 2);
      expect(m.displayAt(0), '4');
    });

    test('blank fields are omitted from the result', () {
      final m = model()
        ..digit(4)
        ..next()
        ..next();
      expect(m.toValues().keys, ['length']);
      expect(m.filledCount, 1);
    });

    test('range warnings are soft and live', () {
      final m = model()
        ..digit(1)
        ..digit(2);
      expect(m.rangeAt(0), RangeStatus.tooLow);
      m.digit(0);
      expect(m.rangeAt(0), RangeStatus.tooHigh);
      m
        ..backspace()
        ..backspace()
        ..backspace()
        ..digit(3)
        ..digit(8);
      expect(m.rangeAt(0), RangeStatus.ok);
      expect(m.rangeAt(2), RangeStatus.ok); // no range configured
    });

    test('cm mode completes after the decimal digit and advances', () {
      final m = model()
        ..setUnit(MeasureUnit.cm)
        ..digit(9)
        ..digit(6)
        ..decimalPoint()
        ..digit(5);
      expect(m.focusedIndex, 1);
      expect(m.displayAt(0), '96.5');
      expect(m.fractionsEnabled, isFalse);
    });

    test('switching unit keeps stored values and re-renders them', () {
      final m = model()
        ..digit(4)
        ..digit(0)
        ..next()
        ..setUnit(MeasureUnit.cm);
      expect(m.displayAt(0), '101.6');
      m.setUnit(MeasureUnit.inch);
      expect(m.displayAt(0), '40');
    });

    test('Bangla digits are display only', () {
      final m = model()
        ..digit(4)
        ..digit(2)
        ..fraction(4);
      expect(m.displayAt(0, bangla: true), '৪২½');
      expect(m.toValues()['length']!.toInchFraction(), '42½');
    });

    test('initial values load and prefill display', () {
      final m = MeasurementFormModel(
        fields: fields,
        initial: {'chest': typed('38½').length!},
      );
      expect(m.displayAt(1), '38½');
      expect(m.hasValues, isTrue);
    });
  });

  group('MeasurementKeypad widget', () {
    Future<List<String>> pump(
      WidgetTester tester, {
      bool fractions = true,
      Size size = const Size(360, 640),
    }) async {
      final log = <String>[];
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MeasurementKeypad(
                fractionsEnabled: fractions,
                onDigit: (d) => log.add('d$d'),
                onDecimal: () => log.add('.'),
                onFraction: (n) => log.add('f$n'),
                onBackspace: () => log.add('<'),
                onNext: () => log.add('next'),
              ),
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('every key reports the right event', (tester) async {
      final log = await pump(tester);
      for (var d = 0; d <= 9; d++) {
        await tester.tap(find.byKey(ValueKey('key-$d')));
      }
      for (var n = 1; n <= 7; n++) {
        await tester.tap(find.byKey(ValueKey('key-frac-$n')));
      }
      await tester.tap(find.byKey(const ValueKey('key-decimal')));
      await tester.tap(find.byKey(const ValueKey('key-backspace')));
      await tester.tap(find.byKey(const ValueKey('key-next')));
      expect(log, [
        for (var d = 0; d <= 9; d++) 'd$d',
        for (var n = 1; n <= 7; n++) 'f$n',
        '.',
        '<',
        'next',
      ]);
    });

    testWidgets('keys are at least 48dp and the pad is compact', (
      tester,
    ) async {
      await pump(tester);
      for (final id in ['key-1', 'key-frac-4', 'key-backspace', 'key-next']) {
        final size = tester.getSize(find.byKey(ValueKey(id)));
        expect(size.height, greaterThanOrEqualTo(48), reason: id);
        expect(size.width, greaterThanOrEqualTo(48), reason: id);
      }
      final pad = tester.getSize(find.byType(MeasurementKeypad));
      expect(pad.height, lessThan(260)); // leaves room on a 5" screen
    });

    testWidgets('fraction keys are disabled in cm mode', (tester) async {
      final log = await pump(tester, fractions: false);
      await tester.tap(find.byKey(const ValueKey('key-frac-4')));
      await tester.tap(find.byKey(const ValueKey('key-5')));
      expect(log, ['d5']);
    });

    testWidgets('works on a very small 320x480 screen', (tester) async {
      await pump(tester, size: const Size(320, 480));
      expect(tester.takeException(), isNull);
    });
  });
}
