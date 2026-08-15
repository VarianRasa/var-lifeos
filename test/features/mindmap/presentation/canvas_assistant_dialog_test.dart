import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/workshop_ai.dart';
import 'package:var_app/features/mindmap/presentation/canvas_assistant_dialog.dart';

void main() {
  final now = DateTime(2026, 7, 28);

  CanvasObject sticky(String id, String text, double x) => CanvasObject(
    id: id,
    type: CanvasObjectType.stickyNote,
    geometry: CanvasGeometry(x: x, y: 0, width: 240, height: 160),
    payload: <String, Object?>{'text': text},
    createdAt: now,
    updatedAt: now,
  );

  testWidgets('selection scope analyzes selected objects and emits preview', (
    tester,
  ) async {
    final board = CanvasBoard(
      id: 'project:dialog',
      kind: CanvasBoardKind.project,
      title: 'Dialog',
      objects: <CanvasObject>[
        sticky('selected', 'TODO: Validate launch', 0),
        sticky('other', 'Launch planning', 260),
      ],
      createdAt: now,
      updatedAt: now,
    );
    var previews = const <CanvasObject>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasAssistantDialog(
            board: board,
            nodes: const [],
            selectedObjectIds: const <String>{'selected'},
            canApply: true,
            onPreviewChanged: (objects) => previews = objects,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('1 analyzed objects'), findsOneWidget);
    expect(find.text('Selection (1)'), findsOneWidget);
    expect(previews, isNotEmpty);

    await tester.tap(find.text('Entire board'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 analyzed objects'), findsOneWidget);
  });

  testWidgets('remote analysis requires consent and previews clusters', (
    tester,
  ) async {
    final board = CanvasBoard(
      id: 'project:remote',
      kind: CanvasBoardKind.project,
      title: 'Remote',
      objects: <CanvasObject>[
        sticky('s1', 'Exact private sticky', 0),
        sticky('s2', 'Related private sticky', 260),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final client = _FakeWorkshopAiClient();
    var previews = const <CanvasObject>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasAssistantDialog(
            board: board,
            nodes: const [],
            selectedObjectIds: const <String>{},
            canApply: true,
            workshopAiEndpoint: Uri.parse('https://worker.test'),
            workshopAiClient: client,
            onPreviewChanged: (objects) => previews = objects,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('workshop-ai-analyze')));
    await tester.pumpAndSettle();
    expect(find.text('Host: worker.test'), findsOneWidget);
    expect(find.text('Exact private sticky'), findsOneWidget);
    expect(client.calls, 0);

    await tester.tap(find.byKey(const ValueKey('workshop-ai-consent-send')));
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    expect(find.byKey(const ValueKey('workshop-ai-results')), findsOneWidget);
    expect(find.text('Remote clusters added to preview.'), findsOneWidget);
    expect(
      previews.where((object) => object.type == CanvasObjectType.frame),
      hasLength(1),
    );
  });

  testWidgets('Save AI summary returns snapshot with zero proposals', (
    tester,
  ) async {
    final board = CanvasBoard(
      id: 'project:summary',
      kind: CanvasBoardKind.project,
      title: 'Summary',
      objects: <CanvasObject>[
        sticky('s1', 'First sticky', 0),
        sticky('s2', 'Second sticky', 260),
      ],
      createdAt: now,
      updatedAt: now,
    );
    CanvasAssistantDialogResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<CanvasAssistantDialogResult>(
                context: context,
                builder: (context) => CanvasAssistantDialog(
                  board: board,
                  nodes: const [],
                  selectedObjectIds: const <String>{},
                  canApply: true,
                  workshopAiEndpoint: Uri.parse('https://worker.test'),
                  workshopAiClient: _FakeWorkshopAiClient(),
                  onPreviewChanged: (_) {},
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workshop-ai-analyze')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workshop-ai-consent-send')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('canvas-assistant-save-summary')),
    );
    await tester.pumpAndSettle();

    expect(result?.proposalIds, isEmpty);
    expect(result?.aiSummarySnapshot?.summary, 'Remote summary');
  });

  testWidgets('read-only assistant disables proposal changes and apply', (
    tester,
  ) async {
    final board = CanvasBoard(
      id: 'project:read-only',
      kind: CanvasBoardKind.project,
      title: 'Read only',
      objects: <CanvasObject>[
        sticky('first', 'Research customer needs', 0),
        sticky('second', 'Research customer journey', 260),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasAssistantDialog(
            board: board,
            nodes: const [],
            selectedObjectIds: const <String>{},
            canApply: false,
            workshopAiEndpoint: Uri.parse('https://worker.test'),
            workshopAiClient: _FakeWorkshopAiClient(),
            onPreviewChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Read-only: editor permission required to apply.'),
      findsOneWidget,
    );
    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('canvas-assistant-apply')),
    );
    expect(apply.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('workshop-ai-analyze')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workshop-ai-consent-send')));
    await tester.pumpAndSettle();
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('canvas-assistant-save-summary')),
    );
    expect(save.onPressed, isNull);
  });
}

final class _FakeWorkshopAiClient implements WorkshopAiClient {
  int calls = 0;

  @override
  Future<WorkshopAiAnalysis> analyze(List<WorkshopAiSticky> sticky) async {
    calls += 1;
    return const WorkshopAiAnalysis(
      summary: 'Remote summary',
      themes: <WorkshopAiSourceGroup>[
        WorkshopAiSourceGroup(name: 'Theme', sourceIds: <String>['s1']),
      ],
      clusters: <WorkshopAiSourceGroup>[
        WorkshopAiSourceGroup(
          name: 'Remote cluster',
          sourceIds: <String>['s1', 's2'],
        ),
      ],
      decisions: <WorkshopAiSourceStatement>[],
      actionItems: <WorkshopAiSourceStatement>[],
      risks: <WorkshopAiSourceStatement>[],
      model: 'model',
      version: '1',
    );
  }
}
