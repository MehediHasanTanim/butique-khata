import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/features/dev/perf_harness.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';
import 'package:tailor_khata/features/dev/seed_writer.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Debug-only screen to generate synthetic customers, save them, and time it.
class SeedScreen extends ConsumerStatefulWidget {
  const SeedScreen({super.key});

  @override
  ConsumerState<SeedScreen> createState() => _SeedScreenState();
}

class _SeedScreenState extends ConsumerState<SeedScreen> {
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

  Future<void> _save() async {
    final l10n = AppL10n.of(context);
    final harness = PerfHarness();
    final writer = SeedWriter(ref.read(appDatabaseProvider));
    final saved = await harness.measure(
      'write',
      () => writer.write(SeedGenerator().customers(_count)),
    );
    if (!mounted) return;
    setState(
      () => _result = '${l10n.seedSaved(saved)} · ${harness.samples.single}',
    );
  }

  Future<void> _clear() async {
    final l10n = AppL10n.of(context);
    final removed = await SeedWriter(ref.read(appDatabaseProvider)).clear();
    if (!mounted) return;
    setState(() => _result = l10n.seedRemoved(removed));
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
          const SizedBox(height: 12),
          PrimaryButton(label: l10n.seedWrite, onPressed: _save),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _clear, child: Text(l10n.seedClear)),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}
