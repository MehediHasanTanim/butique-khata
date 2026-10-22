import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/features/dev/perf_harness.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';

void main() {
  test('is deterministic for a seed and yields valid BD mobile numbers', () {
    final a = SeedGenerator(seed: 7).customers(200);
    final b = SeedGenerator(seed: 7).customers(200);
    expect(a.map((c) => c.name), b.map((c) => c.name));
    expect(a.map((c) => c.phone), b.map((c) => c.phone));
    for (final c in a) {
      expect(c.phone, matches(RegExp(r'^01[3-9]\d{8}$')));
      expect(c.name.trim().split(' '), hasLength(2));
    }
  });

  test('mixes Bangla and English names', () {
    final names = SeedGenerator().customers(200).map((c) => c.name);
    bool isBangla(String s) => s.runes.any((r) => r >= 0x0980 && r <= 0x09FF);
    expect(names.any(isBangla), isTrue);
    expect(names.any((n) => !isBangla(n)), isTrue);
  });

  test('generates 10,000 customers quickly and the harness records it', () {
    final harness = PerfHarness();
    final list = harness.measureSync(
      'gen',
      () => SeedGenerator().customers(10000),
    );
    expect(list, hasLength(10000));
    expect(harness.samples.single.elapsed.inSeconds, lessThan(2));
  });
}
