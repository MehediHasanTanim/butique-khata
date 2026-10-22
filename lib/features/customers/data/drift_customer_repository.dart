import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/customers/domain/customer_repository.dart';

class DriftCustomerRepository implements CustomerRepository {
  DriftCustomerRepository(this._db);

  final AppDatabase _db;

  static Customer _toDomain(CustomerRow row) => Customer(
    id: row.id,
    name: row.name,
    phone: row.phone,
    address: row.address,
    note: row.note,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
  );

  static CustomerCompanion _toCompanion(Customer c) {
    final digits = c.phone == null
        ? null
        : PhoneNormalizer.parse(c.phone!)?.searchDigits;
    return CustomerCompanion(
      id: Value(c.id),
      name: Value(c.name),
      nameNorm: Value(NameNormalizer.normalize(c.name)),
      phone: Value(c.phone),
      phoneDigits: Value(digits),
      address: Value(c.address),
      note: Value(c.note),
      createdAt: Value(c.createdAt.millisecondsSinceEpoch),
      updatedAt: Value(c.updatedAt.millisecondsSinceEpoch),
    );
  }

  SimpleSelectStatement<$CustomerTable, CustomerRow> get _active =>
      _db.select(_db.customer)..where((t) => t.deletedAt.isNull());

  @override
  Future<Customer?> byId(String id) async {
    final row = await (_active..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<Customer?> watchById(String id) =>
      (_active..where((t) => t.id.equals(id))).watchSingleOrNull().map(
        (row) => row == null ? null : _toDomain(row),
      );

  @override
  Stream<List<Customer>> watchAll() =>
      (_active..orderBy([(t) => OrderingTerm.asc(t.nameNorm)])).watch().map(
        (rows) => rows.map(_toDomain).toList(),
      );

  @override
  Stream<List<Customer>> watchSearch(String query, {int limit = 100}) {
    final built = _buildSearch(query, limit);
    if (built == null) {
      return (_active
            ..orderBy([(t) => OrderingTerm.asc(t.nameNorm)])
            ..limit(limit))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());
    }
    return _db
        .customSelect(
          built.sql,
          variables: built.variables,
          readsFrom: {_db.customer},
        )
        .watch()
        .map(_mapRows);
  }

  @override
  Future<List<Customer>> search(String query, {int limit = 100}) async {
    final built = _buildSearch(query, limit);
    if (built == null) {
      final rows =
          await (_active
                ..orderBy([(t) => OrderingTerm.asc(t.nameNorm)])
                ..limit(limit))
              .get();
      return rows.map(_toDomain).toList();
    }
    final rows = await _db
        .customSelect(
          built.sql,
          variables: built.variables,
          readsFrom: {_db.customer},
        )
        .get();
    return _mapRows(rows);
  }

  List<Customer> _mapRows(List<QueryRow> rows) =>
      rows.map((r) => _toDomain(_db.customer.map(r.data))).toList();

  /// Returns null for an empty query.
  _Search? _buildSearch(String query, int limit) {
    final normalized = NameNormalizer.normalize(query);
    if (normalized.isEmpty) return null;

    final phoneLike = RegExp(r'^[\d\s+\-()]+$').hasMatch(normalized);
    if (phoneLike) {
      var digits = normalized.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return null;
      if (digits.startsWith('880') && digits.length > 3) {
        digits = '0${digits.substring(3)}';
      }
      return _Search(
        'SELECT * FROM customer WHERE deleted_at IS NULL '
        "AND phone_digits LIKE '%' || ? || '%' "
        'ORDER BY name_norm LIMIT ?',
        [Variable<String>(digits), Variable<int>(limit)],
      );
    }

    final terms = normalized
        .split(' ')
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .join(' ');
    return _Search(
      'SELECT c.* FROM customer c JOIN customer_fts f ON f.rowid = c.rowid '
      'WHERE customer_fts MATCH ? AND c.deleted_at IS NULL '
      'ORDER BY c.name_norm LIMIT ?',
      [Variable<String>(terms), Variable<int>(limit)],
    );
  }

  @override
  Future<Customer?> findByPhone(String phone, {String? excludeId}) async {
    final query = _active..where((t) => t.phone.equals(phone));
    if (excludeId != null) query.where((t) => t.id.equals(excludeId).not());
    final row = await (query..limit(1)).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<void> insert(Customer customer) =>
      _db.into(_db.customer).insert(_toCompanion(customer));

  @override
  Future<void> update(Customer customer) {
    final companion = _toCompanion(customer)
        .copyWith(createdAt: const Value.absent());
    return (_db.update(
      _db.customer,
    )..where((t) => t.id.equals(customer.id))).write(companion);
  }

  @override
  Future<void> softDelete(String id, DateTime at) =>
      (_db.update(_db.customer)..where((t) => t.id.equals(id))).write(
        CustomerCompanion(
          deletedAt: Value(at.millisecondsSinceEpoch),
          updatedAt: Value(at.millisecondsSinceEpoch),
        ),
      );

  @override
  Future<void> restore(String id, DateTime at) =>
      (_db.update(_db.customer)..where((t) => t.id.equals(id))).write(
        CustomerCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(at.millisecondsSinceEpoch),
        ),
      );

  @override
  Future<int> count() async {
    final expr = _db.customer.id.count();
    final query = _db.selectOnly(_db.customer)
      ..addColumns([expr])
      ..where(_db.customer.deletedAt.isNull());
    return (await query.getSingle()).read(expr) ?? 0;
  }
}

class _Search {
  const _Search(this.sql, this.variables);
  final String sql;
  final List<Variable<Object>> variables;
}
