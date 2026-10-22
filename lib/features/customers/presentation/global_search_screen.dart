import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/routes.dart';
import 'package:tailor_khata/core/l10n/digit_formatter.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_tile.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

/// One search box for customers (name, phone) and orders (number, name,
/// phone) (S-1).
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _controller = TextEditingController();
  Timer? _timer;
  String _query = '';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final bangla = ref.watch(useBanglaDigitsProvider);
    final customers = _query.isEmpty
        ? const AsyncValue<List<Customer>>.data([])
        : ref.watch(_searchCustomersProvider(_query));
    final orders = _query.isEmpty
        ? const AsyncValue<List<OrderSummary>>.data([])
        : ref.watch(
            orderSummariesProvider((
              customerId: null,
              openOnly: false,
              filter: OrderFilter(query: _query),
            )),
          );
    final customerList = customers.value ?? const <Customer>[];
    final orderList = (orders.value ?? const <OrderSummary>[])
        .take(20)
        .toList();
    final nothing =
        _query.isNotEmpty && customerList.isEmpty && orderList.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('global-search-field'),
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            border: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      body: ListView(
        children: [
          if (nothing)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(l10n.searchNothing)),
            ),
          if (customerList.isNotEmpty) SectionHeader(l10n.searchCustomers),
          for (final c in customerList)
            ListTile(
              key: ValueKey('search-customer-${c.id}'),
              minTileHeight: 56,
              leading: CircleAvatar(child: Text(c.initial)),
              title: Text(c.name),
              subtitle: c.phoneDisplay == null
                  ? null
                  : Text(
                      DigitFormatter.format(c.phoneDisplay!, bangla: bangla),
                    ),
              onTap: () => context.push(AppRoutes.customer(c.id)),
            ),
          if (orderList.isNotEmpty) SectionHeader(l10n.searchOrders),
          for (final o in orderList) OrderTile(summary: o),
        ],
      ),
    );
  }
}

final _searchCustomersProvider = StreamProvider.autoDispose
    .family<List<Customer>, String>(
      (ref, query) =>
          ref.watch(customerRepositoryProvider).watchSearch(query, limit: 20),
    );
