import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/status_chip.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// One row in an order list: slip number, customer, delivery, status, due.
class OrderTile extends ConsumerWidget {
  const OrderTile({required this.summary, this.showCustomer = true, super.key});

  final OrderSummary summary;
  final bool showCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final order = summary.order;
    final money = summary.money;

    final subtitle = DigitFormatter.format(
      '${l10n.deliveryOn(formatStoredDate(order.deliveryDate, lang))} · '
      '${l10n.itemsCount(summary.itemCount)}',
      bangla: bangla,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        key: ValueKey('order-${order.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(AppRoutes.order(order.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  DigitFormatter.format('${order.number}', bangla: bangla),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showCustomer)
                      Text(
                        summary.customerName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                    if (order.urgent && order.isOpen)
                      Text(
                        l10n.urgentBadge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (order.isCancelled)
                    Text(
                      l10n.cancelledBadge,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  else
                    StatusChip(order.status),
                  const SizedBox(height: 6),
                  if (order.isCancelled)
                    const SizedBox.shrink()
                  else if (money.hasDue)
                    MoneyText(money.due, highlightDue: true)
                  else
                    Text(
                      l10n.paidInFull,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF2E7D32),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
