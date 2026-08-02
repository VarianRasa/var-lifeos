import 'package:collection/collection.dart';

import 'canvas_board.dart';
import 'mindmap_node.dart';

final class CanvasBoardTemplate {
  CanvasBoardTemplate({
    required String id,
    required String name,
    required String sourceBoardId,
    required this.createdAt,
    required this.updatedAt,
  }) : id = id.trim(),
       name = name.trim(),
       sourceBoardId = sourceBoardId.trim() {
    if (this.id.isEmpty || this.name.isEmpty || this.sourceBoardId.isEmpty) {
      throw const FormatException('Invalid canvas board template.');
    }
  }

  factory CanvasBoardTemplate.fromJson(Map<String, Object?> json) =>
      CanvasBoardTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sourceBoardId: json['sourceBoardId'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String? ?? ''),
        updatedAt: DateTime.parse(json['updatedAt'] as String? ?? ''),
      );

  final String id;
  final String name;
  final String sourceBoardId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'sourceBoardId': sourceBoardId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasBoardTemplate &&
      other.id == id &&
      other.name == name &&
      other.sourceBoardId == sourceBoardId &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(id, name, sourceBoardId, createdAt, updatedAt);
}

final class BuiltInCanvasBoardTemplate {
  BuiltInCanvasBoardTemplate({
    required this.template,
    required this.name,
    required List<CanvasObject> objects,
  }) : objects = List<CanvasObject>.unmodifiable(objects);

  final CanvasProjectTemplate template;
  final String name;
  final List<CanvasObject> objects;

  @override
  bool operator ==(Object other) =>
      other is BuiltInCanvasBoardTemplate &&
      other.template == template &&
      other.name == name &&
      const ListEquality<CanvasObject>().equals(other.objects, objects);

  @override
  int get hashCode => Object.hash(
    template,
    name,
    const ListEquality<CanvasObject>().hash(objects),
  );
}

final DateTime _builtInTemplateTime = DateTime.utc(2026, 1, 1);

BuiltInCanvasBoardTemplate _builtIn(
  CanvasProjectTemplate template,
  String name,
) => BuiltInCanvasBoardTemplate(
  template: template,
  name: name,
  objects: CanvasBoard.project(
    workspaceName: 'template:$name',
    nodes: const <MindmapNode>[],
    now: _builtInTemplateTime,
  ).addProjectTemplate(template, now: _builtInTemplateTime).objects,
);

final List<BuiltInCanvasBoardTemplate> builtInCanvasBoardTemplates =
    List<BuiltInCanvasBoardTemplate>.unmodifiable(<BuiltInCanvasBoardTemplate>[
      _builtIn(CanvasProjectTemplate.projectPlan, 'Project Plan'),
      _builtIn(CanvasProjectTemplate.kanban, 'Kanban'),
      _builtIn(CanvasProjectTemplate.brainstorm, 'Brainstorm'),
      _builtIn(CanvasProjectTemplate.contentCalendar, 'Content Calendar'),
      _builtIn(CanvasProjectTemplate.weeklyPlanner, 'Weekly Planner'),
      _builtIn(CanvasProjectTemplate.researchBoard, 'Research Board'),
      _builtIn(CanvasProjectTemplate.moodboard, 'Moodboard'),
      _builtIn(CanvasProjectTemplate.goalTracker, 'Goal Tracker'),
    ]);
