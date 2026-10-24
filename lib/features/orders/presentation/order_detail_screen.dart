import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/core/ui/status_chip.dart';
import 'package:tailor_khata/features/deliveries/domain/message_templates.dart';
import 'package:tailor_khata/features/deliveries/presentation/delivery_actions.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/measurements/domain/measurement_format.dart';
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/domain/style_catalog.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/payment_dialogs.dart';
import 'package:tailor_khata/features/orders/presentation/photo_widgets.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

enum _MenuAction { editDelivery, setAll, message, slip, duplicate, cancel }

/// Everything about one order: items and their progress, the measurements
/// they were cut from, money, payments and the change log (O-11, P-3).
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final detail = ref.watch(orderDetailProvider(orderId));
    return detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.errorGenericTitle)),
      ),
      data: (value) {
        if (value == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.orderNotFound,
              body: '',
            ),
          );
        }
        return _OrderDetailView(detail: value);
      },
    );
  }
}

class _OrderDetailView extends ConsumerWidget {
  const _OrderDetailView({required this.detail});

  final OrderDetail detail;

  Order get order => detail.order;

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.editDelivery:
        final edit = await showEditDeliveryDialog(context, ref, order);
        if (edit != null &&
            edit.deliveryDate != order.deliveryDate &&
            context.mounted) {
          // The date moved: offer to tell the customer (D-5).
          final updated = await ref
              .read(orderRepositoryProvider)
              .detail(order.id);
          if (updated != null && context.mounted) {
            await showMessageSheet(
              context,
              ref,
              updated,
              MessageKind.moved,
              newDate: edit.deliveryDate,
            );
          }
        }
      case _MenuAction.message:
        await showMessageSheet(
          context,
          ref,
          detail,
          detail.money.hasDue && order.status != OrderStatus.ready
              ? MessageKind.due
              : MessageKind.ready,
        );
      case _MenuAction.slip:
        await context.push(AppRoutes.slip(order.id));
      case _MenuAction.setAll:
        final to = await showStatusPicker(context, null);
        if (to != null) {
          await ref
              .read(orderRepositoryProvider)
              .setAllItemsStatus(order.id, to);
        }
      case _MenuAction.duplicate:
        await context.push(
          AppRoutes.newOrder(order.customerId, duplicateOf: order.id),
        );
      case _MenuAction.cancel:
        await showCancelOrderDialog(context, ref, detail);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final garments = ref.watch(garmentsProvider).value ?? const [];
    final money = detail.money;
    String d(String s) => DigitFormatter.format(s, bangla: bangla);

