import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/router.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

class TailorKhataApp extends ConsumerStatefulWidget {
  const TailorKhataApp({this.router, super.key});

  /// Injectable for tests.
  final GoRouter? router;

  @override
  ConsumerState<TailorKhataApp> createState() => _TailorKhataAppState();
}

class _TailorKhataAppState extends ConsumerState<TailorKhataApp> {
  late final GoRouter _router = widget.router ?? buildRouter();
  StreamSubscription<String>? _taps;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationServiceProvider);
    // A tap on a reminder opens the order or delivery list it is about.
    _taps = notifications.taps.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = notifications.launchPayload;
      if (launch != null) _open(launch);
      _scheduleSync();
    });
  }

  void _open(String route) {
    if (!mounted) return;
    try {
      _router.push(route);
    } on Object {
      // An unknown route in an old notification must never crash the app.
    }
  }

  /// Several order changes in a row become one reschedule.
  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) ref.read(reminderSyncProvider).sync();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Anything that changes what should be scheduled triggers a rebuild of
    // the schedule: orders, reminder times, language.
    ref
      ..listen(openDeliveryDaysProvider, (_, _) => _scheduleSync())
      ..listen(
        appSettingsProvider.select((s) => s.reminders),
        (_, _) => _scheduleSync(),
      )
      ..listen(localeProvider, (_, _) => _scheduleSync());

    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppL10n.of(context).appName,
      routerConfig: _router,
      locale: locale,
      supportedLocales: AppL10n.supportedLocales,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(locale),
      darkTheme: AppTheme.dark(locale),
      debugShowCheckedModeBanner: false,
    );
  }
}
