import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:var_app/features/mindmap/data/canvas_export_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveCanvasPng writes exact bytes under Var exports', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'var-canvas-export-',
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
    final bytes = Uint8List.fromList(const [137, 80, 78, 71, 13, 10, 26, 10]);

    final result = await saveCanvasPng(bytes, 'canvas.png');

    expect(result, p.join(tempDirectory.path, 'Var', 'exports', 'canvas.png'));
    expect(await File(result).readAsBytes(), bytes);
  });

  test('saveCanvasSvg writes exact text under Var exports', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'var-canvas-export-',
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
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';

    final result = await saveCanvasSvg(svg, 'canvas.svg');

    expect(result, p.join(tempDirectory.path, 'Var', 'exports', 'canvas.svg'));
    expect(await File(result).readAsString(), svg);
  });
}