    final canEdit = !order.isCancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(d(l10n.orderNumber(order.number))),
        actions: [
          PopupMenuButton<_MenuAction>(
            key: const ValueKey('order-menu'),
            onSelected: (a) => _onMenu(context, ref, a),
            itemBuilder: (context) => [
              if (canEdit)
                PopupMenuItem(
                  value: _MenuAction.editDelivery,
                  child: Text(l10n.editDetails),
                ),
              if (canEdit)
                PopupMenuItem(
                  value: _MenuAction.setAll,
                  child: Text(l10n.setAllItems),
                ),
              PopupMenuItem(
                value: _MenuAction.message,
                child: Text(l10n.sendMessage),
              ),
              PopupMenuItem(
                value: _MenuAction.slip,
                child: Text(l10n.slipTitle),
              ),
              PopupMenuItem(
                value: _MenuAction.duplicate,
                child: Text(l10n.duplicateOrder),
              ),
              if (canEdit)
                PopupMenuItem(
                  value: _MenuAction.cancel,
                  child: Text(l10n.cancelOrder),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _ActionBar(detail: detail),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- header -------------------------------------------------------
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () =>
                      context.push(AppRoutes.customer(order.customerId)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      detail.customerName,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  d(
                    l10n.deliveryOn(formatStoredDate(order.deliveryDate, lang)),
                  ),
                  key: const ValueKey('delivery-text'),
                  style: theme.textTheme.titleMedium,
                ),
                if (order.trialDate != null)
                  Text(
                    d(l10n.trialOn(formatStoredDate(order.trialDate!, lang))),
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    if (order.isCancelled)
                      Chip(
                        label: Text(l10n.cancelledBadge),
                        backgroundColor: theme.colorScheme.errorContainer,
                      )
                    else
                      StatusChip(order.status),
                    if (order.overbooked && order.isOpen)
                      Chip(
                        key: const ValueKey('overbooked-chip'),
                        label: Text(l10n.overbookedBadge),
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                      ),
                    if (order.urgent && order.isOpen)
                      Chip(
                        label: Text(l10n.urgentBadge),
                        backgroundColor: theme.colorScheme.errorContainer,
                      ),
                  ],
                ),
                if (order.isCancelled && order.cancelReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(order.cancelReason!),
                  ),
                if (order.note != null && order.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      order.note!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ---- items --------------------------------------------------------
          for (final item in detail.items)
            _ItemCard(
              key: ValueKey('item-${item.id}'),
              detail: detail,
              item: item,
              garment: garments
                  .where((g) => g.id == item.garmentTypeId)
                  .firstOrNull,
              editable: canEdit,
            ),
          // ---- money --------------------------------------------------------
          const SizedBox(height: 8),
          _MoneyCard(detail: detail),
          // ---- payments -----------------------------------------------------
          SectionHeader(l10n.paymentsHeader),
          if (detail.payments.isEmpty)
            ListTile(title: Text(l10n.noPayments))
          else
            for (final p in detail.payments)
              ListTile(
                key: ValueKey('payment-${p.id}'),
                dense: true,
                title: Text('${p.kind.label(l10n)} · ${p.method.label(l10n)}'),
                subtitle: Text(
                  [
                    formatStoredDate(p.paidOn, lang),
                    if (p.note != null && p.note!.isNotEmpty) p.note!,
                  ].join(' · '),
                ),
                trailing: MoneyText(p.amount),
              ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  PrimaryButton(
                    label: money.hasDue ? l10n.collectDue : l10n.addPayment,
                    icon: Icons.payments_outlined,
                    onPressed: () => showAddPaymentDialog(
                      context,
                      ref,
                      detail,
                      suggested: money.hasDue ? money.due : null,
                    ),
                  ),
                  if (detail.payments.isNotEmpty)
                    TextButton(
                      onPressed: () => showAddPaymentDialog(
                        context,
                        ref,
                        detail,
                        refund: true,
                      ),
                      child: Text(l10n.recordRefund),
                    ),
                ],
              ),
            ),
          // ---- change log ---------------------------------------------------
          _ChangeLog(orderId: order.id),
        ],
      ),
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.detail,
    required this.item,
    required this.garment,
    required this.editable,
    super.key,
  });

  final OrderDetail detail;
  final OrderItem item;
  final GarmentInfo? garment;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final name = garment?.label(lang) ?? '';
    final styleText = StyleCatalog.summarize(
      garment?.key ?? '',
      item.style,
      lang,
    );
    final next = item.status.next;
    final details = [
      if (styleText.isNotEmpty) styleText,
      if (item.fabricSource != null)
        item.fabricSource == FabricSource.customer
            ? l10n.fabricCustomer
            : l10n.fabricShop,
      if (item.colour != null && item.colour!.isNotEmpty) item.colour!,
      if (item.note != null && item.note!.isNotEmpty) item.note!,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.qty > 1
                        ? '$name × ${DigitFormatter.format('${item.qty}', bangla: bangla)}'
                        : name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                MoneyText(item.price),
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  details.join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                InkWell(
                  key: ValueKey('status-${item.id}'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: editable
                      ? () async {
                          final to = await showStatusPicker(
                            context,
                            item.status,
                          );
                          if (to != null && context.mounted) {
                            await moveItemGuarded(
                              context,
                              ref,
                              detail,
                              item,
                              to,
                            );
                          }
                        }
                      : null,
                  child: StatusChip(item.status),
                ),
                if (editable && next != null)
                  FilledButton.tonal(
                    key: ValueKey('advance-${item.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () =>
                        moveItemGuarded(context, ref, detail, item, next),
                    child: Text(l10n.moveTo(next.label(l10n))),
                  ),
              ],
            ),
            if (item.measurementSetId != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey('snapshot-${item.id}'),
                  onPressed: () => _showSnapshot(context, ref, item, garment),
                  icon: const Icon(Icons.straighten, size: 18),
                  label: Text(l10n.snapshotTitle),
                ),
              ),
            ItemPhotosSection(itemId: item.id, editable: editable),
          ],
        ),
      ),
    );
  }

  Future<void> _showSnapshot(
    BuildContext context,
    WidgetRef ref,
    OrderItem item,
    GarmentInfo? garment,
  ) async {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.read(useBanglaDigitsProvider);
    final m = await ref
        .read(measurementRepositoryProvider)
        .byId(item.measurementSetId!);
    if (!context.mounted) return;
    final fields = garment?.fields ?? const <FieldTemplate>[];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.snapshotTitle),
        content: m == null
            ? Text(l10n.snapshotNone)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DigitFormatter.format(
                        '${l10n.versionLabel(m.version)} · '
                        '${formatStoredDate(m.takenOn, lang)}',
                        bangla: bangla,
                      ),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final f in fields)
                      if (m.values.containsKey(f.key))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(child: Text(f.label(lang))),
                              Text(
                                formatLength(
                                  m.values[f.key]!,
                                  m.unit,
                                  bangla: bangla,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.detail});

  final OrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final money = detail.money;
    final subtotal = Money.sum(detail.items.map((i) => i.price));

    Widget row(String label, Widget value, {bool bold = false, Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: bold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyLarge,
                ),
              ),
              KeyedSubtree(key: key, child: value),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row(l10n.subtotalLabel, MoneyText(subtotal)),
            if (!detail.order.discount.isZero)
              row(l10n.discountLabel, MoneyText(-detail.order.discount)),
            row(l10n.totalLabel, MoneyText(money.total), bold: true),
            row(l10n.paid, MoneyText(money.paid)),
            const Divider(),
            if (money.credit.isPositive)
              row(
                l10n.creditShort,
                MoneyText(money.credit),
                bold: true,
                key: const ValueKey('credit'),
              )
            else
              row(
                l10n.dueShort,
                MoneyText(
                  detail.order.isCancelled ? Money.zero : money.due,
                  highlightDue: true,
                  style: theme.textTheme.titleLarge,
                ),
                bold: true,
                key: const ValueKey('due'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChangeLog extends ConsumerWidget {
  const _ChangeLog({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final log = ref.watch(changeLogProvider(orderId)).value ?? const [];

    String text(AuditEntry e) {
      final detail = e.detail ?? '';
      return switch (e.action) {
        'created' => l10n.logCreated,
        'item_status' => l10n.logItemStatus(_localizeStatuses(detail, l10n)),
        'details_changed' => l10n.logDetails(detail),
        'payment_added' => l10n.logPayment(detail),
        'cancelled' => l10n.logCancelled(detail),
        _ => e.action,
      };
    }

    return ExpansionTile(
      key: const ValueKey('change-log'),
      title: Text(l10n.changeLog),
      children: [
        for (final e in log)
          ListTile(
            dense: true,
            title: Text(text(e)),
            subtitle: Text(
              DigitFormatter.format(
                '${formatStoredDate(Clock.toDateString(e.at), lang)} '
                '${e.at.hour.toString().padLeft(2, '0')}:'
                '${e.at.minute.toString().padLeft(2, '0')}',
                bangla: bangla,
              ),
            ),
          ),
      ],
    );
  }

  /// `received → cut` with the stage names translated.
  String _localizeStatuses(String detail, AppL10n l10n) {
    var out = detail;
    for (final s in OrderStatus.values) {
      out = out.replaceAll(s.dbValue, s.label(l10n));
    }
    return out;
  }
}

/// Main next step for the order: mark it ready, then hand it over (D-3, P-4).
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.detail});

  final OrderDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final order = detail.order;
    if (!order.isOpen) return const SizedBox.shrink();
    final ready = order.status == OrderStatus.ready;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: PrimaryButton(
          key: ValueKey(ready ? 'action-deliver' : 'action-ready'),
          label: ready ? l10n.deliverOrder : l10n.markReady,
          icon: ready
              ? Icons.local_shipping_outlined
              : Icons.check_circle_outline,
          onPressed: () async {
            if (ready) {
              await runDeliverFlow(context, ref, detail);
              return;
            }
            await ref
                .read(orderRepositoryProvider)
                .setAllItemsStatus(order.id, OrderStatus.ready);
            if (!context.mounted) return;
            final updated = await ref
                .read(orderRepositoryProvider)
                .detail(order.id);
            if (updated != null && context.mounted) {
              await showMessageSheet(context, ref, updated, MessageKind.ready);
            }
          },
        ),
      ),
    );
  }
}
