import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/gendo_ai_service.dart';
import 'package:var_app/features/mindmap/domain/gendo_ai_node.dart';
import 'package:var_app/features/mindmap/presentation/widgets/gendo_ai_canvas_card.dart';

void main() {
  group('GendoAiCanvasCard widget tests', () {
    testWidgets('renders header badge and initial prompt and style chips', (
      tester,
    ) async {
      const initialData = GendoAiNodeData(
        prompt: 'Modern brutalist concrete villa',
        negativePrompt: 'blurry, low quality',
        selectedStyle: GendoAiStylePreset.photorealistic,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: GendoAiCanvasCard(data: initialData, onChanged: (_) {}),
            ),
          ),
        ),
      );

      // Verify header badge
      expect(find.text('Gendo AI Studio'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNWidgets(2),
      ); // prompt + negative prompt

      // Verify prompt content
      expect(find.text('Modern brutalist concrete villa'), findsOneWidget);

      // Verify style preset chips exist
      expect(find.text('Photorealistic'), findsOneWidget);
      expect(find.text('Daylight Architecture'), findsOneWidget);
      expect(find.text('Interior Modern'), findsOneWidget);
    });

    testWidgets('selecting a style chip notifies onChanged', (tester) async {
      GendoAiNodeData? updatedData;
      const initialData = GendoAiNodeData(
        selectedStyle: GendoAiStylePreset.photorealistic,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: GendoAiCanvasCard(
                data: initialData,
                onChanged: (data) => updatedData = data,
              ),
            ),
          ),
        ),
      );

      // Tap on Daylight Architecture chip
      await tester.tap(find.text('Daylight Architecture'));
      await tester.pumpAndSettle();

      expect(updatedData, isNotNull);
      expect(
        updatedData!.selectedStyle,
        GendoAiStylePreset.daylightArchitecture,
      );
    });

    testWidgets(
      'triggering generate render calls client and updates node data',
      (tester) async {
        GendoAiNodeData? updatedData;
        final mockService = MockGendoAiService();
        const initialData = GendoAiNodeData(
          prompt: 'Glass pavilion in autumn forest',
          selectedStyle: GendoAiStylePreset.eveningAtmosphere,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Center(
                child: GendoAiCanvasCard(
                  data: initialData,
                  client: mockService,
                  onChanged: (data) => updatedData = data,
                ),
              ),
            ),
          ),
        );

        // Find Generate Render button
        final generateBtn = find.text('Generate Render');
        expect(generateBtn, findsOneWidget);

        await tester.tap(generateBtn);
        await tester.pump(); // Start async generation
        await tester.pumpAndSettle(); // Settle generation

        expect(updatedData, isNotNull);
        expect(updatedData!.iterations.length, 1);
        expect(
          updatedData!.activeIteration?.status,
          GendoAiRenderStatus.completed,
        );
        expect(
          updatedData!.activeIteration?.stylePreset,
          GendoAiStylePreset.eveningAtmosphere,
        );
      },
    );

    testWidgets('navigating iteration history changes active iteration', (
      tester,
    ) async {
      GendoAiNodeData? updatedData;
      final mockService = MockGendoAiService();
      final iter1 = GendoAiRenderIteration(
        id: '1',
        prompt: 'Iteration 1 prompt',
        outputImageUrl: 'https://example.com/1.jpg',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        status: GendoAiRenderStatus.completed,
      );
      final iter2 = GendoAiRenderIteration(
        id: '2',
        prompt: 'Iteration 2 prompt',
        outputImageUrl: 'https://example.com/2.jpg',
        createdAt: DateTime.now(),
        status: GendoAiRenderStatus.completed,
      );

      final initialData = GendoAiNodeData(
        prompt: 'Base prompt',
        iterations: [iter1, iter2],
        activeIterationIndex: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: GendoAiCanvasCard(
                data: initialData,
                client: mockService,
                onChanged: (data) => updatedData = data,
              ),
            ),
          ),
        ),
      );

      // Find iteration thumbnail 1
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);

      // Tap on Iteration #1
      await tester.tap(find.text('#1'));
      await tester.pumpAndSettle();

      expect(updatedData, isNotNull);
      expect(updatedData!.activeIterationIndex, 0);
    });

    testWidgets('strength slider updates data strength', (tester) async {
      GendoAiNodeData? updatedData;
      const initialData = GendoAiNodeData(strength: 0.5);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: GendoAiCanvasCard(
                data: initialData,
                onChanged: (data) => updatedData = data,
              ),
            ),
          ),
        ),
      );

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      await tester.drag(sliderFinder, const Offset(50, 0));
      await tester.pumpAndSettle();

      expect(updatedData, isNotNull);
      expect(updatedData!.strength, isNot(0.5));
    });
  });
}
