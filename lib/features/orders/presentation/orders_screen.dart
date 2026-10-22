import 'dart:async';

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
import 'package:tailor_khata/features/measurements/presentation/measurement_providers.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/presentation/order_filter_sheet.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// Orders tab: all orders by delivery date, with search and filters, and a
/// Dues tab showing who owes what.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({this.initialTab = 0, super.key});

  /// 0 = orders, 1 = dues.
  final int initialTab;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  bool _openOnly = true;
  OrderFilter _filter = const OrderFilter();

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
      initialIndex: widget.initialTab,
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
              filter: _filter,
              onToggleOpen: (value) => setState(() => _openOnly = value),
              onFilter: (value) => setState(() => _filter = value),
            ),
            const _DuesList(),
          ],
        ),
      ),
    );
  }
}

class _OrdersList extends ConsumerStatefulWidget {
  const _OrdersList({
    required this.openOnly,
    required this.filter,
    required this.onToggleOpen,
    required this.onFilter,
  });

  final bool openOnly;
  final OrderFilter filter;
  final ValueChanged<bool> onToggleOpen;
  final ValueChanged<OrderFilter> onFilter;

  @override
  ConsumerState<_OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends ConsumerState<_OrdersList> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) widget.onFilter(widget.filter.copyWith(query: value));
    });
  }

  Future<void> _openFilters() async {
    final garments = await ref.read(measurementRepositoryProvider).garments();
    if (!mounted) return;
    final result = await showModalBottomSheet<OrderFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          OrderFilterSheet(initial: widget.filter, garments: garments),
    );
    if (result != null) widget.onFilter(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final filter = widget.filter;
    final active = filter.activeCount;
    // Searching or filtering looks at every order, not only open ones.
    final openOnly = widget.openOnly && filter.isEmpty;
    final orders = ref.watch(
      orderSummariesProvider((
        customerId: null,
        openOnly: openOnly,
        filter: filter.isEmpty ? null : filter,
      )),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('order-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: l10n.orderSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: IconButton.filledTonal(
                  key: const ValueKey('order-filter-button'),
                  tooltip: l10n.filterTitle,
                  icon: const Icon(Icons.tune),
                  onPressed: _openFilters,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilterChip(
              key: const ValueKey('filter-open'),
              label: Text(l10n.openOnly),
              selected: openOnly,
              onSelected: filter.isEmpty ? widget.onToggleOpen : null,
            ),
          ),
        ),
        Expanded(
          child: orders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.errorGenericTitle)),
            data: (list) {
              if (list.isEmpty) {
                return filter.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: l10n.ordersEmptyTitle,
                        body: l10n.ordersEmptyBody,
                      )
                    : EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: l10n.filterNoMatch,
                        body: '',
                        action: TextButton(
                          key: const ValueKey('filter-clear-inline'),
                          onPressed: () {
                            _search.clear();
                            widget.onFilter(const OrderFilter());
                          },
                          child: Text(l10n.filterClear),
                        ),
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
