import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

import '../../../../benchmark/canvas_benchmark_fixture.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('10k canvas builds only viewport object structure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 700,
            child: MindmapCanvas(
              nodes: const <MindmapNode>[],
              board: createCanvasBenchmarkBoard(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final renderedObjects = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          ((widget.key! as ValueKey<String>).value).startsWith(
            'canvas-object-',
          ),
    );
    expect(renderedObjects, findsWidgets);
    expect(renderedObjects.evaluate().length, lessThan(100));
    expect(
      find.byKey(const ValueKey<String>('canvas-object-benchmark-9999')),
      findsNothing,
    );
  });
}
