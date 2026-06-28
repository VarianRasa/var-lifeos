/// Domain model for anything placed on a day's mindmap.
library;

import 'package:collection/collection.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'canvas_position.dart';

enum NodeStatus {
  open('Open'),
  planned('Planned'),
  doing('Doing'),
  waiting('Waiting'),
  done('Done');

  const NodeStatus(this.label);

  final String label;

  static NodeStatus fromName(String? name) {
    for (final status in values) {
      if (status.name == name) return status;
    }
    return NodeStatus.open;
  }
}

enum NodePriority {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High'),
  urgent('Urgent');

  const NodePriority(this.label);

  final String label;

  static NodePriority fromName(String? name) {
    for (final priority in values) {
      if (priority.name == name) return priority;
    }
    return NodePriority.none;
  }
}

final class TaskChecklistItem {
  const TaskChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  factory TaskChecklistItem.fromJson(Map<String, Object?> json) {
    return TaskChecklistItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
    );
  }

  final String id;
  final String title;
  final bool isDone;

  TaskChecklistItem copyWith({String? id, String? title, bool? isDone}) {
    return TaskChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'isDone': isDone};

  @override
  bool operator ==(Object other) {
    return other is TaskChecklistItem &&
        other.id == id &&
        other.title == title &&
        other.isDone == isDone;
  }

  @override
  int get hashCode => Object.hash(id, title, isDone);
}

final class MindmapNode {
  const MindmapNode({
    required this.id,
    required this.type,
    required this.title,
    required this.day,
    required this.createdAt,
    required this.updatedAt,
    this.body = '',
    this.position = const CanvasPosition(0, 0),
    this.isDone = false,
    this.status = NodeStatus.open,
    this.priority = NodePriority.none,
    this.project = '',
    this.area = '',
    this.tags = const [],
    this.dueDate,
    this.progress = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.checklist = const [],
    this.relatedNodeIds = const [],
    this.data = const {},
  });

