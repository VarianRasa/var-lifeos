import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final output = const JsonEncoder.withIndent('  ').convert(data);
    await File(
      'build/canvas_benchmark_summary.json',
    ).writeAsString('$output\n');
  },
);
