import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/ui/app_list_tile.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/features/backup/domain/backup_models.dart';
import 'package:tailor_khata/features/backup/presentation/backup_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// "5.2 MB" style size, with Bangla digits when the app is in Bangla.
String formatBytes(int bytes, {bool bangla = false}) {
  final text = bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return bangla ? DigitFormatter.toBangla(text) : text;
}

String formatBackupTime(DateTime at, String lang) {
  final text = DateFormat.yMMMd(lang).add_jm().format(at);
  return lang == 'bn' ? DigitFormatter.toBangla(text) : text;
}

/// Plain-language reason for a failed backup or restore.
String backupFailureText(AppL10n l10n, BackupFailure failure) =>
    switch (failure.code) {
      BackupFailure.noKey => l10n.backupErrNoKey,
      BackupFailure.notABackup => l10n.backupErrNotBackup,
      BackupFailure.wrongPassphrase => l10n.backupErrWrongPassphrase,
      BackupFailure.corrupt => l10n.backupErrCorrupt,
      BackupFailure.newerVersion => l10n.backupErrNewer,
      _ => l10n.backupErrFailed,
    };

/// Make, share and restore encrypted backups (B-2, B-3).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setPassphrase() async {
    final service = ref.read(backupServiceProvider);
    if (service == null) return;
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => PassphraseSetupDialog(
        generate: ref.read(backupPassphraseGeneratorProvider),
      ),
    );
    if (passphrase == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await service.setPassphrase(passphrase);
      ref.read(backupRevisionProvider.notifier).bump();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backupNow() async {
    final service = ref.read(backupServiceProvider);
    if (service == null) return;
    final l10n = AppL10n.of(context);
    final bangla = ref.read(useBanglaDigitsProvider);
    setState(() => _busy = true);
    try {
      final result = await service.createBackup();
      ref.read(backupRevisionProvider.notifier).bump();
      if (mounted) {
        _say(l10n.backupDone(formatBytes(result.sizeBytes, bangla: bangla)));
      }
    } on BackupFailure catch (failure) {
      if (mounted) _say(backupFailureText(l10n, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final service = ref.read(backupServiceProvider);
    final env = ref.read(backupEnvironmentProvider);
    if (service == null || env == null) return;
    final l10n = AppL10n.of(context);
    final file = await ref.read(backupFilePickerProvider).pick();
    if (file == null || !mounted) return;
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => const RestorePassphraseDialog(),
    );
    if (passphrase == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupRestoreConfirmTitle),
        content: Text(l10n.backupRestoreConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            key: const ValueKey('restore-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.backupRestoreAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final db = ref.read(appDatabaseProvider);
    final restart = ref.read(appRestartProvider);
    setState(() => _busy = true);
    // The progress dialog cannot be dismissed; it is closed below.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(child: Text(l10n.backupRestoring)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final result = await service.restore(
        backupFile: file,
        passphrase: passphrase,
        liveDbFile: env.dbFile,
        deviceKeyHex: env.deviceKeyHex,
        closeDatabase: db.close,
      );
      navigator.pop();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Text(
            l10n.backupRestored(
              result.manifest.counts['customers'] ?? 0,
              result.manifest.counts['measurements'] ?? 0,
            ),
          ),
          actions: [
            FilledButton(
              key: const ValueKey('restore-done'),
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.actionOk),
            ),
          ],
        ),
      );
      restart();
    } on BackupFailure catch (failure) {
      navigator.pop();
      if (mounted) _say(backupFailureText(l10n, failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final status = ref.watch(backupStatusProvider).value;
    final files = ref.watch(backupFilesProvider);
    final auto = ref.watch(backupAutoEnabledProvider).value ?? true;
    final service = ref.watch(backupServiceProvider);
    final hasKey = status?.hasKey ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l10n.backupExplain, style: theme.textTheme.bodyMedium),
          ),
          ListTile(
            key: const ValueKey('backup-status'),
            leading: Icon(
              status?.lastAt == null
                  ? Icons.warning_amber_rounded
                  : Icons.verified_outlined,
            ),
            title: Text(
              status?.lastAt == null
                  ? l10n.backupNever
                  : l10n.backupLastAt(formatBackupTime(status!.lastAt!, lang)),
            ),
          ),
          if (service == null)
            const SizedBox.shrink()
          else if (!hasKey)
            Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                key: const ValueKey('backup-set-passphrase'),
                label: l10n.backupSetupAction,
                icon: Icons.key,
                onPressed: _busy ? null : _setPassphrase,
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                key: const ValueKey('backup-now'),
                label: _busy ? l10n.backupWorking : l10n.backupNow,
                icon: Icons.backup_outlined,
                onPressed: _busy ? null : _backupNow,
              ),
            ),
            SwitchListTile(
              key: const ValueKey('backup-auto'),
              title: Text(l10n.backupAuto),
              subtitle: Text(l10n.backupAutoSubtitle),
              value: auto,
              onChanged: (value) async {
                await service.setAutoEnabled(value);
                ref.read(backupRevisionProvider.notifier).bump();
              },
            ),
            AppListTile(
              key: const ValueKey('backup-change-passphrase'),
              title: l10n.backupChangePassphrase,
              leading: const Icon(Icons.key_outlined),
              onTap: _busy ? null : _setPassphrase,
            ),
          ],
          if (service != null) ...[
            SectionHeader(l10n.backupFilesTitle),
            if (files.isEmpty)
              ListTile(title: Text(l10n.backupFilesEmpty))
            else
              for (var i = 0; i < files.length; i++)
                ListTile(
                  key: ValueKey('backup-file-$i'),
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(formatBackupTime(files[i].modified, lang)),
                  subtitle: Text(
                    formatBytes(files[i].sizeBytes, bangla: bangla),
                  ),
                  trailing: IconButton(
                    key: ValueKey('backup-share-$i'),
                    tooltip: l10n.backupShare,
                    icon: const Icon(Icons.ios_share),
                    onPressed: () => ref
                        .read(fileSharerProvider)
                        .shareExistingFile(files[i].file.path),
                  ),
                ),
            const Divider(),
            AppListTile(
              key: const ValueKey('backup-restore'),
              title: l10n.backupRestoreTitle,
              subtitle: l10n.backupRestoreSubtitle,
              leading: const Icon(Icons.restore),
              onTap: _busy ? null : _restore,
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for a new passphrase twice, or makes one (B-2).
class PassphraseSetupDialog extends StatefulWidget {
  const PassphraseSetupDialog({required this.generate, super.key});

  final String Function() generate;

  @override
  State<PassphraseSetupDialog> createState() => _PassphraseSetupDialogState();
}

class _PassphraseSetupDialogState extends State<PassphraseSetupDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(l10n.backupSetupTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.backupPassphraseWarn),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('passphrase-field'),
                controller: _first,
                decoration: InputDecoration(
                  labelText: l10n.backupPassphrase,
                  helperText: l10n.backupPassphraseHint,
                ),
                validator: (v) =>
                    (v ?? '').length < 8 ? l10n.backupPassphraseShort : null,
              ),
              TextFormField(
                key: const ValueKey('passphrase-confirm'),
                controller: _second,
                decoration: InputDecoration(
                  labelText: l10n.backupPassphraseConfirm,
                ),
                validator: (v) =>
                    v != _first.text ? l10n.backupPassphraseMismatch : null,
              ),
              TextButton.icon(
                key: const ValueKey('passphrase-generate'),
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.backupPassphraseGenerate),
                onPressed: () {
                  final value = widget.generate();
                  _first.text = value;
                  _second.text = value;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('passphrase-save'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _first.text);
            }
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

/// Asks for the passphrase of a backup about to be restored.
class RestorePassphraseDialog extends StatefulWidget {
  const RestorePassphraseDialog({super.key});

  @override
  State<RestorePassphraseDialog> createState() =>
      _RestorePassphraseDialogState();
}

class _RestorePassphraseDialogState extends State<RestorePassphraseDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(l10n.backupRestorePassphraseTitle),
      content: TextField(
        key: const ValueKey('restore-passphrase'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.backupPassphrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          key: const ValueKey('restore-passphrase-ok'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.actionConfirm),
        ),
      ],
    );
  }
}
