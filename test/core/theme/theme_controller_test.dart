import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/theme/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('themeModeProvider defaults to dark', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('themeModeProvider persists selected mode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.system);

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(
      await SharedPreferencesAsync().getString('theme_mode'),
      ThemeMode.system.name,
    );
  });

  test('themeModeProvider restores stored mode', () async {
    await SharedPreferencesAsync().setString(
      'theme_mode',
      ThemeMode.light.name,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
