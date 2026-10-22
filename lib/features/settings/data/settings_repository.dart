import 'package:tailor_khata/core/db/app_database.dart';

/// Keys stored in the `app_setting` table.
abstract class SettingKeys {
  static const String locale = 'locale';
}

/// Reads and writes key/value settings.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.appSetting,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) => _db
      .into(_db.appSetting)
      .insertOnConflictUpdate(
        AppSettingCompanion.insert(key: key, value: value),
      );

  Future<void> remove(String key) =>
      (_db.delete(_db.appSetting)..where((t) => t.key.equals(key))).go();

  Stream<String?> watch(String key) =>
      (_db.select(_db.appSetting)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);
}
