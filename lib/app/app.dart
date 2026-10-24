import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/router.dart';
import 'package:tailor_khata/app/services.dart';
import 'package:tailor_khata/core/logging/app_log.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
import 'package:tailor_khata/features/backup/presentation/backup_providers.dart';
import 'package:tailor_khata/features/customers/presentation/customer_providers.dart';
import 'package:tailor_khata/features/orders/presentation/order_providers.dart';
import 'package:tailor_khata/features/security/presentation/lock_screen.dart';
import 'package:tailor_khata/l10n/gen/app_localizations.dart';

class TailorKhataApp extends ConsumerStatefulWidget {
  const TailorKhataApp({this.router, super.key});

  /// Injectable for tests.
  final GoRouter? router;

  @override
  ConsumerState<TailorKhataApp> createState() => _TailorKhataAppState();
}

class _TailorKhataAppState extends ConsumerState<TailorKhataApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = widget.router ?? buildRouter();
  StreamSubscription<String>? _taps;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationServiceProvider);
    // A tap on a reminder opens the order or delivery list it is about.
    _taps = notifications.taps.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = notifications.launchPayload;
      if (launch != null) _open(launch);
      _scheduleSync();
      _housekeeping();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _housekeeping();
  }

  /// Quiet daily upkeep, run at start and whenever the app comes back: an
  /// automatic backup if one is due (B-2) and the purge of old deleted
  /// customers (B-8). Neither may ever disturb the person using the app.
  Future<void> _housekeeping() async {
    try {
      final backups = ref.read(backupServiceProvider);
      final made = backups == null ? null : await backups.maybeAutoBackup();
      if (made != null) {
        await copyToDriveIfEnabled(
          settings: ref.read(settingsRepositoryProvider),
          store: ref.read(driveStoreProvider),
          file: made.file,
        );
        ref.read(backupRevisionProvider.notifier).bump();
      }
      await ref
          .read(deletedCustomerRepositoryProvider)
          .purgeExpired(ref.read(clockProvider).now());
    } on Object catch (error) {
      AppLog.w('app', 'Housekeeping skipped: $error');
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox()),
      debugShowCheckedModeBanner: false,
    );
  }
}
