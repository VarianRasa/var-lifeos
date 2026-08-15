enum GendoAiStylePreset {
  photorealistic,
  conceptualSketch,
  daylightArchitecture,
  eveningAtmosphere,
  interiorModern,
  materialsFinishes;

  String get label {
    switch (this) {
      case GendoAiStylePreset.photorealistic:
        return 'Photorealistic';
      case GendoAiStylePreset.conceptualSketch:
        return 'Conceptual Sketch';
      case GendoAiStylePreset.daylightArchitecture:
        return 'Daylight Architecture';
      case GendoAiStylePreset.eveningAtmosphere:
        return 'Evening Atmosphere';
      case GendoAiStylePreset.interiorModern:
        return 'Interior Modern';
      case GendoAiStylePreset.materialsFinishes:
        return 'Materials & Finishes';
    }
  }
}

enum GendoAiRenderStatus { idle, generating, completed, failed }

final class GendoAiRenderIteration {
  const GendoAiRenderIteration({
    required this.id,
    required this.prompt,
    this.negativePrompt = '',
    this.stylePreset = GendoAiStylePreset.photorealistic,
    this.sourceImageUrl,
    this.outputImageUrl = '',
    this.seed,
    required this.createdAt,
    this.status = GendoAiRenderStatus.idle,
    this.errorMessage,
  });

  final String id;
  final String prompt;
  final String negativePrompt;
  final GendoAiStylePreset stylePreset;
  final String? sourceImageUrl;
  final String outputImageUrl;
  final int? seed;
  final DateTime createdAt;
  final GendoAiRenderStatus status;
  final String? errorMessage;

  GendoAiRenderIteration copyWith({
    String? id,
    String? prompt,
    String? negativePrompt,
    GendoAiStylePreset? stylePreset,
    String? sourceImageUrl,
    String? outputImageUrl,
    int? seed,
    DateTime? createdAt,
    GendoAiRenderStatus? status,
    String? errorMessage,
  }) {
    return GendoAiRenderIteration(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      stylePreset: stylePreset ?? this.stylePreset,
      sourceImageUrl: sourceImageUrl ?? this.sourceImageUrl,
      outputImageUrl: outputImageUrl ?? this.outputImageUrl,
      seed: seed ?? this.seed,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'stylePreset': stylePreset.name,
      if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
      'outputImageUrl': outputImageUrl,
      if (seed != null) 'seed': seed,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  factory GendoAiRenderIteration.fromJson(Map<String, Object?> json) {
    final styleName = json['stylePreset'] as String?;
    final style = styleName != null
        ? GendoAiStylePreset.values
                  .where((e) => e.name == styleName)
                  .firstOrNull ??
              GendoAiStylePreset.photorealistic
        : GendoAiStylePreset.photorealistic;

    final statusName = json['status'] as String?;
    final status = statusName != null
        ? GendoAiRenderStatus.values
                  .where((e) => e.name == statusName)
                  .firstOrNull ??
              GendoAiRenderStatus.idle
        : GendoAiRenderStatus.idle;

    final rawCreatedAt = json['createdAt'] as String?;
    final createdAt = rawCreatedAt != null
        ? DateTime.tryParse(rawCreatedAt) ?? DateTime.now()
        : DateTime.now();

    return GendoAiRenderIteration(
      id: (json['id'] as String?) ?? '',
      prompt: (json['prompt'] as String?) ?? '',
      negativePrompt: (json['negativePrompt'] as String?) ?? '',
      stylePreset: style,
      sourceImageUrl: json['sourceImageUrl'] as String?,
      outputImageUrl: (json['outputImageUrl'] as String?) ?? '',
      seed: json['seed'] as int?,
      createdAt: createdAt,
      status: status,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

final class GendoAiNodeData {
  const GendoAiNodeData({
    this.prompt = '',
    this.negativePrompt = '',
    this.selectedStyle = GendoAiStylePreset.photorealistic,
    this.sourceImageUrl,
    this.iterations = const <GendoAiRenderIteration>[],
    this.activeIterationIndex = 0,
    this.strength = 0.75,
    this.aspectRatio = '16:9',
  });

  final String prompt;
  final String negativePrompt;
  final GendoAiStylePreset selectedStyle;
  final String? sourceImageUrl;
  final List<GendoAiRenderIteration> iterations;
  final int activeIterationIndex;
  final double strength;
  final String aspectRatio;

  GendoAiRenderIteration? get activeIteration {
    if (iterations.isEmpty) return null;
    if (activeIterationIndex < 0 || activeIterationIndex >= iterations.length) {
      return iterations.last;
    }
    return iterations[activeIterationIndex];
  }

  GendoAiNodeData copyWith({
    String? prompt,
    String? negativePrompt,
    GendoAiStylePreset? selectedStyle,
    String? sourceImageUrl,
    List<GendoAiRenderIteration>? iterations,
    int? activeIterationIndex,
    double? strength,
    String? aspectRatio,
  }) {
    return GendoAiNodeData(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      sourceImageUrl: sourceImageUrl ?? this.sourceImageUrl,
      iterations: iterations ?? this.iterations,
      activeIterationIndex: activeIterationIndex ?? this.activeIterationIndex,
      strength: strength ?? this.strength,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'selectedStyle': selectedStyle.name,
      if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
      'iterations': iterations.map((e) => e.toJson()).toList(),
      'activeIterationIndex': activeIterationIndex,
      'strength': strength,
      'aspectRatio': aspectRatio,
    };
  }

  factory GendoAiNodeData.fromJson(Map<String, Object?> json) {
    final styleName = json['selectedStyle'] as String?;
    final style = styleName != null
        ? GendoAiStylePreset.values
                  .where((e) => e.name == styleName)
                  .firstOrNull ??
              GendoAiStylePreset.photorealistic
        : GendoAiStylePreset.photorealistic;

    final rawIterations = json['iterations'];
    final iterations = <GendoAiRenderIteration>[
      if (rawIterations is List)
        for (final item in rawIterations)
          if (item is Map<String, Object?>)
            GendoAiRenderIteration.fromJson(item)
          else if (item is Map)
            GendoAiRenderIteration.fromJson(Map<String, Object?>.from(item)),
    ];

    final rawStrength = json['strength'];
    final strength = rawStrength is num ? rawStrength.toDouble() : 0.75;

    return GendoAiNodeData(
      prompt: (json['prompt'] as String?) ?? '',
      negativePrompt: (json['negativePrompt'] as String?) ?? '',
      selectedStyle: style,
      sourceImageUrl: json['sourceImageUrl'] as String?,
      iterations: iterations,
      activeIterationIndex: (json['activeIterationIndex'] as int?) ?? 0,
      strength: strength.clamp(0.0, 1.0),
      aspectRatio: (json['aspectRatio'] as String?) ?? '16:9',
    );
  }
}
