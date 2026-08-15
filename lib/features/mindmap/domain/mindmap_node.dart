/// Domain model for anything placed on a day's mindmap.
library;

import 'dart:convert';

import 'package:collection/collection.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'canvas_position.dart';

enum NodeStatus {
  inbox('Inbox'),
  open('Open'),
  next('Next'),
  planned('Planned'),
  doing('Doing'),
  waiting('Waiting'),
  someday('Someday'),
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

enum NodeEffort {
  unspecified('Unspecified'),
  fiveMinutes('5m'),
  fifteenMinutes('15m'),
  thirtyMinutes('30m'),
  oneHourPlus('1h+');

  const NodeEffort(this.label);

  final String label;

  static NodeEffort fromName(String? name) {
    for (final effort in values) {
      if (effort.name == name) return effort;
    }
    return NodeEffort.unspecified;
  }
}

enum NodeReviewState {
  none('None'),
  needsReview('Needs review'),
  stale('Stale'),
  someday('Someday'),
  parked('Parked');

  const NodeReviewState(this.label);

  final String label;

  static NodeReviewState fromName(String? name) {
    for (final state in values) {
      if (state.name == name) return state;
    }
    return NodeReviewState.none;
  }
}

final class TaskChecklistItem {
  const TaskChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
    this.parentId,
  });

  factory TaskChecklistItem.fromJson(Map<String, Object?> json) {
    return TaskChecklistItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      isDone: json['isDone'] as bool? ?? false,
      parentId: json['parentId'] as String?,
    );
  }

  final String id;
  final String title;
  final bool isDone;
  final String? parentId;

  TaskChecklistItem copyWith({
    String? id,
    String? title,
    bool? isDone,
    String? parentId,
    bool clearParentId = false,
  }) {
    return TaskChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      parentId: clearParentId ? null : parentId ?? this.parentId,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'isDone': isDone,
    if (parentId != null) 'parentId': parentId,
  };

  @override
  bool operator ==(Object other) {
    return other is TaskChecklistItem &&
        other.id == id &&
        other.title == title &&
        other.isDone == isDone &&
        other.parentId == parentId;
  }

  @override
  int get hashCode => Object.hash(id, title, isDone, parentId);
}

final class MindmapNode {
  MindmapNode({
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
    this.effort = NodeEffort.unspecified,
    this.reviewState = NodeReviewState.none,
    this.project = '',
    this.area = '',
    List<String> tags = const [],
    List<String> contextTags = const [],
    this.dueDate,
    this.progress = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isLocked = false,
    List<TaskChecklistItem> checklist = const [],
    List<String> relatedNodeIds = const [],
    List<String> blockedByNodeIds = const [],
    Map<String, Object?> data = const {},
  }) : tags = List<String>.unmodifiable(tags),
       contextTags = List<String>.unmodifiable(contextTags),
       checklist = _normalizeChecklist(checklist),
       relatedNodeIds = List<String>.unmodifiable(relatedNodeIds),
       blockedByNodeIds = List<String>.unmodifiable(blockedByNodeIds) {
    this.data = _freezeData(data);
    presentationDataKey = _presentationDataKey(type, this.data, this.checklist);
    presentationDataRevision = presentationDataKey.hashCode;
  }

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
    NodeEffort effort = NodeEffort.unspecified,
    NodeReviewState reviewState = NodeReviewState.none,
    String project = '',
    String area = '',
    List<String> tags = const [],
    List<String> contextTags = const [],
    DateTime? dueDate,
    double progress = 0,
    bool isPinned = false,
    bool isArchived = false,
    bool isLocked = false,
    List<TaskChecklistItem> checklist = const [],
    List<String> relatedNodeIds = const [],
    List<String> blockedByNodeIds = const [],
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
      effort: effort,
      reviewState: reviewState,
      project: _normalizeContextName(project),
      area: _normalizeContextName(area),
      tags: _normalizeTags(tags),
      contextTags: _normalizeTags(contextTags),
      dueDate: dueDate?.dateOnly,
      progress: _normalizeProgress(progress),
      isPinned: isPinned,
      isArchived: isArchived,
      isLocked: isLocked,
      checklist: _normalizeChecklist(checklist),
      relatedNodeIds: _normalizeNodeIds(relatedNodeIds, selfId: id),
      blockedByNodeIds: _normalizeNodeIds(blockedByNodeIds, selfId: id),
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
      effort: NodeEffort.fromName(json['effort'] as String?),
      reviewState: NodeReviewState.fromName(json['reviewState'] as String?),
      project: _contextNameFromJson(json['project']),
      area: _contextNameFromJson(json['area']),
      tags: _tagsFromJson(json['tags']),
      contextTags: _tagsFromJson(json['contextTags']),
      dueDate: _dateFromJson(json['dueDate']),
      progress: _normalizeProgress((json['progress'] as num?)?.toDouble() ?? 0),
      isPinned: json['isPinned'] as bool? ?? false,
      isArchived: json['isArchived'] as bool? ?? false,
      isLocked: json['isLocked'] as bool? ?? false,
      checklist: _checklistFromJson(json['checklist']),
      relatedNodeIds: _nodeIdsFromJson(json['relatedNodeIds'], selfId: id),
      blockedByNodeIds: _nodeIdsFromJson(json['blockedByNodeIds'], selfId: id),
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
  final NodeEffort effort;
  final NodeReviewState reviewState;
  final String project;
  final String area;
  final List<String> tags;
  final List<String> contextTags;
  final DateTime? dueDate;
  final double progress;
  final bool isPinned;
  final bool isArchived;
  final bool isLocked;
  final List<TaskChecklistItem> checklist;
  final List<String> relatedNodeIds;
  final List<String> blockedByNodeIds;
  late final Map<String, Object?> data;
  late final String presentationDataKey;
  late final int presentationDataRevision;

