import 'package:flutter/material.dart';

/// Minimum interactive size (Spec §8: 48 dp targets, one-handed use).
const double kMinTouchTarget = 48;
const double kPrimaryButtonHeight = 56;

/// Theme builder shared by light and dark modes (S0-07).
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF0F6B5C);
  static const String bengaliFont = 'NotoSansBengali';

  static ThemeData light(Locale locale) => _build(Brightness.light, locale);
  static ThemeData dark(Locale locale) => _build(Brightness.dark, locale);

  static ThemeData _build(Brightness brightness, Locale locale) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isBangla = locale.languageCode == 'bn';
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      // Bangla glyphs are taller; give them room so conjuncts never clip.
      fontFamily: isBangla ? bengaliFont : null,
      fontFamilyFallback: isBangla ? null : const [bengaliFont],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final text = _scaled(base.textTheme, isBangla ? 1.45 : 1.3);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(kMinTouchTarget, kPrimaryButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(kMinTouchTarget, kMinTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static TextTheme _scaled(TextTheme theme, double height) {
    TextStyle? tune(TextStyle? style) =>
        style?.copyWith(height: _heightFor(style, height));
    return theme.copyWith(
      displayLarge: tune(theme.displayLarge),
      displayMedium: tune(theme.displayMedium),
      displaySmall: tune(theme.displaySmall),
      headlineLarge: tune(theme.headlineLarge),
      headlineMedium: tune(theme.headlineMedium),
      headlineSmall: tune(theme.headlineSmall),
      titleLarge: tune(theme.titleLarge),
      titleMedium: tune(theme.titleMedium),
      titleSmall: tune(theme.titleSmall),
      bodyLarge: tune(theme.bodyLarge),
      bodyMedium: tune(theme.bodyMedium),
      bodySmall: tune(theme.bodySmall),
      labelLarge: tune(theme.labelLarge),
      labelMedium: tune(theme.labelMedium),
      labelSmall: tune(theme.labelSmall),
    );
  }

  /// Large headings need less leading than body text.
  static double _heightFor(TextStyle style, double body) {
    final size = style.fontSize ?? 14;
    return size >= 28 ? body - 0.15 : body;
  }
}
