import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/errors/result.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/deliveries/domain/deliver_order.dart';
import 'package:tailor_khata/features/deliveries/domain/message_composer.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

final deliverOrderProvider = Provider((ref) => DeliverOrderFacade(ref));

/// Thin wrapper so UI code can build a `DeliverOrder` from providers.
class DeliverOrderFacade {
  DeliverOrderFacade(this._ref);

  final Ref _ref;

  Future<Result<void>> call(
    String orderId, {
    DeliverChoice? choice,
    PayMethod method = PayMethod.cash,
  }) => DeliverOrder(_ref.read(orderRepositoryProvider))(
    orderId,
    choice: choice,
    method: method,
    today: _ref.read(clockProvider).today(),
  );
}

/// Asks what to do about money still owed at hand-over (P-4). Returns null
/// if the tailor backs out.
Future<DeliverChoice?> showDueDialog(
  BuildContext context,
  WidgetRef ref,
  Money due,
) {
  final l10n = AppL10n.of(context);
  final amount = due.format(bangla: ref.read(useBanglaDigitsProvider));
  return showDialog<DeliverChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deliverDueTitle(amount)),
      actionsOverflowDirection: VerticalDirection.down,
      actions: [
        FilledButton(
          key: const ValueKey('deliver-collect'),
          onPressed: () =>
              Navigator.pop(context, DeliverChoice.collectAndDeliver),
          child: Text(l10n.deliverCollect(amount)),
        ),
        OutlinedButton(
          key: const ValueKey('deliver-with-due'),
          onPressed: () => Navigator.pop(context, DeliverChoice.deliverWithDue),
          child: Text(l10n.deliverWithDue(amount)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionGoBack),
        ),
      ],
    ),
  );
}

/// Hands the whole order over, asking about a balance first. Returns true
/// when the order was delivered.
Future<bool> runDeliverFlow(
  BuildContext context,
  WidgetRef ref,
  OrderDetail detail,
) async {
  final l10n = AppL10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final facade = ref.read(deliverOrderProvider);
  var result = await facade(detail.order.id);
  final failure = result.failureOrNull;
  if (failure is DueOutstandingFailure) {
    if (!context.mounted) return false;
    final choice = await showDueDialog(context, ref, failure.due);
    if (choice == null) return false;
    result = await facade(detail.order.id, choice: choice);
  }
  if (result.isOk) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.delivered)));
    return true;
  }
  return false;
}

/// Moves one garment to [target], routing "Delivered" through the balance
/// check. Returns true if it moved.
Future<bool> moveItemGuarded(
  BuildContext context,
  WidgetRef ref,
  OrderDetail detail,
  OrderItem item,
  OrderStatus target,
) async {
  final repo = ref.read(orderRepositoryProvider);
  try {
    await repo.setItemStatus(item.id, target);
    return true;
  } on DueOutstandingError catch (error) {
    if (!context.mounted) return false;
    final choice = await showDueDialog(context, ref, error.due);
    if (choice == null) return false;
    if (choice == DeliverChoice.collectAndDeliver) {
      await repo.addPayment(
        NewPayment(
          orderId: detail.order.id,
          amount: error.due,
          method: PayMethod.cash,
          paidOn: ref.read(clockProvider).today(),
        ),
      );
    }
    await repo.setItemStatus(item.id, target, dueConfirmed: true);
    return true;
  }
}

/// Offers the customer a message about this order (D-3, D-5): preview and
/// edit the text, then open SMS or WhatsApp with it prefilled, or copy it.
Future<void> showMessageSheet(
  BuildContext context,
  WidgetRef ref,
  OrderDetail detail,
  MessageKind kind, {
  String? newDate,
}) async {
  final lang = Localizations.localeOf(context).languageCode;
  final l10n = AppL10n.of(context);
  final settings = ref.read(appSettingsProvider);
  final customer = await ref
      .read(customerRepositoryProvider)
      .byId(detail.order.customerId);
  final garments = await ref.read(measurementRepositoryProvider).garments();
  if (!context.mounted) return;
  final names = [
    for (final item in detail.items)
      garments
              .where((g) => g.id == item.garmentTypeId)
              .firstOrNull
              ?.label(lang) ??
          '',
  ].where((n) => n.isNotEmpty).toSet().toList();

  final text = composeMessage(
    template: settings.templateFor(kind, lang),
    detail: detail,
    garments: names,
    shop: settings.shopName.isEmpty ? l10n.appName : settings.shopName,
    languageCode: lang,
    newDate: newDate,
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MessageSheet(
      initialText: text,
      phone: customer?.phone,
      title: kind == MessageKind.moved
          ? l10n.rescheduleNotify
          : l10n.messageReadyTitle,
    ),
  );
}

class _MessageSheet extends ConsumerStatefulWidget {
  const _MessageSheet({
    required this.initialText,
    required this.phone,
    required this.title,
  });

  final String initialText;
  final String? phone;
  final String title;

  @override
  ConsumerState<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends ConsumerState<_MessageSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy(String message) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: _text.text));
    } on Object {
      // Copying is a convenience; still tell the user what happened.
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send(Uri? Function(String? phone, String body) build) async {
    final l10n = AppL10n.of(context);
    final uri = build(widget.phone, _text.text);
    final navigator = Navigator.of(context);
    if (uri == null) {
      await _copy(l10n.messageNoPhone);
      navigator.pop();
      return;
    }
    final opened = await ref.read(externalLauncherProvider).open(uri);
    if (!opened) {
      if (!mounted) return;
      await _copy(l10n.messageCouldNotOpen);
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('message-text'),
            controller: _text,
            maxLines: 6,
            minLines: 3,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('message-sms'),
                  onPressed: () => _send(MessageLinks.sms),
                  icon: const Icon(Icons.sms_outlined),
                  label: Text(l10n.messageSms),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('message-whatsapp'),
                  onPressed: () => _send(MessageLinks.whatsApp),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(l10n.messageWhatsApp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey('message-copy'),
                onPressed: () => _copy(l10n.messageCopied),
                icon: const Icon(Icons.copy),
                label: Text(l10n.messageCopy),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.messageLater),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
