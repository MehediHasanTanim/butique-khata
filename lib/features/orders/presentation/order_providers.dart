import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/create_order.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => DriftOrderRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
    ref.watch(idGeneratorProvider),
  ),
);

final createOrderProvider = Provider<CreateOrder>(
  (ref) => CreateOrder(ref.watch(orderRepositoryProvider)),
);

/// Which orders a list shows.
typedef OrderListKey = ({String? customerId, bool openOnly});

final orderSummariesProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, OrderListKey>(
      (ref, key) => ref
          .watch(orderRepositoryProvider)
          .watchSummaries(customerId: key.customerId, openOnly: key.openOnly),
    );

final orderDetailProvider = StreamProvider.autoDispose
    .family<OrderDetail?, String>(
      (ref, id) => ref.watch(orderRepositoryProvider).watchDetail(id),
    );

final duesProvider = StreamProvider.autoDispose<List<CustomerDue>>(
  (ref) => ref.watch(orderRepositoryProvider).watchDues(),
);

final customerDueProvider = StreamProvider.autoDispose.family<Money, String>(
  (ref, customerId) =>
      ref.watch(orderRepositoryProvider).watchCustomerDue(customerId),
);

final changeLogProvider = StreamProvider.autoDispose
    .family<List<AuditEntry>, String>(
      (ref, orderId) =>
          ref.watch(orderRepositoryProvider).watchChangeLog(orderId),
    );
