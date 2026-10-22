import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';

/// A delivery was attempted while the customer still owes money and nobody
/// confirmed it (P-4). Carries the amount so the UI can offer to collect it.
class DueOutstandingError implements Exception {
  const DueOutstandingError(this.due);

  final Money due;

  @override
  String toString() => 'DueOutstandingError($due)';
}

/// Position in the delivery list for keyset paging: orders are sorted by
/// delivery date, then slip number.
class DeliveryCursor {
  const DeliveryCursor(this.date, this.number);

  final String date;
  final int number;
}

/// How many open orders fall in each delivery bucket (D-1).
class DeliveryCounts {
  const DeliveryCounts({
    this.overdue = 0,
    this.today = 0,
    this.tomorrow = 0,
    this.week = 0,
    this.uncollected = 0,
  });

  final int overdue;
  final int today;
  final int tomorrow;

  /// Two to seven days from today.
  final int week;

  /// Ready for a while but not yet handed over (D-6).
  final int uncollected;

  @override
  bool operator ==(Object other) =>
      other is DeliveryCounts &&
      other.overdue == overdue &&
      other.today == today &&
      other.tomorrow == tomorrow &&
      other.week == week &&
      other.uncollected == uncollected;

  @override
  int get hashCode => Object.hash(overdue, today, tomorrow, week, uncollected);
}

/// Open orders due on one day; input for reminders (D-2).
class DeliveryDay {
  const DeliveryDay({
    required this.date,
    required this.count,
    required this.firstOrderId,
  });

  final String date;
  final int count;

  /// An order of that day, used for a deep link when [count] is 1.
  final String firstOrderId;
}

/// Numbers for the Home dashboard (S-3).
class DashboardStats {
  const DashboardStats({
    this.dueToday = 0,
    this.overdue = 0,
    this.totalDue = Money.zero,
    this.receivedToday = 0,
  });

  final int dueToday;
  final int overdue;
  final Money totalDue;
  final int receivedToday;

  @override
  bool operator ==(Object other) =>
      other is DashboardStats &&
      other.dueToday == dueToday &&
      other.overdue == overdue &&
      other.totalDue == totalDue &&
      other.receivedToday == receivedToday;

  @override
  int get hashCode => Object.hash(dueToday, overdue, totalDue, receivedToday);
}

/// Filters for the order list (S-2).
class OrderFilter {
  const OrderFilter({
    this.query = '',
    this.statuses = const {},
    this.dueOnly = false,
    this.garmentTypeId,
    this.from,
    this.to,
  });

  /// Order number (`12`, `#12`), customer name or phone digits.
  final String query;
  final Set<OrderStatus> statuses;
  final bool dueOnly;
  final String? garmentTypeId;

  /// Delivery date range, inclusive, `YYYY-MM-DD`.
  final String? from;
  final String? to;

  bool get isEmpty =>
      query.trim().isEmpty &&
      statuses.isEmpty &&
      !dueOnly &&
      garmentTypeId == null &&
      from == null &&
      to == null;

  /// Number of active filter groups (for a badge).
  int get activeCount =>
      (statuses.isEmpty ? 0 : 1) +
      (dueOnly ? 1 : 0) +
      (garmentTypeId == null ? 0 : 1) +
      (from == null && to == null ? 0 : 1);

  OrderFilter copyWith({
    String? query,
    Set<OrderStatus>? statuses,
    bool? dueOnly,
    String? Function()? garmentTypeId,
    String? Function()? from,
    String? Function()? to,
  }) => OrderFilter(
    query: query ?? this.query,
    statuses: statuses ?? this.statuses,
    dueOnly: dueOnly ?? this.dueOnly,
    garmentTypeId: garmentTypeId != null ? garmentTypeId() : this.garmentTypeId,
    from: from != null ? from() : this.from,
    to: to != null ? to() : this.to,
  );

  @override
  bool operator ==(Object other) =>
      other is OrderFilter &&
      other.query == query &&
      other.dueOnly == dueOnly &&
      other.garmentTypeId == garmentTypeId &&
      other.from == from &&
      other.to == to &&
      other.statuses.length == statuses.length &&
      other.statuses.containsAll(statuses);

  @override
  int get hashCode => Object.hash(
    query,
    dueOnly,
    garmentTypeId,
    from,
    to,
    Object.hashAllUnordered(statuses),
  );
}

/// The date boundaries of the delivery tabs for a given "today".
class DeliveryBuckets {
  const DeliveryBuckets._(
    this.today,
    this.tomorrow,
    this.weekStart,
    this.weekEnd,
  );

  factory DeliveryBuckets.of(String today) {
    final d = Clock.parseDate(today);
    String plus(int days) =>
        Clock.toDateString(DateTime(d.year, d.month, d.day + days));
    return DeliveryBuckets._(today, plus(1), plus(2), plus(7));
  }

  final String today;
  final String tomorrow;

  /// "This week" is two to seven days from today.
  final String weekStart;
  final String weekEnd;
}
