import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/core/db/app_database.dart';
import 'package:tailor_khata/core/ids/id_generator.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/time/clock.dart';
import 'package:tailor_khata/core/units/fraction.dart';
import 'package:tailor_khata/core/units/length.dart';
import 'package:tailor_khata/features/customers/data/drift_customer_repository.dart';
import 'package:tailor_khata/features/customers/domain/customer.dart';
import 'package:tailor_khata/features/measurements/data/drift_measurement_repository.dart';
import 'package:tailor_khata/features/measurements/domain/built_in_templates.dart';
import 'package:tailor_khata/features/measurements/domain/measurement.dart';
import 'package:tailor_khata/features/orders/data/drift_order_repository.dart';
import 'package:tailor_khata/features/orders/domain/order.dart';
import 'package:tailor_khata/features/rush/data/drift_rush_repository.dart';
import 'package:tailor_khata/features/rush/domain/season.dart';

import 'fakes.dart';
import 'flow_helpers.dart';
import 'test_app.dart';

// Shared fixture for the delivery / reminder / photo flow tests.
//
// "Today" is 2026-03-10 (see [TestEnv]). Rahim has a phone and Panjabi
// measurements; Karim has no phone.

Length inches(String text) => Length.fromInches(Fraction.tryParse(text)!);

late String panjabiId;
late String shirtId;
late DriftOrderRepository orders;

/// "Today" in these tests is 2026-03-10 (see [TestEnv]). Rahim has a phone
/// and Panjabi measurements; Karim has no phone.
Future<void> seed(AppDatabase db) async {
  final now = DateTime(2026, 3, 5);
  final customers = DriftCustomerRepository(db);
  await customers.insert(
    Customer(
      id: 'c1',
      name: 'Rahim Uddin',
      phone: '+8801712345678',
      createdAt: now,
      updatedAt: now,
    ),
  );
  await customers.insert(
    Customer(id: 'c2', name: 'Karim Hossain', createdAt: now, updatedAt: now),
  );
  panjabiId = BuiltInTemplates.byKey('panjabi').id;
  shirtId = BuiltInTemplates.byKey('shirt').id;
  await DriftMeasurementRepository(
    db,
    FixedClock(now),
    SequentialIdGenerator('m'),
  ).create(
    NewMeasurement(
      customerId: 'c1',
      garmentTypeId: panjabiId,
      takenOn: '2026-03-01',
      unit: MeasureUnit.inch,
      values: {'length': inches('42'), 'chest': inches('38½')},
    ),
  );
  orders = DriftOrderRepository(db, env.clock, SequentialIdGenerator('o'));
}

Future<OrderDetail> seedOrder({
  String customer = 'c1',
  int price = 1200,
  int advance = 500,
  String delivery = '2026-03-10',
  String garment = 'panjabi',
  Map<String, String> style = const {'collar': 'band'},
  String? measurementSetId,
  int qty = 1,
}) => orders.create(
  NewOrder(
    customerId: customer,
    deliveryDate: delivery,
    items: [
      NewOrderItem(
        garmentTypeId: garment == 'panjabi' ? panjabiId : shirtId,
        price: Money.taka(price),
        style: style,
        measurementSetId: measurementSetId,
        qty: qty,
      ),
    ],
    advance: advance == 0
        ? null
        : NewPayment(
            orderId: '',
            amount: Money.taka(advance),
            method: PayMethod.cash,
            paidOn: '2026-03-05',
            kind: PaymentKind.advance,
          ),
  ),
);

late TestEnv env;
String? clipboard;
late AppDatabase shopDb;

/// Opens the app on [route] with a freshly seeded shop.
Future<void> openShop(
  WidgetTester tester,
  String route, {
  String locale = 'en',
  Future<void> Function()? extra,
  TestEnv? withEnv,
  void Function(TestEnv env)? configure,
}) async {
  phoneScreen(tester);
  clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  env = withEnv ?? TestEnv();
  configure?.call(env);
  addTearDown(env.dispose);
  shopDb = memoryDb();
  await tester.runAsync(() async {
    await seed(shopDb);
    await extra?.call();
  });
  await tester.pumpWidget(
    appOn(shopDb, start: route, locale: locale, env: env),
  );
  await tester.pumpAndSettle();
  // Let the debounced reminder sync run once, as it does on a real start.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The main vertical list or scroll view of the current screen (tab bars and
/// page views scroll sideways and must not be picked).
Finder get verticalScrollable => find
    .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
    .first;

/// Scrolls [finder] into view if it is not built yet, without waiting for
/// timers (snackbars) to run out.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: verticalScrollable,
    );
  }
  await _bringIntoView(tester, finder);
}

/// Scrolls [finder] into view only if it cannot be tapped yet. Scrolling a
/// widget that is already visible can drag a tab view sideways.
Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isNotEmpty) return;
  // A focused text field pulls the scroll view back to itself whenever the
  // layout changes, so let go of the focus before scrolling elsewhere.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: verticalScrollable,
    );
  }
}

/// Lets real asynchronous work (isolates, file I/O, picture encoding) finish.
///
/// Such work needs real time, while the code that follows each step runs in
/// the test's fake clock, so the two are alternated: wait a little for real,
/// then pump to run what became ready, and repeat.
Future<void> settleIo(
  WidgetTester tester, {
  int rounds = 20,
  bool Function()? until,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  for (var i = 0; i < rounds || (until != null && !until()); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (until != null && until()) break;
    if (DateTime.now().isAfter(deadline)) break;
  }
  await tester.pumpAndSettle();
}

/// Taps the widget with [key] but only pumps a frame, so asynchronous work
/// (photo processing) can be awaited by the test afterwards.
Future<void> tapNoSettle(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: verticalScrollable,
    );
  }
  final finder = find.text(text).last;
  await _bringIntoView(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKeyed(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: verticalScrollable,
    );
  }
  await _bringIntoView(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps and lets a snackbar appear without waiting for it to leave.
Future<void> tapAndSee(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Text of the widget with [key]: the widget itself when it is a [Text],
/// otherwise the first text inside it (the value on a stat card).
String textOf(WidgetTester tester, String key) {
  final keyed = tester.widget(find.byKey(ValueKey(key)));
  if (keyed is Text) return keyed.data!;
  return tester
      .widget<Text>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Text),
            )
            .first,
      )
      .data!;
}

Future<OrderDetail> detail(WidgetTester tester, String id) async =>
    (await tester.runAsync(() => orders.detail(id)))!;

Future<List<T>> query<T>(
  WidgetTester tester,
  Future<List<T>> Function() q,
) async => (await tester.runAsync(q))!;

/// Saves a season for the Eid-rush tests. Defaults: ready by 20 March,
/// 10 standard garments a day, every day a working day.
Future<void> seedSeason({
  String target = '2026-03-20',
  int capacity = 1000,
  int mask = 127,
  Set<String> closed = const {},
  String id = 'season1',
}) => DriftRushRepository(shopDb).save(
  Season(
    id: id,
    name: 'Eid-ul-Fitr',
    kind: SeasonKind.eidFitr,
    targetDate: target,
    dailyCapacity: capacity,
    workingDaysMask: mask,
    closedDates: closed,
  ),
);
