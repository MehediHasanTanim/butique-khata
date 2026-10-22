import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Shop name and the wording of messages sent to customers (D-3).
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  late final TextEditingController _shop;
  final Map<MessageKind, TextEditingController> _templates = {};
  final Map<MessageKind, Timer> _timers = {};

  @override
  void initState() {
    super.initState();
    _shop = TextEditingController(text: ref.read(appSettingsProvider).shopName);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = Localizations.localeOf(context).languageCode;
    final settings = ref.read(appSettingsProvider);
    for (final kind in MessageKind.values) {
      _templates.putIfAbsent(
        kind,
        () => TextEditingController(text: settings.templateFor(kind, lang)),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _shop.dispose();
    for (final c in _templates.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveLater(MessageKind kind, String text) {
    _timers[kind]?.cancel();
    _timers[kind] = Timer(const Duration(milliseconds: 400), () {
      ref.read(appSettingsProvider.notifier).setTemplate(kind, text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final labels = {
      MessageKind.ready: l10n.templateReady,
      MessageKind.due: l10n.templateDue,
      MessageKind.moved: l10n.templateMoved,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMessages)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('shop-name'),
            controller: _shop,
            decoration: InputDecoration(labelText: l10n.shopNameLabel),
            onChanged: (v) =>
                ref.read(appSettingsProvider.notifier).setShopName(v),
          ),
          const SizedBox(height: 16),
          Text(
            '${l10n.templateHelp} {name} {order} {garment} {due} {date} {shop}',
            style: theme.textTheme.bodySmall,
          ),
          for (final kind in MessageKind.values) ...[
            const SizedBox(height: 20),
            Text(labels[kind]!, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('template-${kind.name}'),
              controller: _templates[kind],
              maxLines: 5,
              minLines: 3,
              onChanged: (v) => _saveLater(kind, v),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: ValueKey('template-reset-${kind.name}'),
                onPressed: () {
                  _timers[kind]?.cancel();
                  ref.read(appSettingsProvider.notifier).setTemplate(kind, '');
                  _templates[kind]!.text = MessageTemplates.defaultFor(
                    kind,
                    lang,
                  );
                },
                child: Text(l10n.templateReset),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
