import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// Current brightness preference. Defaults to dark.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

/// Current Astryx theme preference.
final themeVariantProvider =
    StateNotifierProvider<ThemeVariantNotifier, AppThemeVariant>((ref) {
      return ThemeVariantNotifier();
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

class ThemeVariantNotifier extends StateNotifier<AppThemeVariant> {
  ThemeVariantNotifier() : super(AppThemeVariant.astryxNeutral) {
    _loadThemeVariant();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'theme_variant';

  Future<void> _loadThemeVariant() async {
    final stored = await _prefs.getString(_key);
    state = _variantFromName(stored);
  }

  Future<void> setThemeVariant(AppThemeVariant variant) async {
    await _prefs.setString(_key, variant.name);
    state = variant;
  }
}

AppThemeVariant _variantFromName(String? name) {
  for (final variant in AppThemeVariant.values) {
    if (variant.name == name) return variant;
  }
  // Retired palettes remain harmless in preferences and fall back to Neutral.
  return AppThemeVariant.astryxNeutral;
}

enum AppFontSize {
  small,
  medium,
  large;

  double get scaleFactor => switch (this) {
    AppFontSize.small => 0.85,
    AppFontSize.medium => 1.0,
    AppFontSize.large => 1.15,
  };

  String get label => switch (this) {
    AppFontSize.small => 'Small',
    AppFontSize.medium => 'Medium',
    AppFontSize.large => 'Large',
  };
}

final themeFontSizeProvider =
    StateNotifierProvider<ThemeFontSizeNotifier, AppFontSize>((ref) {
      return ThemeFontSizeNotifier();
    });

class ThemeFontSizeNotifier extends StateNotifier<AppFontSize> {
  ThemeFontSizeNotifier() : super(AppFontSize.medium) {
    _loadFontSize();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'theme_font_size';

  Future<void> _loadFontSize() async {
    final stored = await _prefs.getString(_key);
    if (stored != null) {
      state = AppFontSize.values.firstWhere(
        (value) => value.name == stored,
        orElse: () => AppFontSize.medium,
      );
    }
  }

  Future<void> setFontSize(AppFontSize fontSize) async {
    await _prefs.setString(_key, fontSize.name);
    state = fontSize;
  }
}
