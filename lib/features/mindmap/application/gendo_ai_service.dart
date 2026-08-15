import 'dart:math';
import 'package:var_app/features/mindmap/domain/gendo_ai_node.dart';

abstract interface class GendoAiClient {
  Future<GendoAiNodeData> generateRender(
    GendoAiNodeData currentData, {
    String? promptOverride,
    GendoAiStylePreset? styleOverride,
    String? sourceImageOverride,
    double? strengthOverride,
    String? aspectRatioOverride,
  });

  Future<GendoAiNodeData> swapMaterial(
    GendoAiNodeData currentData, {
    required String targetMaterial,
    String? basePrompt,
  });

  GendoAiNodeData selectIteration(GendoAiNodeData currentData, int index);
}

class MockGendoAiService implements GendoAiClient {
  MockGendoAiService({this.randomSeedGenerator});

  final int Function()? randomSeedGenerator;

  @override
  Future<GendoAiNodeData> generateRender(
    GendoAiNodeData currentData, {
    String? promptOverride,
    GendoAiStylePreset? styleOverride,
    String? sourceImageOverride,
    double? strengthOverride,
    String? aspectRatioOverride,
  }) async {
    final prompt = (promptOverride ?? currentData.prompt).trim();
    final style = styleOverride ?? currentData.selectedStyle;
    final sourceImage = sourceImageOverride ?? currentData.sourceImageUrl;
    final strength = strengthOverride ?? currentData.strength;
    final aspectRatio = aspectRatioOverride ?? currentData.aspectRatio;

    final seed = randomSeedGenerator?.call() ?? Random().nextInt(1000000);
    final now = DateTime.now();
    final iterationId = 'iter_${now.millisecondsSinceEpoch}_$seed';

    final styleSlug = style.name;
    final mockOutputUrl =
        'https://images.unsplash.com/photo-mock-$styleSlug-$seed?auto=format&fit=crop&w=1200&q=80';

    final newIteration = GendoAiRenderIteration(
      id: iterationId,
      prompt: prompt.isEmpty ? 'Architectural concept render' : prompt,
      negativePrompt: currentData.negativePrompt,
      stylePreset: style,
      sourceImageUrl: sourceImage,
      outputImageUrl: mockOutputUrl,
      seed: seed,
      createdAt: now,
      status: GendoAiRenderStatus.completed,
    );

    final updatedIterations = <GendoAiRenderIteration>[
      ...currentData.iterations,
      newIteration,
    ];

    return currentData.copyWith(
      prompt: prompt,
      selectedStyle: style,
      sourceImageUrl: sourceImage,
      strength: strength,
      aspectRatio: aspectRatio,
      iterations: updatedIterations,
      activeIterationIndex: updatedIterations.length - 1,
    );
  }

  @override
  Future<GendoAiNodeData> swapMaterial(
    GendoAiNodeData currentData, {
    required String targetMaterial,
    String? basePrompt,
  }) async {
    final active = currentData.activeIteration;
    final base = (basePrompt ?? active?.prompt ?? currentData.prompt).trim();
    final newPrompt = base.isEmpty
        ? 'Applied material: $targetMaterial'
        : '$base with $targetMaterial finish and detailing';

    return generateRender(
      currentData,
      promptOverride: newPrompt,
      styleOverride: GendoAiStylePreset.materialsFinishes,
      sourceImageOverride: active?.outputImageUrl ?? currentData.sourceImageUrl,
    );
  }

  @override
  GendoAiNodeData selectIteration(GendoAiNodeData currentData, int index) {
    if (currentData.iterations.isEmpty) return currentData;
    final clampedIndex = index.clamp(0, currentData.iterations.length - 1);
    return currentData.copyWith(activeIterationIndex: clampedIndex);
  }
}
