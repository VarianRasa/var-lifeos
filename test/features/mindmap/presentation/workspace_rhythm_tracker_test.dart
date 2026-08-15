import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/mindmap/presentation/workspace_rhythm_tracker.dart';

void main() {
  testWidgets('WorkspaceRhythmTracker renders rhythm slots and choice chips', (
    tester,
  ) async {
    final node1 = MindmapNode.create(
      id: 'node-1',
      type: NodeType.task,
      title: 'Morning Task',
      day: DateTime(2026, 7, 24),
      now: DateTime(2026, 7, 24, 8, 30),
      project: 'Dev',
    );

    final node2 = MindmapNode.create(
      id: 'node-2',
      type: NodeType.task,
      title: 'Afternoon Task',
      day: DateTime(2026, 7, 24),
      now: DateTime(2026, 7, 24, 14, 0),
      project: 'Dev',
    );

    final contextDev = WorkspaceContext(
      type: WorkspaceContextType.project,
      name: 'Dev',
      nodes: [node1, node2],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WorkspaceRhythmTracker(
                workspaceContexts: [contextDev],
                nodes: [node1, node2],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Ritme Energi & Ruang Kerja'), findsOneWidget);
    expect(find.text('Semua Konteks'), findsOneWidget);
    expect(find.text('Dev (2)'), findsOneWidget);
    expect(find.text('Pagi (06-12)'), findsOneWidget);
    expect(find.text('Siang (12-18)'), findsOneWidget);
    expect(find.text('Malam (18-24)'), findsOneWidget);
  });
}
