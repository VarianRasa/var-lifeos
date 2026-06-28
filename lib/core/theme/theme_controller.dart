import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Current brightness preference. Defaults to dark (the app's primary look).
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

/// Current accent color preference. Defaults to indigo-blue.
final themeAccentColorProvider =
    StateNotifierProvider<ThemeAccentColorNotifier, Color>((ref) {
      return ThemeAccentColorNotifier();
    });

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadThemeMode();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'theme_mode';

  Future<void> _loadThemeMode() async {
    final stored = await _prefs.getString(_key);
    final mode = _themeModeFromName(stored);
    if (mode != null) state = mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_key, mode.name);
    state = mode;
  }
}

ThemeMode? _themeModeFromName(String? name) {
  for (final mode in ThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

class ThemeAccentColorNotifier extends StateNotifier<Color> {
  ThemeAccentColorNotifier() : super(const Color(0xFF6C8EEF)) {
    _loadAccentColor();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'theme_accent_color';

  Future<void> _loadAccentColor() async {
    final hexString = await _prefs.getString(_key);
    if (hexString != null) {
      final value = int.tryParse(hexString, radix: 16);
      if (value != null) {
        state = Color(value);
      }
    }
  }

  Future<void> setAccentColor(Color color) async {
    await _prefs.setString(_key, color.toARGB32().toRadixString(16));
    state = color;
  }
}
