import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

/// Logging wrapper that strips personal data before anything is written
/// (TD §6: no customer data in logs).
class AppLog {
  const AppLog._();

  /// Receives every redacted line; tests replace this to capture output.
  @visibleForTesting
  static void Function(LogLevel level, String tag, String message)? sink;

  static final RegExp _phone = RegExp(r'\+?\d[\d\s\-]{6,}\d');
  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');

  /// Masks phone-number-like digit runs and e-mail addresses.
  static String redact(String input) =>
      input.replaceAll(_email, '<email>').replaceAll(_phone, '<number>');

  static void d(String tag, String message) =>
      _write(LogLevel.debug, tag, message);
  static void i(String tag, String message) =>
      _write(LogLevel.info, tag, message);
  static void w(String tag, String message) =>
      _write(LogLevel.warning, tag, message);

  static void e(
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final detail = error == null ? message : '$message: ${error.runtimeType}';
    _write(LogLevel.error, tag, detail, stack);
  }

  static void _write(
    LogLevel level,
    String tag,
    String message, [
    StackTrace? stack,
  ]) {
    final safe = redact(message);
    final capture = sink;
    if (capture != null) {
      capture(level, tag, safe);
      return;
    }
    if (level == LogLevel.debug && !kDebugMode) return;
    developer.log(
      safe,
      name: tag,
      level: switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      },
      stackTrace: stack,
    );
  }
}
