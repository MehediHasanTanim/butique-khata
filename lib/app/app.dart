import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tailor_khata/app/providers.dart';
import 'package:tailor_khata/app/router.dart';
import 'package:tailor_khata/core/ui/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
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
