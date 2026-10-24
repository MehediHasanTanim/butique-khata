import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:tailor_khata/core/db/app_database.dart';

/// A removed customer waiting in "Recently deleted".
class DeletedCustomer {
  const DeletedCustomer({
    required this.id,
    required this.name,
    required this.phone,
    required this.deletedAt,
    required this.hasHistory,
  });

  final String id;
  final String name;
  final String? phone;
  final DateTime deletedAt;

  /// Has measurements, orders or photos. Such a customer is never purged
  /// automatically: history is append-only and losing it is the worst failure.
  final bool hasHistory;

  /// Whole days until the automatic purge, 0 when due today.
  int daysLeft(DateTime now, {int retentionDays = 30}) {
    final left = deletedAt
        .add(Duration(days: retentionDays))
        .difference(now)
        .inDays;
    return left < 0 ? 0 : left;
  }
}

/// Soft-delete recovery (B-8): list, restore and purge removed customers.
class DeletedCustomerRepository {
  DeletedCustomerRepository(this._db);

  final AppDatabase _db;

  /// How long a removed customer with no history is kept.
  static const int retentionDays = 30;

  static const String _noHistory = '''
NOT EXISTS (SELECT 1 FROM measurement_set m WHERE m.customer_id = c.id)
AND NOT EXISTS (SELECT 1 FROM customer_order o WHERE o.customer_id = c.id)
AND NOT EXISTS (SELECT 1 FROM attachment a
                WHERE a.owner_type = 'customer' AND a.owner_id = c.id)
AND c.photo_path IS NULL''';

  Stream<List<DeletedCustomer>> watchDeleted() => _db
      .customSelect(
        'SELECT c.id, c.name, c.phone, c.deleted_at, '
        'NOT ($_noHistory) AS has_history '
        'FROM customer c WHERE c.deleted_at IS NOT NULL '
        'ORDER BY c.deleted_at DESC',
        readsFrom: {
          _db.customer,
          _db.measurementSet,
          _db.customerOrder,
          _db.attachment,
        },
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            DeletedCustomer(
              id: r.read<String>('id'),
              name: r.read<String>('name'),
              phone: r.readNullable<String>('phone'),
              deletedAt: DateTime.fromMillisecondsSinceEpoch(
                r.read<int>('deleted_at'),
              ),
              hasHistory: r.read<int>('has_history') != 0,
            ),
        ],
      );

  /// Uses `customUpdate` (not `customStatement`) so lists showing customers
  /// refresh straight away.
  Future<void> restore(String id, DateTime now) => _db.customUpdate(
    'UPDATE customer SET deleted_at = NULL, updated_at = ? WHERE id = ?',
    variables: [
      Variable<int>(now.millisecondsSinceEpoch),
      Variable<String>(id),
    ],
    updates: {_db.customer},
    updateKind: UpdateKind.update,
  );

  /// Permanently removes customers deleted more than [retentionDays] ago
  /// that have no history. Returns how many were removed.
  Future<int> purgeExpired(DateTime now) async {
    final cutoff = now
        .subtract(const Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    return _db.customUpdate(
      'DELETE FROM customer AS c WHERE c.deleted_at IS NOT NULL '
      'AND c.deleted_at < ? AND $_noHistory',
      variables: [Variable<int>(cutoff)],
      updates: {_db.customer},
      updateKind: UpdateKind.delete,
    );
  }
}
