import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/app.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/router.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/db/app_database.dart';

import 'fakes.dart';

/// Full app on [db], optionally starting at route [start]. Platform
/// services are fakes held by [env] (a fresh one if not given).
Widget appOn(
  AppDatabase db, {
  String locale = 'en',
  String? start,
  TestEnv? env,
  List<Override> extra = const [],
}) {
  final e = env ?? TestEnv();
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      initialLocaleCodeProvider.overrideWithValue(locale),
      clockProvider.overrideWithValue(e.clock),
      initialAppSettingsProvider.overrideWithValue(e.settings),
      notificationServiceProvider.overrideWithValue(e.notifications),
      externalLauncherProvider.overrideWithValue(e.launcher),
      fileSharerProvider.overrideWithValue(e.sharer),
      photoSourceProvider.overrideWithValue(e.photos),
      mediaStoreProvider.overrideWithValue(e.media),
      ...extra,
    ],
    child: TailorKhataApp(
      router: start == null ? null : buildRouter(initialLocation: start),
    ),
  );
}

void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> tapKey(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey(id)));
  await tester.pump();
}

/// Types on the measurement keypad. `<` is backspace, `.` the decimal key,
/// ⅛¼⅜½⅝¾⅞ the fraction keys.
Future<void> typeKeys(WidgetTester tester, String keys) async {
  for (final char in keys.split('')) {
    final id = switch (char) {
      '.' => 'key-decimal',
      '<' => 'key-backspace',
      '⅛' => 'key-frac-1',
      '¼' => 'key-frac-2',
      '⅜' => 'key-frac-3',
      '½' => 'key-frac-4',
      '⅝' => 'key-frac-5',
      '¾' => 'key-frac-6',
      '⅞' => 'key-frac-7',
      _ => 'key-$char',
    };
    await tapKey(tester, id);
  }
}
