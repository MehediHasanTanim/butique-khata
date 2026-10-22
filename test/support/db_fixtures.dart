import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Raw-SQL snapshots of each released schema version (S0-09).
///
/// Migration tests build a database from the *old* snapshot, open it with the
/// current [AppDatabase], and assert data survives. When a schema version is
/// bumped, add its snapshot here and a `fromXToY` test.
class DbFixtures {
  const DbFixtures._();

  /// Schema version 1: `app_setting` and `audit_log`.
  static void createV1(sqlite.Database db, {bool withData = true}) {
    db.execute('''
      CREATE TABLE app_setting (
        "key" TEXT NOT NULL,
        value TEXT NOT NULL,
        PRIMARY KEY ("key")
      );
    ''');
    db.execute('''
      CREATE TABLE audit_log (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        at INTEGER NOT NULL,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        diff_json TEXT NULL
      );
    ''');
    if (withData) {
      db.execute("INSERT INTO app_setting VALUES ('locale', 'bn')");
      db.execute(
        'INSERT INTO audit_log (at, entity, entity_id, action) '
        "VALUES (1, 'customer', 'c1', 'create')",
      );
    }
    db.execute('PRAGMA user_version = 1');
  }

  /// Writes a v1 database file at [file] (plain SQLite, no encryption).
  static void writeV1File(File file) {
    final db = sqlite.sqlite3.open(file.path);
    try {
      createV1(db);
    } finally {
      db.close();
    }
  }
}
