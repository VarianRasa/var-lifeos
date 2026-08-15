import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:var_app/features/insights/insights_export_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveInsightsExport writes exact text to requested file', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'var-insights-export-',
    );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await tempDirectory.delete(recursive: true);
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDirectory.path,
        );

    final result = await saveInsightsExport('alpha,beta\n1,2', 'report.csv');

    expect(result, p.join(tempDirectory.path, 'report.csv'));
    expect(await File(result).readAsString(), 'alpha,beta\n1,2');
  });
}
