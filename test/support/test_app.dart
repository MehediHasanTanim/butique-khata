import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/app.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/db/app_database.dart';

/// Builds the full app on an in-memory database.
Widget buildTestApp(AppDatabase db, {String locale = 'en'}) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    initialLocaleCodeProvider.overrideWithValue(locale),
  ],
  child: const TailorKhataApp(),
);

AppDatabase memoryDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Unmounts the app and lets Drift's stream-cleanup timers run before the
/// database closes, so no timers are pending when the test body ends.
Future<void> shutDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(db.close);
}
