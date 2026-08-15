import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/capture/application/capture_providers.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/presentation/quick_capture_dialog.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('QuickCaptureDialog Widget', () {
    late InMemoryMindmapRepository mindmapRepository;

    setUp(() {
      mindmapRepository = InMemoryMindmapRepository();
    });

    Widget buildTestableWidget({
      List<CaptureDestination>? overrideDestinations,
    }) {
      return ProviderScope(
        overrides: [
          mindmapRepositoryProvider.overrideWithValue(mindmapRepository),
          captureServiceProvider.overrideWith(
            (ref) async => CaptureService(mindmapRepository: mindmapRepository),
          ),
          availableCaptureDestinationsProvider.overrideWith((ref) async {
            return overrideDestinations ??
                const [
                  CaptureDestination(
                    boardId: 'inbox-board',
                    boardTitle: 'Inbox Board',
                    workspaceId: 'main-workspace',
                  ),
                ];
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: QuickCaptureDialog())),
      );
    }

    testWidgets(
      'renders input fields and keeps save disabled without destination or content',
      (tester) async {
        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        expect(find.text('Quick Capture'), findsOneWidget);
        expect(find.text('Save Capture'), findsOneWidget);

        final saveButtonFinder = find.byKey(
          const Key('quick_capture_save_button'),
        );
        final saveButton = tester.widget<FilledButton>(saveButtonFinder);
        expect(saveButton.onPressed, isNull);
      },
    );

    testWidgets('enables save button when content and destination selected', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('quick_capture_text_field')),
        'Quick note idea',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('quick_capture_destination_dropdown')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inbox Board (main-workspace)').last);
      await tester.pumpAndSettle();

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('quick_capture_save_button')),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets(
      'triggers duplicate detection and renders match options when match found',
      (tester) async {
        final existingNode = MindmapNode.create(
          id: 'existing-node-1',
          title: 'https://example.com/duplicate',
          type: NodeType.link,
          day: DateTime.now(),
          data: {'url': 'https://example.com/duplicate'},
        );
        await mindmapRepository.saveNode(existingNode);

        await tester.pumpWidget(buildTestableWidget());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('quick_capture_url_field')),
          'https://example.com/duplicate',
        );
        await tester.pumpAndSettle();

        expect(find.text('Duplicate content detected'), findsOneWidget);
        expect(find.text('Open Existing'), findsOneWidget);
        expect(find.text('Create Copy'), findsOneWidget);
        final saveButton = tester.widget<FilledButton>(
          find.byKey(const Key('quick_capture_save_button')),
        );
        expect(saveButton.onPressed, isNull);
      },
    );

    testWidgets('capture fits compact width and exposes native save action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestableWidget());
      await tester.pump();

      expect(
        find.byKey(const Key('quick_capture_save_button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate warning is live and copy uses filled action', (
      tester,
    ) async {
      final existingNode = MindmapNode.create(
        id: 'existing-node-live',
        title: 'https://example.com/duplicate',
        type: NodeType.link,
        day: DateTime.now(),
        data: {'url': 'https://example.com/duplicate'},
      );
      await mindmapRepository.saveNode(existingNode);
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick_capture_url_field')),
        'https://example.com/duplicate',
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSemantics(find.text('Duplicate content detected'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(find.widgetWithText(FilledButton, 'Create Copy'), findsOneWidget);
    });

    testWidgets('creates new node via CaptureService on save', (tester) async {
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('quick_capture_text_field')),
        'Save quick item',
      );
      await tester.tap(
        find.byKey(const Key('quick_capture_destination_dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inbox Board (main-workspace)').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('quick_capture_save_button')));
      await tester.pumpAndSettle();

      final savedNodes = await mindmapRepository.listNodes();
      expect(savedNodes.any((n) => n.title == 'Save quick item'), isTrue);
    });
  });
}
