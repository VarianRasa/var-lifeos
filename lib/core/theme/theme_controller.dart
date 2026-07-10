import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';

/// Current brightness preference. Defaults to dark (the app's primary look).
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

/// Current accent color preference. Defaults to lime marker.
final themeAccentColorProvider =
    StateNotifierProvider<ThemeAccentColorNotifier, Color>((ref) {
      return ThemeAccentColorNotifier();
    });

/// Current theme variant preference (e.g. blackboard, blueprint, schoolboard, midnight, cardboard).
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

class ThemeAccentColorNotifier extends StateNotifier<Color> {
  ThemeAccentColorNotifier() : super(const Color(0xFFB6FF00)) {
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

class ThemeVariantNotifier extends StateNotifier<AppThemeVariant> {
  ThemeVariantNotifier() : super(AppThemeVariant.blackboard) {
    _loadThemeVariant();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const _key = 'theme_variant';

  Future<void> _loadThemeVariant() async {
    final stored = await _prefs.getString(_key);
    final variant = _variantFromName(stored);
    if (variant != null) {
      state = variant;
      ThemeVariantConfig.active = variant;
    }
  }

  Future<void> setThemeVariant(AppThemeVariant variant) async {
    await _prefs.setString(_key, variant.name);
    state = variant;
    ThemeVariantConfig.active = variant;
  }

  AppThemeVariant? _variantFromName(String? name) {
    for (final variant in AppThemeVariant.values) {
      if (variant.name == name) return variant;
    }
    return null;
  }
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
      final val = AppFontSize.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => AppFontSize.medium,
      );
      state = val;
    }
  }

  Future<void> setFontSize(AppFontSize fontSize) async {
    await _prefs.setString(_key, fontSize.name);
    state = fontSize;
  }
}
