import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Orders tab: all orders by delivery date, and who owes what.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _openOnly = true;

  Future<void> _startNewOrder() async {
    final customerId = await context.push<String>(AppRoutes.pickCustomer);
    if (customerId != null && mounted) {
      await context.push(AppRoutes.newOrder(customerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.ordersTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.ordersTabOrders),
              Tab(text: l10n.ordersTabDues),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _startNewOrder,
          icon: const Icon(Icons.add),
          label: Text(l10n.newOrder),
        ),
        body: TabBarView(
          children: [
            _OrdersList(
              openOnly: _openOnly,
              onToggle: (value) => setState(() => _openOnly = value),
            ),
            const _DuesList(),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends ConsumerWidget {
  const _OrdersList({required this.openOnly, required this.onToggle});

  final bool openOnly;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final orders = ref.watch(
      orderSummariesProvider((customerId: null, openOnly: openOnly)),
    );
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilterChip(
              key: const ValueKey('filter-open'),
              label: Text(l10n.openOnly),
              selected: openOnly,
              onSelected: onToggle,
            ),
          ),
        ),
        Expanded(
          child: orders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: l10n.ordersEmptyTitle,
                  body: l10n.ordersEmptyBody,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 96),
                itemCount: list.length,
                itemBuilder: (context, i) => OrderTile(summary: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

enum _DueSort { amount, age }

class _DuesList extends ConsumerStatefulWidget {
  const _DuesList();

  @override
  ConsumerState<_DuesList> createState() => _DuesListState();
}

class _DuesListState extends ConsumerState<_DuesList> {
  _DueSort _sort = _DueSort.amount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);
    final dues = ref.watch(duesProvider);
    return dues.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.verified_outlined,
            title: l10n.noDuesTitle,
            body: l10n.noDuesBody,
          );
        }
        final sorted = [...list];
        if (_sort == _DueSort.age) {
          sorted.sort((a, b) {
            final byDate = a.oldestDeliveryDate.compareTo(b.oldestDeliveryDate);
            return byDate != 0 ? byDate : b.due.compareTo(a.due);
          });
        }
        final total = Money.sum(list.map((d) => d.due));
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.totalOutstanding,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  MoneyText(
                    total,
                    key: const ValueKey('dues-total'),
                    highlightDue: true,
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<_DueSort>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _DueSort.amount,
                    label: Text(l10n.sortByAmount),
                  ),
                  ButtonSegment(
                    value: _DueSort.age,
                    label: Text(l10n.sortByAge),
                  ),
                ],
                selected: {_sort},
                onSelectionChanged: (v) => setState(() => _sort = v.first),
              ),
            ),
            for (final due in sorted)
              ListTile(
                key: ValueKey('due-${due.customerId}'),
                minTileHeight: 64,
                title: Text(due.customerName),
                subtitle: Text(
                  DigitFormatter.format(
                    l10n.duesSince(
                      due.orderCount,
                      formatStoredDate(due.oldestDeliveryDate, lang),
                    ),
                    bangla: bangla,
                  ),
                ),
                trailing: MoneyText(due.due, highlightDue: true),
                onTap: () => context.push(AppRoutes.customer(due.customerId)),
              ),
          ],
        );
      },
    );
  }
}
