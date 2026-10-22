import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/ui/app_list_tile.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final locale = ref.watch(localeProvider);
    final controller = ref.read(localeProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moreTitle)),
      body: ListView(
        children: [
          SectionHeader(l10n.settingsLanguage),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
                ButtonSegment(value: 'bn', label: Text(l10n.languageBangla)),
              ],
              selected: {locale.languageCode},
              onSelectionChanged: (value) =>
                  controller.setLanguage(value.first),
            ),
          ),
          if (kDebugMode) ...[
            SectionHeader(l10n.settingsDeveloper),
            AppListTile(
              title: l10n.seedTitle,
              subtitle: l10n.settingsDeveloperSubtitle,
              leading: const Icon(Icons.bug_report_outlined),
              onTap: () => context.go(AppRoutes.seed),
            ),
          ],
        ],
      ),
    );
  }
}
