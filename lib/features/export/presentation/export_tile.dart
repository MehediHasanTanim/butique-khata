import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/ui/app_list_tile.dart';
import 'package:tailor_khata/features/export/data/csv_exporter.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// "Export to spreadsheet" row in More: builds the CSV zip and opens the
/// share sheet (B-4).
class ExportTile extends ConsumerStatefulWidget {
  const ExportTile({super.key});

  @override
  ConsumerState<ExportTile> createState() => _ExportTileState();
}

class _ExportTileState extends ConsumerState<ExportTile> {
  bool _busy = false;

  Future<void> _export() async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sharer = ref.read(fileSharerProvider);
    final clock = ref.read(clockProvider);
    setState(() => _busy = true);
    try {
      final zip = await CsvExporter(ref.read(appDatabaseProvider)).buildZip();
      final d = clock.now();
      String two(int v) => v.toString().padLeft(2, '0');
      await sharer.shareFile(
        zip,
        fileName: 'tailor_khata_${d.year}${two(d.month)}${two(d.day)}.zip',
      );
    } on Object {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AppListTile(
      key: const ValueKey('more-export'),
      title: l10n.exportTitle,
      subtitle: _busy ? l10n.exportWorking : l10n.exportSubtitle,
      leading: const Icon(Icons.table_chart_outlined),
      onTap: _busy ? null : _export,
    );
  }
}
