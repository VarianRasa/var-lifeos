final class WorkshopAiSticky {
  const WorkshopAiSticky({
    required this.id,
    required this.text,
    required this.votes,
    required this.locale,
  });

  final String id;
  final String text;
  final int votes;
  final String locale;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'text': text,
    'votes': votes,
    'locale': locale,
  };
}

final class WorkshopAiSourceGroup {
  const WorkshopAiSourceGroup({required this.name, required this.sourceIds});

  final String name;
  final List<String> sourceIds;
}

final class WorkshopAiSourceStatement {
  const WorkshopAiSourceStatement({
    required this.text,
    required this.sourceIds,
  });

  final String text;
  final List<String> sourceIds;
}

final class WorkshopAiSummarySnapshot {
  const WorkshopAiSummarySnapshot({
    required this.summary,
    required this.themes,
    required this.decisions,
    required this.actionItems,
    required this.risks,
    required this.model,
    required this.version,
  });

  factory WorkshopAiSummarySnapshot.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    List<String> strings(String key) =>
        (json[key] as List?)?.whereType<String>().toList(growable: false) ??
        const <String>[];
    return WorkshopAiSummarySnapshot(
      summary: json['summary'] as String? ?? '',
      themes: strings('themes'),
      decisions: strings('decisions'),
      actionItems: strings('actionItems'),
      risks: strings('risks'),
      model: json['model'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }

  factory WorkshopAiSummarySnapshot.fromAnalysis(WorkshopAiAnalysis analysis) =>
      WorkshopAiSummarySnapshot(
        summary: analysis.summary,
        themes: analysis.themes.map((item) => item.name).toList(),
        decisions: analysis.decisions.map((item) => item.text).toList(),
        actionItems: analysis.actionItems.map((item) => item.text).toList(),
        risks: analysis.risks.map((item) => item.text).toList(),
        model: analysis.model,
        version: analysis.version,
      );

  final String summary;
  final List<String> themes;
  final List<String> decisions;
  final List<String> actionItems;
  final List<String> risks;
  final String model;
  final String version;

  Map<String, Object> toJson() => <String, Object>{
    'summary': summary,
    'themes': themes,
    'decisions': decisions,
    'actionItems': actionItems,
    'risks': risks,
    'model': model,
    'version': version,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkshopAiSummarySnapshot &&
      other.summary == summary &&
      _listEquals(other.themes, themes) &&
      _listEquals(other.decisions, decisions) &&
      _listEquals(other.actionItems, actionItems) &&
      _listEquals(other.risks, risks) &&
      other.model == model &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    summary,
    Object.hashAll(themes),
    Object.hashAll(decisions),
    Object.hashAll(actionItems),
    Object.hashAll(risks),
    model,
    version,
  );
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class WorkshopAiAnalysis {
  const WorkshopAiAnalysis({
    required this.summary,
    required this.themes,
    required this.clusters,
    required this.decisions,
    required this.actionItems,
    required this.risks,
    required this.model,
    required this.version,
  });

  final String summary;
  final List<WorkshopAiSourceGroup> themes;
  final List<WorkshopAiSourceGroup> clusters;
  final List<WorkshopAiSourceStatement> decisions;
  final List<WorkshopAiSourceStatement> actionItems;
  final List<WorkshopAiSourceStatement> risks;
  final String model;
  final String version;
}

abstract interface class WorkshopAiClient {
  Future<WorkshopAiAnalysis> analyze(List<WorkshopAiSticky> sticky);
}

final class WorkshopAiException implements Exception {
  const WorkshopAiException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => 'WorkshopAiException($code, $message)';
}
