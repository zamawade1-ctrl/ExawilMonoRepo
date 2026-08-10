import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'theme_mode';

/// Persisted light/dark switch. Not a secret, so plain SharedPreferences -
/// unlike the JWT/profile, this doesn't belong in secure storage.
final themeModeControllerProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);

    return switch (stored) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      // No explicit choice yet - default to the white (light) theme, which is
      // the app's primary identity, rather than following a dark system setting.
      // The settings toggle still lets a user opt into dark.
      _ => ThemeMode.light,
    };
  }

  Future<void> setDarkMode(bool isDark) async {
    final mode = isDark ? ThemeMode.dark : ThemeMode.light;
    state = AsyncData(mode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, isDark ? 'dark' : 'light');
  }
}
