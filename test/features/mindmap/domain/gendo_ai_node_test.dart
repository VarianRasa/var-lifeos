import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/gendo_ai_service.dart';
import 'package:var_app/features/mindmap/domain/gendo_ai_node.dart';

void main() {
  group('GendoAiNodeData serialization', () {
    test('serializes and deserializes correctly with default values', () {
      const data = GendoAiNodeData();
      final json = data.toJson();
      final restored = GendoAiNodeData.fromJson(json);

      expect(restored.prompt, '');
      expect(restored.negativePrompt, '');
      expect(restored.selectedStyle, GendoAiStylePreset.photorealistic);
      expect(restored.sourceImageUrl, isNull);
      expect(restored.iterations, isEmpty);
      expect(restored.activeIterationIndex, 0);
      expect(restored.strength, 0.75);
      expect(restored.aspectRatio, '16:9');
    });

    test('serializes and deserializes full data with iterations', () {
      final now = DateTime(2026, 8, 15, 12, 0);
      final iteration = GendoAiRenderIteration(
        id: 'iter-1',
        prompt: 'Modern glass villa in forest',
        negativePrompt: 'blurry, low quality',
        stylePreset: GendoAiStylePreset.daylightArchitecture,
        sourceImageUrl: 'https://example.com/source.jpg',
        outputImageUrl: 'https://example.com/out.jpg',
        seed: 42,
        createdAt: now,
        status: GendoAiRenderStatus.completed,
      );

      final data = GendoAiNodeData(
        prompt: 'Modern glass villa in forest',
        negativePrompt: 'blurry, low quality',
        selectedStyle: GendoAiStylePreset.daylightArchitecture,
        sourceImageUrl: 'https://example.com/source.jpg',
        iterations: [iteration],
        activeIterationIndex: 0,
        strength: 0.85,
        aspectRatio: '4:3',
      );

      final json = data.toJson();
      final restored = GendoAiNodeData.fromJson(json);

      expect(restored.prompt, data.prompt);
      expect(restored.negativePrompt, data.negativePrompt);
      expect(restored.selectedStyle, GendoAiStylePreset.daylightArchitecture);
      expect(restored.sourceImageUrl, 'https://example.com/source.jpg');
      expect(restored.iterations.length, 1);
      expect(restored.iterations.first.id, 'iter-1');
      expect(
        restored.iterations.first.outputImageUrl,
        'https://example.com/out.jpg',
      );
      expect(restored.iterations.first.seed, 42);
      expect(restored.iterations.first.createdAt, now);
      expect(restored.iterations.first.status, GendoAiRenderStatus.completed);
      expect(restored.activeIterationIndex, 0);
      expect(restored.strength, 0.85);
      expect(restored.aspectRatio, '4:3');
    });

    test('copyWith works properly', () {
      const data = GendoAiNodeData();
      final updated = data.copyWith(
        prompt: 'Minimalist concrete loft',
        selectedStyle: GendoAiStylePreset.materialsFinishes,
        strength: 0.6,
      );

      expect(updated.prompt, 'Minimalist concrete loft');
      expect(updated.selectedStyle, GendoAiStylePreset.materialsFinishes);
      expect(updated.strength, 0.6);
      expect(updated.aspectRatio, '16:9');
    });
  });

  group('MockGendoAiService', () {
    test('generates render iteration and updates history', () async {
      final service = MockGendoAiService();
      const initialData = GendoAiNodeData(
        prompt: 'Atmospheric evening pavilion',
        selectedStyle: GendoAiStylePreset.eveningAtmosphere,
        aspectRatio: '16:9',
      );

      final updatedData = await service.generateRender(initialData);

      expect(updatedData.iterations.length, 1);
      expect(updatedData.activeIterationIndex, 0);
      final iter = updatedData.activeIteration;
      expect(iter, isNotNull);
      expect(iter!.status, GendoAiRenderStatus.completed);
      expect(iter.outputImageUrl, isNotEmpty);
      expect(iter.stylePreset, GendoAiStylePreset.eveningAtmosphere);
      expect(iter.prompt, 'Atmospheric evening pavilion');
    });

    test('handles material swapping on active render', () async {
      final service = MockGendoAiService();
      const initialData = GendoAiNodeData(
        prompt: 'Modern interior living room',
        selectedStyle: GendoAiStylePreset.interiorModern,
      );

      final generated = await service.generateRender(initialData);
      final swapped = await service.swapMaterial(
        generated,
        targetMaterial: 'timber slats and brushed brass',
      );

      expect(swapped.iterations.length, 2);
      expect(swapped.activeIterationIndex, 1);
      expect(
        swapped.activeIteration!.prompt,
        contains('timber slats and brushed brass'),
      );
      expect(
        swapped.activeIteration!.stylePreset,
        GendoAiStylePreset.materialsFinishes,
      );
    });

    test('switches active iteration', () {
      final service = MockGendoAiService();
      final now = DateTime.now();
      final data = GendoAiNodeData(
        iterations: [
          GendoAiRenderIteration(
            id: '1',
            prompt: 'V1',
            createdAt: now,
            status: GendoAiRenderStatus.completed,
          ),
          GendoAiRenderIteration(
            id: '2',
            prompt: 'V2',
            createdAt: now,
            status: GendoAiRenderStatus.completed,
          ),
        ],
        activeIterationIndex: 0,
      );

      final switched = service.selectIteration(data, 1);
      expect(switched.activeIterationIndex, 1);
      expect(switched.activeIteration?.prompt, 'V2');
    });
  });
}
