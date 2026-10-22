import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/orders/data/attachment_repository.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/create_order.dart';
import 'package:tailor_khata/features/orders/domain/delivery.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/orders/domain/order_repository.dart';
import 'package:tailor_khata/features/orders/domain/photo_attachment.dart';

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
typedef OrderListKey = ({
  String? customerId,
  bool openOnly,
  OrderFilter? filter,
});

final orderSummariesProvider = StreamProvider.autoDispose
    .family<List<OrderSummary>, OrderListKey>(
      (ref, key) => ref
          .watch(orderRepositoryProvider)
          .watchSummaries(
            customerId: key.customerId,
            openOnly: key.openOnly,
            filter: key.filter,
          ),
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

final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => AttachmentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(mediaStoreProvider),
    ref.watch(clockProvider),
    ref.watch(idGeneratorProvider),
  ),
);

/// Photos of one garment in an order.
final itemPhotosProvider = StreamProvider.autoDispose
    .family<List<PhotoAttachment>, String>(
      (ref, itemId) => ref
          .watch(attachmentRepositoryProvider)
          .watch(AttachmentOwner.orderItem, itemId),
    );

// ---- deliveries / dashboard -----------------------------------------------

/// Today's date as the app sees it (rebuilt only when the clock provider is).
final todayProvider = Provider<String>(
  (ref) => ref.watch(clockProvider).today(),
);

final deliveryCountsProvider = StreamProvider.autoDispose<DeliveryCounts>((
  ref,
) {
  final clock = ref.watch(clockProvider);
  final days = ref.watch(appSettingsProvider.select((s) => s.uncollectedDays));
  return ref
      .watch(orderRepositoryProvider)
      .watchDeliveryCounts(
        buckets: DeliveryBuckets.of(clock.today()),
        uncollectedBeforeMillis: clock
            .now()
            .subtract(Duration(days: days))
            .millisecondsSinceEpoch,
      );
});

final dashboardProvider = StreamProvider.autoDispose<DashboardStats>((ref) {
  final clock = ref.watch(clockProvider);
  final now = clock.now();
  return ref
      .watch(orderRepositoryProvider)
      .watchDashboard(
        today: clock.today(),
        startOfTodayMillis: DateTime(
          now.year,
          now.month,
          now.day,
        ).millisecondsSinceEpoch,
      );
});

final openDeliveryDaysProvider = StreamProvider.autoDispose<List<DeliveryDay>>(
  (ref) => ref.watch(orderRepositoryProvider).watchOpenDeliveryDays(),
);
