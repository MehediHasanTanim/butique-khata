import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/features/backup/presentation/backup_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Home warning when there is no recent backup (B-2): never backed up, or
/// the last one is a week old or more.
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backupServiceProvider) == null) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(backupStatusProvider).value;
    final now = ref.watch(clockProvider).now();
    if (status == null || !status.isStale(now)) return const SizedBox.shrink();

    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final days = status.daysSince(now);
    final text = days == null
        ? l10n.homeBackupNever
        : l10n.homeBackupStale(days);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        key: const ValueKey('backup-banner'),
        color: theme.colorScheme.errorContainer,
        child: ListTile(
          leading: Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          title: Text(
            ref.watch(useBanglaDigitsProvider)
                ? DigitFormatter.toBangla(text)
                : text,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          trailing: TextButton(
            onPressed: () => context.push(AppRoutes.backup),
            child: Text(l10n.homeBackupAction),
          ),
          onTap: () => context.push(AppRoutes.backup),
        ),
      ),
    );
  }
}
