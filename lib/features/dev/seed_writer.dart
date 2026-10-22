import 'package:drift/drift.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/text/name_normalizer.dart';
import 'package:tailor_khata/core/text/phone_normalizer.dart';
import 'package:tailor_khata/features/dev/seed_generator.dart';

/// Persists synthetic customers (debug builds) and removes them again.
/// Seeded rows carry [marker] in `note` so real data is never touched.
class SeedWriter {
  SeedWriter(this._db, [this._ids = const UuidV7Generator()]);

  static const String marker = '__seed__';

  final AppDatabase _db;
  final IdGenerator _ids;

  /// Inserts [customers] in one transaction and returns how many.
  Future<int> write(List<SeedCustomer> customers) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((batch) {
      batch.insertAll(_db.customer, [
        for (final c in customers)
          CustomerCompanion.insert(
            id: _ids.newId(),
            name: c.name,
            nameNorm: NameNormalizer.normalize(c.name),
            phone: Value('+88${c.phone}'),
            phoneDigits: Value(PhoneNormalizer.parse(c.phone)?.searchDigits),
            note: const Value(marker),
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
    return customers.length;
  }

  /// Deletes all seeded customers; returns how many were removed.
  Future<int> clear() =>
      (_db.delete(_db.customer)..where((t) => t.note.equals(marker))).go();
}