  int get completedChecklistCount {
    return checklist.where((item) => item.isDone).length;
  }

  double get checklistProgress {
    if (checklist.isEmpty) return 0;
    return completedChecklistCount / checklist.length;
  }

  bool get hasDueDate => dueDate != null;

  bool isBlockedBy(List<MindmapNode> allNodes) {
    if (blockedByNodeIds.isEmpty) return false;
    final nodeMap = {for (final n in allNodes) n.id: n};
    for (final id in blockedByNodeIds) {
      final blocker = nodeMap[id];
      if (blocker != null &&
          !blocker.isDone &&
          blocker.status != NodeStatus.done) {
        return true;
      }
    }
    return false;
  }

  bool isNextActionCandidate(DateTime today) {
    if (isDone || status == NodeStatus.done || isArchived) return false;
    if (reviewState == NodeReviewState.someday ||
        reviewState == NodeReviewState.parked) {
      return false;
    }
    return nextActionScore(today) > 0;
  }

  List<String> reviewNudges(DateTime today) {
    if (isDone || status == NodeStatus.done || isArchived) return const [];
    final normalizedToday = today.dateOnly;
    final nudges = <String>[];
    if (reviewState == NodeReviewState.needsReview ||
        reviewState == NodeReviewState.stale) {
      nudges.add('Pick next action');
    }
    if (effort == NodeEffort.unspecified && type == NodeType.task) {
      nudges.add('Set effort');
    }
    final due = dueDate;
    if (due != null && due.dateOnly.isBefore(normalizedToday)) {
      nudges.add('Reschedule overdue node');
    }
    if (checklist.isNotEmpty && checklistProgress < 1) {
      nudges.add(
        'Finish checklist: $completedChecklistCount/${checklist.length} done',
      );
    }
    if (status == NodeStatus.waiting && relatedNodeIds.isEmpty) {
      nudges.add('Link blocker or owner');
    }
    if (contextTags.isEmpty && type == NodeType.task) {
      nudges.add('Add context tag');
    }
    return List.unmodifiable(nudges.take(4));
  }

