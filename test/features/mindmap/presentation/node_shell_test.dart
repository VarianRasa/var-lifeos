import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';

void main() {
  Widget subject({
    Size size = const Size(300, 200),
    bool selected = true,
    bool compact = false,
    double scale = 1,
    ValueChanged<NodeResizeChange>? onResizeChanged,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Transform.scale(
          scale: scale,
          child: NodeShell(
            type: NodeType.task,
            size: size,
            color: const Color(0xFFD946EF),
            isSelected: selected,
            isCompact: compact,
            preset: compact ? NodeSizePreset.compact : NodeSizePreset.standard,
            onResizeChanged: onResizeChanged,
            child: const SizedBox.expand(
              key: ValueKey<String>('node-shell-content'),
              child: Text('Task node'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('resize chrome appears only while hovered or selected', (
    tester,
  ) async {
    await tester.pumpWidget(subject(selected: false, onResizeChanged: (_) {}));
    final handle = NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight);
    expect(find.byKey(handle), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(NodeShell)));
    await tester.pump();
    expect(find.byKey(handle), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.byKey(handle), findsNothing);
  });

  for (final scale in <double>[0.5, 1, 2]) {
    for (final handle in NodeResizeHandle.values) {
      testWidgets(
        '${handle.name} preserves opposite corner at ${scale}x and commits once',
        (tester) async {
          final changes = <NodeResizeChange>[];
          await tester.pumpWidget(
            subject(scale: scale, onResizeChanged: changes.add),
          );
          final drag = Offset(20 * scale, 16 * scale);
          await tester.drag(nodeShellHandleFinder(handle), drag);
          await tester.pump();

          final previews = changes
              .where((change) => change.phase == NodeResizePhase.preview)
              .toList();
          final commits = changes
              .where((change) => change.phase == NodeResizePhase.commit)
              .toList();
          expect(previews, isNotEmpty);
          expect(commits, hasLength(1));
          final commit = commits.single;
          final left =
              handle == NodeResizeHandle.topLeft ||
              handle == NodeResizeHandle.bottomLeft;
          final top =
              handle == NodeResizeHandle.topLeft ||
              handle == NodeResizeHandle.topRight;
          expect(commit.size.width, closeTo(left ? 280 : 320, 0.01));
          expect(commit.size.height, closeTo(top ? 184 : 216, 0.01));
          expect(commit.positionDelta.dx, closeTo(left ? 20 : 0, 0.01));
          expect(commit.positionDelta.dy, closeTo(top ? 16 : 0, 0.01));
          expect(commit.preset, NodeSizePreset.custom);

          const originalRight = 300.0;
          const originalBottom = 200.0;
          if (left) {
            expect(
              commit.positionDelta.dx + commit.size.width,
              closeTo(originalRight, 0.01),
            );
          }
          if (top) {
            expect(
              commit.positionDelta.dy + commit.size.height,
              closeTo(originalBottom, 0.01),
            );
          }
        },
      );
    }
  }

  testWidgets('compact and full content rebuild to effective preview size', (
    tester,
  ) async {
    for (final compact in <bool>[false, true]) {
      await tester.pumpWidget(
        subject(compact: compact, onResizeChanged: (_) {}),
      );
      await tester.drag(
        nodeShellHandleFinder(NodeResizeHandle.bottomRight),
        const Offset(30, 24),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('node-shell-content'))),
        const Size(330, 224),
      );
    }
  });

  testWidgets('resize handles keep 44 pixel hit targets', (tester) async {
    await tester.pumpWidget(subject(onResizeChanged: (_) {}));

    for (final handle in NodeResizeHandle.values) {
      expect(tester.getSize(nodeShellHandleFinder(handle)), const Size(44, 44));
    }
  });

  testWidgets(
    'handles excluded from semantics and resize control is adjustable',
    (tester) async {
      final changes = <NodeResizeChange>[];
      await tester.pumpWidget(subject(onResizeChanged: changes.add));
      final handle = find.byKey(
        NodeShell.resizeHandleKey(NodeResizeHandle.bottomRight),
      );
      expect(
        find.descendant(of: handle, matching: find.byType(Semantics)),
        findsNothing,
      );

      final semantics = tester.getSemantics(
        find.byKey(NodeShell.accessibleResizeKey),
      );
      expect(semantics.label, contains('Node custom size'));
      tester
          .widget<Semantics>(find.byKey(NodeShell.accessibleResizeKey))
          .properties
          .onIncrease
          ?.call();
      await tester.pump();
      expect(changes.single.phase, NodeResizePhase.commit);
      expect(changes.single.preset, NodeSizePreset.custom);
    },
  );

  testWidgets('preset selection emits one atomic commit', (tester) async {
    final changes = <NodeResizeChange>[];
    await tester.pumpWidget(subject(onResizeChanged: changes.add));
    await tester.tap(find.byKey(NodeShell.presetButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wide'));
    await tester.pumpAndSettle();
    expect(changes, hasLength(1));
    expect(changes.single.phase, NodeResizePhase.commit);
    expect(changes.single.preset, NodeSizePreset.wide);
  });

  testWidgets('pointer cancel emits cancel and restores original size', (
    tester,
  ) async {
    final changes = <NodeResizeChange>[];
    await tester.pumpWidget(subject(onResizeChanged: changes.add));
    final handle = nodeShellHandleFinder(NodeResizeHandle.topLeft);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 16));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey('node-shell-content'))),
      const Size(280, 184),
    );

    await gesture.cancel();
    await tester.pump();
    expect(changes.last.phase, NodeResizePhase.cancel);
    expect(
      tester.getSize(find.byKey(const ValueKey('node-shell-content'))),
      const Size(300, 200),
    );
  });

  testWidgets('pointer cancellation after disposal does not set state', (
    tester,
  ) async {
    await tester.pumpWidget(subject(onResizeChanged: (_) {}));
    final handle = nodeShellHandleFinder(NodeResizeHandle.bottomRight);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 16));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await gesture.cancel();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
  testWidgets('save status remains presentation only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NodeShell(
            type: NodeType.note,
            size: Size(260, 160),
            color: Color(0xFFD946EF),
            isSelected: true,
            preset: NodeSizePreset.standard,
            saveStatus: NodeShellSaveStatus.saving,
            child: Text('Note'),
          ),
        ),
      ),
    );
    expect(find.text('Saving…'), findsOneWidget);
  });
}

Finder nodeShellHandleFinder(NodeResizeHandle handle) =>
    find.byKey(NodeShell.resizeHandleKey(handle));