  factory MindmapNode.create({
    required String id,
    required NodeType type,
    required String title,
    required DateTime day,
    String body = '',
    CanvasPosition position = const CanvasPosition(0, 0),
    bool isDone = false,
    NodeStatus status = NodeStatus.open,
    NodePriority priority = NodePriority.none,
    String project = '',
    String area = '',
    List<String> tags = const [],
    DateTime? dueDate,
    double progress = 0,
    bool isPinned = false,
    bool isArchived = false,
    List<TaskChecklistItem> checklist = const [],
    List<String> relatedNodeIds = const [],
    Map<String, Object?> data = const {},
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return MindmapNode(
      id: id,
      type: type,
      title: title,
      body: body,
      day: day.dateOnly,
      position: position,
      createdAt: timestamp,
      updatedAt: timestamp,
      isDone: isDone,
      status: status,
      priority: priority,
      project: _normalizeContextName(project),
      area: _normalizeContextName(area),
      tags: _normalizeTags(tags),
      dueDate: dueDate?.dateOnly,
      progress: _normalizeProgress(progress),
      isPinned: isPinned,
      isArchived: isArchived,
      checklist: _normalizeChecklist(checklist),
      relatedNodeIds: _normalizeNodeIds(relatedNodeIds, selfId: id),
      data: data,
    );
  }

  factory MindmapNode.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String;
    return MindmapNode(
      id: id,
      type: _nodeTypeFromName(json['type'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      day: DateTime.parse(json['day'] as String).dateOnly,
      position: CanvasPosition.fromJson(
        (json['position'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isDone: json['isDone'] as bool? ?? false,
      status: NodeStatus.fromName(json['status'] as String?),
      priority: NodePriority.fromName(json['priority'] as String?),
      project: _contextNameFromJson(json['project']),
      area: _contextNameFromJson(json['area']),
      tags: _tagsFromJson(json['tags']),
      dueDate: _dateFromJson(json['dueDate']),
      progress: _normalizeProgress((json['progress'] as num?)?.toDouble() ?? 0),
      isPinned: json['isPinned'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      checklist: _checklistFromJson(json['checklist']),
      relatedNodeIds: _nodeIdsFromJson(json['relatedNodeIds'], selfId: id),
      data: _dataFromJson(json['data']),
    );
  }

  final String id;
  final NodeType type;
  final String title;
  final String body;
  final DateTime day;
  final CanvasPosition position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDone;
  final NodeStatus status;
  final NodePriority priority;
  final String project;
  final String area;
  final List<String> tags;
  final DateTime? dueDate;
  final double progress;
  final bool isPinned;
  final bool isArchived;
  final List<TaskChecklistItem> checklist;
  final List<String> relatedNodeIds;
  final Map<String, Object?> data;

  int get completedChecklistCount {
    return checklist.where((item) => item.isDone).length;
  }

  double get checklistProgress {
    if (checklist.isEmpty) return 0;
    return completedChecklistCount / checklist.length;
  }

  bool get hasDueDate => dueDate != null;

  MindmapNode copyWith({
    String? id,
    NodeType? type,
    String? title,
    String? body,
    DateTime? day,
    CanvasPosition? position,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDone,
    NodeStatus? status,
    NodePriority? priority,
    String? project,
    String? area,
    List<String>? tags,
    DateTime? dueDate,
    bool clearDueDate = false,
    double? progress,
    bool? isPinned,
    bool? isArchived,
    List<TaskChecklistItem>? checklist,
    List<String>? relatedNodeIds,
    Map<String, Object?>? data,
  }) {
    final nextId = id ?? this.id;
    return MindmapNode(
      id: nextId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      day: (day ?? this.day).dateOnly,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDone: isDone ?? this.isDone,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      project: _normalizeContextName(project ?? this.project),
      area: _normalizeContextName(area ?? this.area),
      tags: _normalizeTags(tags ?? this.tags),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate)?.dateOnly,
      progress: _normalizeProgress(progress ?? this.progress),
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      checklist: _normalizeChecklist(checklist ?? this.checklist),
      relatedNodeIds: _normalizeNodeIds(
        relatedNodeIds ?? this.relatedNodeIds,
        selfId: nextId,
      ),
      data: data ?? this.data,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'body': body,
    'day': dayKey(day),
    'position': position.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isDone': isDone,
    'status': status.name,
    'priority': priority.name,
    'project': project,
    'area': area,
    'tags': tags,
    'dueDate': dueDate == null ? null : dayKey(dueDate!),
    'progress': progress,
    'isPinned': isPinned,
    'isArchived': isArchived,
    'checklist': [for (final item in checklist) item.toJson()],
    'relatedNodeIds': relatedNodeIds,
    'data': data,
  };

  @override
  bool operator ==(Object other) {
    return other is MindmapNode &&
        other.id == id &&
        other.type == type &&
        other.title == title &&
        other.body == body &&
        other.day == day &&
        other.position == position &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isDone == isDone &&
        other.status == status &&
        other.priority == priority &&
        other.project == project &&
        other.area == area &&
        const ListEquality<String>().equals(other.tags, tags) &&
        other.dueDate == dueDate &&
        other.progress == progress &&
        other.isPinned == isPinned &&
        other.isArchived == isArchived &&
        const ListEquality<TaskChecklistItem>().equals(
          other.checklist,
          checklist,
        ) &&
        const ListEquality<String>().equals(
          other.relatedNodeIds,
          relatedNodeIds,
        ) &&
        const DeepCollectionEquality().equals(other.data, data);
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    title,
    body,
    day,
    position,
    createdAt,
    updatedAt,
    isDone,
    status,
    priority,
    project,
    area,
    const ListEquality<String>().hash(tags),
    dueDate,
    progress,
    isPinned,
    isArchived,
    const ListEquality<TaskChecklistItem>().hash(checklist),
    const ListEquality<String>().hash(relatedNodeIds),
    const DeepCollectionEquality().hash(data),
  ]);
}

Map<String, Object?> _dataFromJson(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

String _contextNameFromJson(Object? value) {
  if (value is! String) return '';
  return _normalizeContextName(value);
}

List<String> _tagsFromJson(Object? value) {
  if (value is! List) return const [];
  return _normalizeTags([
    for (final tag in value)
      if (tag is String) tag,
  ]);
}

DateTime? _dateFromJson(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.dateOnly;
}

List<TaskChecklistItem> _checklistFromJson(Object? value) {
  if (value is! List) return const [];
  return _normalizeChecklist([
    for (final item in value)
      if (item is Map) TaskChecklistItem.fromJson(item.cast<String, Object?>()),
  ]);
}

List<String> _nodeIdsFromJson(Object? value, {required String selfId}) {
  if (value is! List) return const [];
  return _normalizeNodeIds([
    for (final nodeId in value)
      if (nodeId is String) nodeId,
  ], selfId: selfId);
}

List<String> _normalizeTags(List<String> tags) {
  final seen = <String>{};
  final normalized = <String>[];

  for (final tag in tags) {
    final value = tag.trim().toLowerCase().replaceFirst(RegExp('^#+'), '');
    if (value.isEmpty || !seen.add(value)) continue;
    normalized.add(value);
  }

  return List.unmodifiable(normalized);
}

List<String> _normalizeNodeIds(List<String> nodeIds, {required String selfId}) {
  final seen = <String>{};
  final normalized = <String>[];

  for (final nodeId in nodeIds) {
    final value = nodeId.trim();
    if (value.isEmpty || value == selfId || !seen.add(value)) continue;
    normalized.add(value);
  }

  return List.unmodifiable(normalized);
}

String _normalizeContextName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

List<TaskChecklistItem> _normalizeChecklist(List<TaskChecklistItem> checklist) {
  final normalized = <TaskChecklistItem>[];
  for (final item in checklist) {
    final title = item.title.trim();
    if (title.isEmpty) continue;
    normalized.add(item.copyWith(title: title));
  }
  return List.unmodifiable(normalized);
}

double _normalizeProgress(double progress) {
  if (progress.isNaN) return 0;
  return progress.clamp(0, 1).toDouble();
}

NodeType _nodeTypeFromName(String? name) {
  for (final type in NodeType.values) {
    if (type.name == name) return type;
  }
  return NodeType.note;
}