  int nextActionScore(DateTime today) {
    if (isDone || status == NodeStatus.done || isArchived) return 0;
    final normalizedToday = today.dateOnly;
    var score = 0;
    score += switch (priority) {
      NodePriority.urgent => 50,
      NodePriority.high => 35,
      NodePriority.medium => 20,
      NodePriority.low => 8,
      NodePriority.none => 0,
    };
    score += switch (status) {
      NodeStatus.doing => 20,
      NodeStatus.next => 16,
      NodeStatus.planned => 14,
      NodeStatus.open => 8,
      NodeStatus.inbox => -10,
      NodeStatus.waiting => -20,
      NodeStatus.someday => -40,
      NodeStatus.done => -100,
    };
    score += switch (effort) {
      NodeEffort.fiveMinutes => 16,
      NodeEffort.fifteenMinutes => 12,
      NodeEffort.thirtyMinutes => 8,
      NodeEffort.oneHourPlus => 2,
      NodeEffort.unspecified => 4,
    };
    score += switch (reviewState) {
      NodeReviewState.needsReview => 12,
      NodeReviewState.stale => 6,
      NodeReviewState.none => 0,
      NodeReviewState.someday => -40,
      NodeReviewState.parked => -60,
    };
    final due = dueDate;
    if (due != null) {
      final days = due.dateOnly.difference(normalizedToday).inDays;
      if (days < 0) {
        score += 35;
      } else if (days == 0) {
        score += 28;
      } else if (days <= 3) {
        score += 16;
      } else if (days <= 7) {
        score += 8;
      }
    }
    if (checklist.isNotEmpty && checklistProgress < 1) score += 6;
    return score < 0 ? 0 : score;
  }

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
    NodeEffort? effort,
    NodeReviewState? reviewState,
    String? project,
    String? area,
    List<String>? tags,
    List<String>? contextTags,
    DateTime? dueDate,
    bool clearDueDate = false,
    double? progress,
    bool? isPinned,
    bool? isArchived,
    bool? isLocked,
    List<TaskChecklistItem>? checklist,
    List<String>? relatedNodeIds,
    List<String>? blockedByNodeIds,
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
      effort: effort ?? this.effort,
      reviewState: reviewState ?? this.reviewState,
      project: _normalizeContextName(project ?? this.project),
      area: _normalizeContextName(area ?? this.area),
      tags: _normalizeTags(tags ?? this.tags),
      contextTags: _normalizeTags(contextTags ?? this.contextTags),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate)?.dateOnly,
      progress: _normalizeProgress(progress ?? this.progress),
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isLocked: isLocked ?? this.isLocked,
      checklist: _normalizeChecklist(checklist ?? this.checklist),
      relatedNodeIds: _normalizeNodeIds(
        relatedNodeIds ?? this.relatedNodeIds,
        selfId: nextId,
      ),
      blockedByNodeIds: _normalizeNodeIds(
        blockedByNodeIds ?? this.blockedByNodeIds,
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
    'effort': effort.name,
    'reviewState': reviewState.name,
    'project': project,
    'area': area,
    'tags': tags,
    'contextTags': contextTags,
    'dueDate': dueDate == null ? null : dayKey(dueDate!),
    'progress': progress,
    'isPinned': isPinned,
    'isArchived': isArchived,
    'isLocked': isLocked,
    'checklist': [for (final item in checklist) item.toJson()],
    'relatedNodeIds': relatedNodeIds,
    'blockedByNodeIds': blockedByNodeIds,
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
        other.effort == effort &&
        other.reviewState == reviewState &&
        other.project == project &&
        other.area == area &&
        const ListEquality<String>().equals(other.tags, tags) &&
        const ListEquality<String>().equals(other.contextTags, contextTags) &&
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
    effort,
    reviewState,
    project,
    area,
    const ListEquality<String>().hash(tags),
    const ListEquality<String>().hash(contextTags),
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

Map<String, Object?> _freezeData(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>({
      for (final entry in source.entries)
        entry.key: _freezeDataValue(entry.value),
    });

Object? _freezeDataValue(Object? value) {
  if (value is Map) {
    if (value.keys.every((key) => key is String)) {
      return UnmodifiableMapView<String, Object?>({
        for (final entry in value.entries)
          entry.key as String: _freezeDataValue(entry.value),
      });
    }
    return UnmodifiableMapView<Object?, Object?>({
      for (final entry in value.entries)
        entry.key: _freezeDataValue(entry.value),
    });
  }
  if (value is List) {
    final frozen = [for (final item in value) _freezeDataValue(item)];
    if (frozen.every((item) => item is String)) {
      return List<String>.unmodifiable(frozen.cast<String>());
    }
    if (frozen.every((item) => item is int)) {
      return List<int>.unmodifiable(frozen.cast<int>());
    }
    if (frozen.every((item) => item is num)) {
      return List<num>.unmodifiable(frozen.cast<num>());
    }
    if (frozen.every((item) => item is bool)) {
      return List<bool>.unmodifiable(frozen.cast<bool>());
    }
    if (frozen.every((item) => item is Map<String, Object?>)) {
      return List<Map<String, Object?>>.unmodifiable(
        frozen.cast<Map<String, Object?>>(),
      );
    }
    return List<Object?>.unmodifiable(frozen);
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_freezeDataValue));
  }
  return value;
}

