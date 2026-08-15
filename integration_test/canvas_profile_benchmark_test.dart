import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';

import '../benchmark/canvas_benchmark_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('10k canvas profile benchmark', (tester) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> values) => timings.addAll(values);
    SchedulerBinding.instance.addTimingsCallback(collect);
    addTearDown(() => SchedulerBinding.instance.removeTimingsCallback(collect));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: const <MindmapNode>[],
            board: createCanvasBenchmarkBoard(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    for (var frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.byKey(const ValueKey<String>('canvas-object-benchmark-9999')),
      findsNothing,
    );
    binding.reportData = <String, Object?>{
      'canvas_frame_timing': _summary(timings),
    };
  });
}

Map<String, Object?> _summary(List<FrameTiming> timings) {
  final buildMicros =
      timings.map((timing) => timing.buildDuration.inMicroseconds).toList()
        ..sort();
  final rasterMicros =
      timings.map((timing) => timing.rasterDuration.inMicroseconds).toList()
        ..sort();
  return <String, Object?>{
    'schemaVersion': 1,
    'fixtureObjects': canvasBenchmarkObjectCount,
    'frameCount': timings.length,
    'build': _durationStats(buildMicros),
    'raster': _durationStats(rasterMicros),
  };
}

Map<String, Object?> _durationStats(List<int> values) {
  if (values.isEmpty) {
    return const <String, Object?>{
      'p50Ms': 0,
      'p90Ms': 0,
      'p99Ms': 0,
      'maxMs': 0,
      'over16_67ms': 0,
    };
  }
  double percentile(double fraction) =>
      values[math.min(values.length - 1, (values.length * fraction).floor())] /
      Duration.microsecondsPerMillisecond;
  return <String, Object?>{
    'p50Ms': percentile(0.50),
    'p90Ms': percentile(0.90),
    'p99Ms': percentile(0.99),
    'maxMs': values.last / Duration.microsecondsPerMillisecond,
    'over16_67ms': values.where((value) => value > 16670).length,
  };
}

String encodeCanvasBenchmarkSummary(Map<String, Object?> summary) =>
    jsonEncode(summary);
