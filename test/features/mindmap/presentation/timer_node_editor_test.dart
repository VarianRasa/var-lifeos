import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/timer_node_editor.dart';

void main() {
  testWidgets('timer editor starts pauses and completes persistent session', (
    tester,
  ) async {
    final payloads = <TimerPayload>[];
    var payload = const TimerPayload();
    final node = _node();
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget app() => MaterialApp(
      theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
      home: Scaffold(
        body: SizedBox(
          width: 620,
          height: 900,
          child: TimerNodeEditor(
            node: node,
            payload: payload,
            onTitleChanged: (_) {},
            onBodyChanged: (_) {},
            onPayloadChanged: payloads.add,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey<String>('timer-hybrid-editor')), findsOne);
    await tester.tap(
      find.byKey(const ValueKey<String>('timer-primary-action')),
    );
    await tester.pump();
    payload = payloads.removeLast();
    expect(payload.timer.status, TimerRunStatus.running);
    expect(payload.timer.startedAt, isNotNull);
    final startedAt = DateTime.now().subtract(const Duration(seconds: 2));
    payload = TimerPayload(
      timer: payload.timer.copyWith(
        startedAt: startedAt,
        sessionStartedAt: startedAt,
      ),
    );

    await tester.pumpWidget(app());
    await tester.tap(
      find.byKey(const ValueKey<String>('timer-primary-action')),
    );
    await tester.pump();
    payload = payloads.removeLast();
    expect(payload.timer.status, TimerRunStatus.paused);

    await tester.pumpWidget(app());
    await tester.tap(
      find.byKey(const ValueKey<String>('timer-complete-action')),
    );
    await tester.pump();
    payload = payloads.removeLast();
    expect(payload.timer.history, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopwatch adds lap and distraction without overflow', (
    tester,
  ) async {
    final payloads = <TimerPayload>[];
    final node = _node();
    final payload = TimerPayload(
      timer: HybridTimerState(
        mode: TimerMode.stopwatch,
        status: TimerRunStatus.paused,
        accumulatedSeconds: 90,
        sessionStartedAt: DateTime(2026, 7, 16, 9),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 780,
            child: TimerNodeEditor(
              node: node,
              payload: payload,
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: payloads.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('timer-add-lap')));
    await tester.pump();
    expect(payloads.last.timer.laps, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus timer policy height shows all sections without scroll', (
    tester,
  ) async {
    final node = _node();
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    await tester.binding.setSurfaceSize(
      Size(size.width + 80, size.height + 80),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height - 64,
            child: TimerNodeEditor(
              node: node,
              payload: TimerPayload.fromNode(node),
              onTitleChanged: (_) {},
              onBodyChanged: (_) {},
              onPayloadChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final editorRect = tester.getRect(
      find.byKey(const ValueKey<String>('timer-hybrid-editor')),
    );
    final summaryRect = tester.getRect(
      find.byKey(const ValueKey<String>('timer-summary')),
    );
    expect(editorRect.bottom - summaryRect.bottom, lessThanOrEqualTo(24));
    expect(tester.takeException(), isNull);
  });
}

MindmapNode _node() => MindmapNode.create(
  id: 'timer',
  type: NodeType.timer,
  title: 'Focus session',
  day: DateTime(2026, 7, 16),
  now: DateTime(2026, 7, 16, 9),
);