String _presentationDataKey(
  NodeType type,
  Map<String, Object?> data,
  List<TaskChecklistItem> checklist,
) =>
    '${type.name}|${_canonicalValue(data)}|${_canonicalValue([for (final item in checklist) item.toJson()])}';

String _canonicalValue(Object? value) {
  if (value == null) return 'n';
  if (value is String) return 's${jsonEncode(value)}';
  if (value is bool) return value ? 'b1' : 'b0';
  if (value is int) return 'i$value';
  if (value is double) {
    if (value.isNaN) return 'dNaN';
    if (value == double.infinity) return 'dInfinity';
    if (value == double.negativeInfinity) return 'd-Infinity';
    return 'd${value.toString()}';
  }
  if (value is num) return 'q${value.toString()}';
  if (value is DateTime) return 't${value.toIso8601String()}';
  if (value is Enum) return 'e${value.runtimeType}:${value.name}';
  if (value is Map) {
    final entries =
        [
          for (final entry in value.entries)
            (_canonicalValue(entry.key), _canonicalValue(entry.value)),
        ]..sort((left, right) {
          final keyOrder = left.$1.compareTo(right.$1);
          return keyOrder != 0 ? keyOrder : left.$2.compareTo(right.$2);
        });
    return 'm${entries.map((entry) => '${entry.$1}:${entry.$2}').join('|')}';
  }
  if (value is Set) {
    final items = value.map(_canonicalValue).toList()..sort();
    return 'u${items.join('|')}';
  }
  if (value is Iterable) {
    return 'l${value.map(_canonicalValue).join('|')}';
  }
  return 'o${value.runtimeType}:${jsonEncode(value.toString())}';
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

List<TaskChecklistItem> _normalizeChecklist(
  List<TaskChecklistItem> checklist,
) => normalizeTaskChecklistTree(checklist);

List<TaskChecklistItem> normalizeTaskChecklistTree(
  List<TaskChecklistItem> checklist,
) {
  final normalized = <TaskChecklistItem>[];
  for (final item in checklist) {
    final title = item.title.trim();
    if (title.isEmpty) continue;
    normalized.add(item.copyWith(title: title));
  }
  final ids = {for (final item in normalized) item.id};
  final byId = {for (final item in normalized) item.id: item};
  return List.unmodifiable([
    for (final item in normalized)
      if (item.parentId == null ||
          !ids.contains(item.parentId) ||
          _hasChecklistCycle(item.id, item.parentId!, byId))
        item.copyWith(clearParentId: true)
      else
        item,
  ]);
}

bool _hasChecklistCycle(
  String potentialAncestorId,
  String descendantId,
  Map<String, TaskChecklistItem> byId,
) {
  var cursor = byId[descendantId];
  final visited = <String>{};
  while (cursor != null) {
    final parentId = cursor.parentId;
    if (parentId == null) break;
    if (parentId == potentialAncestorId) return true;
    if (!visited.add(parentId)) return true;
    cursor = byId[parentId];
  }
  return false;
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
