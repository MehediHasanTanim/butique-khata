import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tailor_khata/core/logging/app_log.dart';

/// Installs global error hooks so no uncaught error crashes silently or leaks
/// customer data into logs (S0-11).
class ErrorBoundary {
  const ErrorBoundary._();

  static void install() {
    FlutterError.onError = (details) {
      AppLog.e(
        'flutter',
        details.exceptionAsString(),
        details.exception,
        details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLog.e('platform', 'Uncaught error', error, stack);
      return true;
    };
    ErrorWidget.builder = (details) => const _FallbackErrorWidget();
  }

  /// Runs [body] in a zone that routes uncaught async errors to the log.
  static void run(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      AppLog.e('zone', 'Uncaught async error', error, stack);
    });
  }
}

class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget();

  @override
  Widget build(BuildContext context) {
    // Deliberately avoids l10n and theme lookups: this renders when the tree
    // above it is already broken.
    return const Material(
      color: Color(0xFFFFF3E0),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Icon(Icons.error_outline, size: 40, color: Color(0xFF8D5A00)),
        ),
      ),
    );
  }
}
