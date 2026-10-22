import 'package:flutter/material.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/dev/perf_harness.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Debug-only screen to generate synthetic data and time it.
class SeedScreen extends StatefulWidget {
  const SeedScreen({super.key});

  @override
  State<SeedScreen> createState() => _SeedScreenState();
}

class _SeedScreenState extends State<SeedScreen> {
  static const _sizes = [100, 1000, 10000];
  int _count = 1000;
  String? _result;

  void _generate() {
    final harness = PerfHarness();
    final list = harness.measureSync(
      'generate',
      () => SeedGenerator().customers(_count),
    );
    setState(() {
      _result = AppL10n.of(context)
          .seedDone(list.length, harness.samples.single.elapsed.inMilliseconds);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.seedTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.seedCustomers,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final size in _sizes)
                ButtonSegment(value: size, label: Text('$size')),
            ],
            selected: {_count},
            onSelectionChanged: (value) => setState(() => _count = value.first),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: l10n.seedGenerate, onPressed: _generate),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}
