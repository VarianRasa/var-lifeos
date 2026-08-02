import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/domain/node_ui_state_codec.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('resource collapsed information card stays draggable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'resource-drag',
      type: NodeType.resource,
      title: 'Manual',
      day: day,
      now: day,
      data: const <String, Object?>{
        nodeUiSizePresetKey: 'custom',
        nodeUiWidthKey: 358.5,
        nodeUiHeightKey: 400.0,
      },
    );
    final node = base.copyWith(
      data: const ResourcePayload(
        folders: <ResourceFolder>[
          ResourceFolder(id: 'research', name: 'Research'),
        ],
        relatedAssets: <ResourceAsset>[
          ResourceAsset(
            id: 'manual',
            kind: 'file',
            fileName: 'manual.pdf',
            extension: 'pdf',
            folderId: 'research',
          ),
        ],
        folderPath: <String>['Research'],
      ).toData(base.data),
    );
    CanvasPosition? movedPosition;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MindmapCanvas(
            nodes: <MindmapNode>[node],
            highlightedNodeId: node.id,
            onNodeMoved: (_, position) => movedPosition = position,
            onNodeResize: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nodeFinder = find.byKey(const ValueKey('mindmap-node-resource-drag'));
    final shell = tester.widget<NodeShell>(
      find.descendant(of: nodeFinder, matching: find.byType(NodeShell)),
    );
    expect(shell.isCompact, isFalse);
    expect(find.text('Resource'), findsOneWidget);
    expect(find.text('Folder: Research'), findsOneWidget);
    expect(find.text('Assets: 1'), findsOneWidget);
    expect(find.text('Copy source'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resource-collapsed-preview')),
      findsNothing,
    );

    await tester.drag(nodeFinder, const Offset(40, 20));
    await tester.pump();

    expect(movedPosition, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
