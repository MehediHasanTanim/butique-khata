import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Lets the tailor pick a stage. With [current] only moves allowed from it
/// are offered (forward, or one step back); with null every stage is.
Future<OrderStatus?> showStatusPicker(
  BuildContext context,
  OrderStatus? current,
) {
  final l10n = AppL10n.of(context);
  final options = [
    for (final s in OrderStatus.values)
      if (current == null || current.canMoveTo(s)) s,
  ];
  return showModalBottomSheet<OrderStatus>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              current == null ? l10n.setAllItems : l10n.setStatus,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final s in options)
            ListTile(
              key: ValueKey('pick-status-${s.dbValue}'),
              minTileHeight: 56,
              title: Text(s.label(l10n)),
              onTap: () => Navigator.pop(context, s),
            ),
        ],
      ),
    ),
  );
}

/// Records a payment (or, with [refund], money handed back) for [detail].
Future<void> showAddPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  OrderDetail detail, {
  Money? suggested,
  bool refund = false,
}) async {
  final input = await showDialog<NewPayment>(
    context: context,
    builder: (_) => _PaymentDialog(
      orderId: detail.order.id,
      today: ref.read(clockProvider).today(),
      suggested: suggested,
      refund: refund,
    ),
  );
  if (input != null) {
    await ref.read(orderRepositoryProvider).addPayment(input);
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.orderId,
    required this.today,
    required this.suggested,
    required this.refund,
  });

  final String orderId;
  final String today;
  final Money? suggested;
  final bool refund;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.suggested?.toInputString() ?? '',
  );
  final _note = TextEditingController();
  PayMethod _method = PayMethod.cash;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save(AppL10n l10n) {
    final parsed = Money.tryParse(_amount.text);
    if (parsed == null || parsed.isZero) {
      setState(() => _error = l10n.errInvalidAmount);
      return;
    }
    Navigator.pop(
      context,
      NewPayment(
        orderId: widget.orderId,
        amount: widget.refund ? -parsed : parsed,
        method: _method,
        paidOn: widget.today,
        kind: widget.refund ? PaymentKind.refund : PaymentKind.payment,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return AlertDialog(
      title: Text(widget.refund ? l10n.recordRefund : l10n.addPayment),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('payment-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.paymentAmount,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PayMethod>(
              initialValue: _method,
              decoration: InputDecoration(labelText: l10n.paidByLabel),
              items: [
                for (final m in PayMethod.values)
                  DropdownMenuItem(value: m, child: Text(m.label(l10n))),
              ],
              onChanged: (m) => setState(() => _method = m ?? _method),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l10n.paymentNote),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          key: const ValueKey('payment-save'),
          onPressed: () => _save(l10n),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

/// Cancels the order with a reason and a decision about money already paid.
Future<void> showCancelOrderDialog(
  BuildContext context,
  WidgetRef ref,
  OrderDetail detail,
) async {
  final result = await showDialog<({String reason, CancelAdvance advance})>(
    context: context,
    builder: (_) => _CancelDialog(paid: detail.money.paid),
  );
  if (result != null) {
    await ref
        .read(orderRepositoryProvider)
        .cancel(
          detail.order.id,
          reason: result.reason,
          advance: result.advance,
          today: ref.read(clockProvider).today(),
        );
  }
}

class _CancelDialog extends ConsumerStatefulWidget {
  const _CancelDialog({required this.paid});

  final Money paid;

  @override
  ConsumerState<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends ConsumerState<_CancelDialog> {
  final _reason = TextEditingController();
  CancelAdvance _advance = CancelAdvance.refund;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    return AlertDialog(
      title: Text(l10n.cancelOrder),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('cancel-reason'),
              controller: _reason,
              decoration: InputDecoration(labelText: l10n.cancelReasonLabel),
            ),
            if (widget.paid.isPositive) ...[
              const SizedBox(height: 16),
              Text(l10n.cancelPaidNote(widget.paid.format(bangla: bangla))),
              RadioGroup<CancelAdvance>(
                groupValue: _advance,
                onChanged: (v) => setState(() => _advance = v ?? _advance),
                child: Column(
                  children: [
                    RadioListTile<CancelAdvance>(
                      key: const ValueKey('cancel-refund'),
                      value: CancelAdvance.refund,
                      title: Text(l10n.cancelRefund),
                    ),
                    RadioListTile<CancelAdvance>(
                      key: const ValueKey('cancel-keep'),
                      value: CancelAdvance.keep,
                      title: Text(l10n.cancelKeep),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionGoBack),
        ),
        TextButton(
          key: const ValueKey('cancel-confirm'),
          onPressed: () => Navigator.pop(context, (
            reason: _reason.text.trim(),
            advance: _advance,
          )),
          child: Text(l10n.cancelConfirm),
        ),
      ],
    );
  }
}

/// Change delivery date, trial date and urgency, recorded in the change log.
Future<void> showEditDeliveryDialog(
  BuildContext context,
  WidgetRef ref,
  Order order,
) async {
  final l10n = AppL10n.of(context);
  final lang = Localizations.localeOf(context).languageCode;
  var delivery = order.deliveryDate;
  String? trial = order.trialDate;
  var urgent = order.urgent;

  Future<String?> pick(BuildContext context, String initial) async {
    final now = ref.read(clockProvider).now();
    final current = Clock.parseDate(initial);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    return picked == null ? null : Clock.toDateString(picked);
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.editDetails),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('edit-delivery-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.deliveryDateLabel),
              subtitle: Text(formatStoredDate(delivery, lang)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final d = await pick(context, delivery);
                if (d != null) setState(() => delivery = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.trialDateLabel),
              subtitle: Text(
                trial == null ? l10n.notSet : formatStoredDate(trial!, lang),
              ),
              trailing: trial == null
                  ? const Icon(Icons.event)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => trial = null),
                    ),
              onTap: () async {
                final d = await pick(context, trial ?? delivery);
                if (d != null) setState(() => trial = d);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.urgentLabel),
              value: urgent,
              onChanged: (v) => setState(() => urgent = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            key: const ValueKey('edit-delivery-save'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    ),
  );
  if (saved ?? false) {
    await ref
        .read(orderRepositoryProvider)
        .updateDetails(
          order.id,
          deliveryDate: delivery,
          trialDate: trial,
          clearTrialDate: trial == null,
          urgent: urgent,
        );
  }
}
