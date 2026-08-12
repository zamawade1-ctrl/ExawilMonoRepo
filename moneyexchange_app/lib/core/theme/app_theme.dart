import 'package:flutter/material.dart';

/// Single source of truth for the app's visual identity. Keep screens free of
/// hardcoded colors/text styles - reach for [Theme.of(context)] instead.
///
/// The look is deliberately **white-dominant** with **Leon green** as the single
/// accent: surfaces/app bar/scaffold are white, and the green is reserved for
/// primary actions (buttons), selected states, and highlights. That keeps the
/// money screens calm and readable while making the one thing the user should
/// tap unmistakable.
class AppTheme {
  const AppTheme._();

  /// Leon green — the app's one accent colour. Used for buttons, selected
  /// states, links, and highlights against the white background. Change this in
  /// one place to re-tint the whole app.
  static const Color leonGreen = Color(0xFF2FA84F);
  static const Color _leonGreenDark = Color(0xFF248A40);

  /// Brand mark colour for the app-bar app icon glyph.
  static const Color brandIconGreen = Color(0xFF26A65B);

  /// Brand colour for the app-bar app name text.
  static const Color brandNameGreen = Color(0xFF2E8B57);

  /// The product typeface. The licensed TT Norms Pro font files aren't bundled
  /// in the repo (commercial licence); drop them into `assets/fonts/` and
  /// uncomment the `fonts:` block in pubspec.yaml to activate them. Until then
  /// this family name resolves to the platform default, so the UI still renders.
  static const String fontFamily = 'TT Norms Pro';

  static ThemeData get light => _lightTheme();

  static ThemeData get dark => _darkTheme();

  static ThemeData _lightTheme() {
    // Start from a seeded scheme (so all the Material roles are internally
    // consistent), then pin the pieces that define the white + green identity:
    // white surfaces/background, Leon green as the primary/secondary accent.
    final base = ColorScheme.fromSeed(
      seedColor: leonGreen,
      brightness: Brightness.light,
    );
    final colorScheme = base.copyWith(
      primary: leonGreen,
      onPrimary: Colors.white,
      secondary: leonGreen,
      onSecondary: Colors.white,
      tertiary: _leonGreenDark,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF14181F),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF6F8F7),
      surfaceContainer: const Color(0xFFF1F5F3),
      surfaceContainerHigh: const Color(0xFFECF2EE),
      primaryContainer: const Color(0xFFDBF3E1),
      onPrimaryContainer: _leonGreenDark,
      outline: const Color(0xFFCBD5D0),
      outlineVariant: const Color(0xFFE1E8E4),
    );

    return _build(colorScheme, scaffold: Colors.white);
  }

  static ThemeData _darkTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: leonGreen,
      brightness: Brightness.dark,
    );
    final colorScheme = base.copyWith(
      primary: leonGreen,
      onPrimary: Colors.white,
      secondary: leonGreen,
    );
    return _build(colorScheme, scaffold: colorScheme.surface);
  }

  static ThemeData _build(ColorScheme colorScheme, {required Color scaffold}) {
    final isLight = colorScheme.brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Product typeface. Falls back to the platform default until the licensed
      // TT Norms Pro files are added (see [fontFamily]).
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? Colors.white : colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      // Primary actions are Leon green with white text.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),
      // On white, give cards a hairline outline instead of a heavy shadow.
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? Colors.white : colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        elevation: isLight ? 0 : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }
}
