import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Platform metadata', () {
    test('web title and manifest use Var', () {
      final indexHtml = _read('web/index.html');
      final manifest =
          jsonDecode(_read('web/manifest.json')) as Map<String, Object?>;

      expect(indexHtml, contains('<title>Var</title>'));
      expect(
        indexHtml,
        contains('<meta name="apple-mobile-web-app-title" content="Var">'),
      );
      expect(manifest['name'], 'Var');
      expect(manifest['short_name'], 'Var');
    });

    test('mobile metadata uses Var', () {
      final androidManifest = _read('android/app/src/main/AndroidManifest.xml');
      final iosInfoPlist = _read('ios/Runner/Info.plist');

      expect(androidManifest, contains('android:label="Var"'));
      expect(iosInfoPlist, contains('<key>CFBundleDisplayName</key>'));
      expect(iosInfoPlist, contains('<key>CFBundleName</key>'));
      expect(iosInfoPlist, contains('<string>Var</string>'));
    });

    test('desktop metadata uses Var', () {
      final macosAppInfo = _read('macos/Runner/Configs/AppInfo.xcconfig');
      final windowsMain = _read('windows/runner/main.cpp');
      final windowsResources = _read('windows/runner/Runner.rc');
      final linuxApplication = _read('linux/runner/my_application.cc');

      expect(macosAppInfo, contains('PRODUCT_NAME = Var'));
      expect(windowsMain, contains('window.Create(L"Var"'));
      expect(
        windowsResources,
        contains(r'VALUE "FileDescription", "Var" "\0"'),
      );
      expect(windowsResources, contains(r'VALUE "ProductName", "Var" "\0"'));
      expect(
        linuxApplication,
        contains('gtk_header_bar_set_title(header_bar, "Var");'),
      );
      expect(
        linuxApplication,
        contains('gtk_window_set_title(window, "Var");'),
      );
    });
  });
}
