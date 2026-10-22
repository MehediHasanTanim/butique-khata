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
}
