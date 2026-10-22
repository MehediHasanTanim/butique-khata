/// Per-item production pipeline (Spec O-7). Order is the forward direction.
enum OrderStatus {
  received,
  cut,
  stitching,
  finishing,
  ready,
  delivered;

  /// Value persisted in the database.
  String get dbValue => name;

  static OrderStatus fromDb(String value) =>
      OrderStatus.values.firstWhere((s) => s.name == value);

  /// The next stage, or null at the end of the pipeline.
  OrderStatus? get next => index == OrderStatus.values.length - 1
      ? null
      : OrderStatus.values[index + 1];

  /// Forward moves of any length are allowed, and one step back to fix a
  /// mistake (O-7). Staying put is not a move.
  bool canMoveTo(OrderStatus target) =>
      target.index > index || target.index == index - 1;

  /// An order is as far along as its slowest item (O-7). `delivered` only
  /// when every item is delivered.
  static OrderStatus rollUp(Iterable<OrderStatus> items) {
    OrderStatus? slowest;
    for (final status in items) {
      if (slowest == null || status.index < slowest.index) slowest = status;
    }
    return slowest ?? OrderStatus.received;
  }
}
