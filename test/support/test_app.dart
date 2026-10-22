import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

AppDatabase memoryDb() => AppDatabase(NativeDatabase.memory());
