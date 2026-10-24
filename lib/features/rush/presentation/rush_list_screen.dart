import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/status_chip.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/features/orders/presentation/order_labels.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/rush/presentation/rush_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// One big line per open order, soonest delivery first. Swipe right to move
/// the order to its next stage (E-11), for use in the middle of the rush.
class RushListScreen extends ConsumerWidget {
  const RushListScreen({super.key});

  Future<bool> _advance(
    BuildContext context,
    WidgetRef ref,
    OrderSummary summary,
  ) async {
    final l10n = AppL10n.of(context);
    final bangla = ref.read(useBanglaDigitsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final next = await ref
        .read(orderRepositoryProvider)
        .advanceOrder(summary.order.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            DigitFormatter.format(
              next == null
                  ? l10n.rushListReady
                  : l10n.rushListMoved(summary.order.number, next.label(l10n)),
              bangla: bangla,
            ),
          ),
        ),
      );
    // The list is driven by the database stream, so the row never "dismisses".
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final theme = Theme.of(context);
    final season = ref.watch(activeSeasonProvider).value;
    final orders = ref.watch(
      orderSummariesProvider((customerId: null, openOnly: true, filter: null)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rushListTitle)),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
        data: (all) {
          final list = [
            for (final o in all)
              if (season == null ||
                  o.order.deliveryDate.compareTo(season.targetDate) <= 0)
                o,
          ];
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.format_list_numbered,
              title: l10n.rushListEmpty,
              body: '',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  l10n.rushListHint,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = list[index];
                    final o = s.order;
                    final swipeable = o.status != OrderStatus.ready;
                    return Dismissible(
                      key: ValueKey('rush-row-${o.id}'),
                      direction: swipeable
                          ? DismissDirection.startToEnd
                          : DismissDirection.none,
                      background: Container(
                        color: theme.colorScheme.primaryContainer,
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsetsDirectional.only(start: 24),
                        child: Icon(
                          Icons.arrow_forward,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      confirmDismiss: (_) => _advance(context, ref, s),
                      child: InkWell(
                        onTap: () => context.push(AppRoutes.order(o.id)),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 76),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Text(
                                DigitFormatter.format(
                                  '#${o.number}',
                                  bangla: bangla,
                                ),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.customerName,
                                      style: theme.textTheme.titleLarge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      DigitFormatter.format(
                                        formatStoredDate(o.deliveryDate, lang),
                                        bangla: bangla,
                                      ),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusChip(o.status),
                                  const SizedBox(height: 4),
                                  if (s.money.hasDue)
                                    MoneyText(s.money.due, highlightDue: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
