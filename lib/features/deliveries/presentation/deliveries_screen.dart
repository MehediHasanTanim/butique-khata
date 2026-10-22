import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/time/date_format.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

enum DeliveryTab {
  today,
  tomorrow,
  week,
  overdue,
  uncollected;

  static DeliveryTab fromName(String? name) => DeliveryTab.values.firstWhere(
    (t) => t.name == name,
    orElse: () => DeliveryTab.today,
  );
}

/// What is due: today, tomorrow, this week, overdue, and garments that are
/// ready but not collected (D-1, D-6).
class DeliveriesScreen extends ConsumerWidget {
  const DeliveriesScreen({this.initialTab = DeliveryTab.today, super.key});

  final DeliveryTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final counts =
        ref.watch(deliveryCountsProvider).value ?? const DeliveryCounts();

    String label(DeliveryTab tab) {
      final (text, count) = switch (tab) {
        DeliveryTab.today => (l10n.tabToday, counts.today),
        DeliveryTab.tomorrow => (l10n.tabTomorrow, counts.tomorrow),
        DeliveryTab.week => (l10n.tabWeek, counts.week),
        DeliveryTab.overdue => (l10n.tabOverdue, counts.overdue),
        DeliveryTab.uncollected => (l10n.tabUncollected, counts.uncollected),
      };
      return DigitFormatter.format(
        l10n.tabWithCount(text, count),
        bangla: bangla,
      );
    }

    return DefaultTabController(
      length: DeliveryTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.deliveriesTitle),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final tab in DeliveryTab.values)
                Tab(key: ValueKey('tab-${tab.name}'), text: label(tab)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final tab in DeliveryTab.values) _DeliveryList(tab: tab),
          ],
        ),
      ),
    );
  }
}

class _DeliveryList extends ConsumerStatefulWidget {
  const _DeliveryList({required this.tab});

  final DeliveryTab tab;

  @override
  ConsumerState<_DeliveryList> createState() => _DeliveryListState();
}

class _DeliveryListState extends ConsumerState<_DeliveryList>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 30;

  List<OrderSummary> _items = const [];
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  ({String? from, String? to}) _range(DeliveryBuckets b) {
    final today = Clock.parseDate(b.today);
    final yesterday = Clock.toDateString(
      DateTime(today.year, today.month, today.day - 1),
    );
    return switch (widget.tab) {
      DeliveryTab.today => (from: b.today, to: b.today),
      DeliveryTab.tomorrow => (from: b.tomorrow, to: b.tomorrow),
      DeliveryTab.week => (from: b.weekStart, to: b.weekEnd),
      DeliveryTab.overdue => (from: null, to: yesterday),
      DeliveryTab.uncollected => (from: null, to: null),
    };
  }

  Future<List<OrderSummary>> _fetch({
    DeliveryCursor? after,
    required int limit,
  }) {
    final repo = ref.read(orderRepositoryProvider);
    final clock = ref.read(clockProvider);
    if (widget.tab == DeliveryTab.uncollected) {
      final days = ref.read(appSettingsProvider).uncollectedDays;
      return repo.uncollected(
        olderThanMillis: clock
            .now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch,
      );
    }
    final range = _range(DeliveryBuckets.of(clock.today()));
    return repo.deliveriesPage(
      from: range.from,
      to: range.to,
      after: after,
      limit: limit,
    );
  }

  /// Reloads from the start, keeping at least as many rows as are on screen.
  Future<void> _reload() async {
    final want = _items.length < _pageSize ? _pageSize : _items.length;
    if (widget.tab == DeliveryTab.uncollected) {
      final all = await _fetch(limit: 0);
      if (!mounted) return;
      setState(() {
        _items = all;
        _hasMore = false;
        _loading = false;
      });
      return;
    }
    final page = await _fetch(limit: want + 1);
    if (!mounted) return;
    setState(() {
      _hasMore = page.length > want;
      _items = page.take(want).toList();
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    final last = _items.last.order;
    final page = await _fetch(
      after: DeliveryCursor(last.deliveryDate, last.number),
      limit: _pageSize + 1,
    );
    if (!mounted) return;
    setState(() {
      _hasMore = page.length > _pageSize;
      _items = [..._items, ...page.take(_pageSize)];
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppL10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final bangla = ref.watch(useBanglaDigitsProvider);

    // Any change to orders moves the counts; reload then.
    ref.listen(deliveryCountsProvider, (_, _) => _reload());

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.event_available_outlined,
        title: l10n.nothingDue,
        body: l10n.nothingDueBody,
      );
    }

    final theme = Theme.of(context);
    final rows = <Widget>[];
    String? lastDate;
    for (final summary in _items) {
      final order = summary.order;
      if (widget.tab != DeliveryTab.uncollected &&
          order.deliveryDate != lastDate) {
        lastDate = order.deliveryDate;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              DigitFormatter.format(
                formatStoredDate(order.deliveryDate, lang),
                bangla: bangla,
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      rows.add(OrderTile(summary: summary));
      if (widget.tab == DeliveryTab.uncollected) {
        final days = ref
            .read(clockProvider)
            .now()
            .difference(order.updatedAt)
            .inDays;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 4),
            child: Text(
              DigitFormatter.format(l10n.readyForDays(days), bangla: bangla),
              style: theme.textTheme.bodySmall,
            ),
          ),
        );
      }
    }
    if (_hasMore) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    key: const ValueKey('load-more'),
                    onPressed: _loadMore,
                    child: Text(l10n.loadMore),
                  ),
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 300) _loadMore();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: rows,
      ),
    );
  }
}
