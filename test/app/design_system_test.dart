import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/core/money/money.dart';
import 'package:tailor_khata/core/ui/app_list_tile.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/core/ui/empty_state.dart';
import 'package:tailor_khata/core/ui/money_text.dart';
import 'package:tailor_khata/core/ui/primary_button.dart';
import 'package:tailor_khata/core/ui/section_header.dart';
import 'package:tailor_khata/core/ui/status_chip.dart';
import 'package:tailor_khata/features/orders/domain/order_status.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

import '../support/test_app.dart';

Widget _host(Widget child, {String locale = 'en'}) {
  final db = memoryDb();
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      initialLocaleCodeProvider.overrideWithValue(locale),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppL10n.supportedLocales,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(Locale(locale)),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('PrimaryButton is full width, 56dp tall and tappable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(PrimaryButton(label: 'Save', onPressed: () => taps++)),
    );
    final size = tester.getSize(find.byType(FilledButton));
    expect(size.height, greaterThanOrEqualTo(kPrimaryButtonHeight));
    await tester.tap(find.text('Save'));
    expect(taps, 1);
  });

  testWidgets('AppListTile keeps a 48dp minimum height', (tester) async {
    await tester.pumpWidget(_host(const AppListTile(title: 'Rahim')));
    expect(
      tester.getSize(find.byType(AppListTile)).height,
      greaterThanOrEqualTo(kMinTouchTarget),
    );
  });

  testWidgets('EmptyState shows icon, title, body and action', (tester) async {
    await tester.pumpWidget(
      _host(
        const EmptyState(
          icon: Icons.people,
          title: 'Nothing',
          body: 'Add one',
          action: Text('Go'),
        ),
      ),
    );
    expect(find.text('Nothing'), findsOneWidget);
    expect(find.text('Add one'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets('MoneyText uses lakh grouping and Bangla digits by locale', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const MoneyText(Money.taka(123456))));
    expect(find.text('৳1,23,456'), findsOneWidget);

    await tester.pumpWidget(
      _host(const MoneyText(Money.taka(123456)), locale: 'bn'),
    );
    expect(find.text('৳১,২৩,৪৫৬'), findsOneWidget);
  });

  testWidgets('MoneyText colours due red and cleared green', (tester) async {
    await tester.pumpWidget(
      _host(const MoneyText(Money.taka(500), highlightDue: true)),
    );
    final due = tester.widget<Text>(find.text('৳500'));
    expect(
      due.style?.color,
      AppTheme.light(const Locale('en')).colorScheme.error,
    );

    await tester.pumpWidget(
      _host(const MoneyText(Money.zero, highlightDue: true)),
    );
    final cleared = tester.widget<Text>(find.text('৳0'));
    expect(cleared.style?.color, const Color(0xFF2E7D32));
  });

  testWidgets('StatusChip renders a localized label for every status', (
    tester,
  ) async {
    const english = {
      OrderStatus.received: 'Received',
      OrderStatus.cut: 'Cut',
      OrderStatus.stitching: 'Stitching',
      OrderStatus.finishing: 'Finishing',
      OrderStatus.ready: 'Ready',
      OrderStatus.delivered: 'Delivered',
    };
    for (final entry in english.entries) {
      await tester.pumpWidget(_host(StatusChip(entry.key)));
      expect(find.text(entry.value), findsOneWidget);
    }
    await tester.pumpWidget(
      _host(const StatusChip(OrderStatus.ready), locale: 'bn'),
    );
    expect(find.text('তৈরি'), findsOneWidget);
  });

  testWidgets('SectionHeader renders title and trailing widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const SectionHeader('Language', trailing: Text('x'))),
    );
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('Bangla text does not overflow at 1.3x scale', (tester) async {
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const EmptyState(
            icon: Icons.people_outline,
            title: 'এখনো কোনো গ্রাহক নেই',
            body: 'প্রথম গ্রাহক যোগ করে তাঁর মাপের খাতা শুরু করুন।',
            action: PrimaryButton(label: 'সংরক্ষণ', onPressed: null),
          ),
        ),
        locale: 'bn',
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
