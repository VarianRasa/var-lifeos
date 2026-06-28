/// Automation audit trail events stored as hidden mindmap nodes.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

const automationEventDataKey = 'automationEvent';

enum AutomationEventType {
  applyRoutines,
  skipRoutines,
  snoozeRoutines,
  pauseDuplicateRules,
}

final class AutomationEventRecord {
  AutomationEventRecord({
    required this.nodeId,
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.day,
    required this.occurredAt,
    required List<String> affectedRuleNodeIds,
    required List<String> affectedLabels,
  }) : affectedRuleNodeIds = List.unmodifiable(affectedRuleNodeIds),
       affectedLabels = List.unmodifiable(affectedLabels);

  final String nodeId;
  final String id;
  final AutomationEventType type;
  final String title;
  final String message;
  final DateTime day;
  final DateTime occurredAt;
  final List<String> affectedRuleNodeIds;
  final List<String> affectedLabels;
}

MindmapNode createAutomationEventNode({
  required String id,
  required AutomationEventType type,
  required String title,
  required String message,
  required DateTime day,
  required DateTime occurredAt,
  List<String> affectedRuleNodeIds = const [],
  List<String> affectedLabels = const [],
}) {
  return MindmapNode.create(
    id: 'automation-event-$id',
    type: NodeType.note,
    title: 'Automation event: $title',
    body: message,
    day: day,
    tags: const ['automation', 'automation-event'],
    isArchived: true,
    data: {
      automationEventDataKey: {
        'id': id,
        'type': type.name,
        'title': title,
        'message': message,
        'occurredAt': occurredAt.toIso8601String(),
        'affectedRuleNodeIds': affectedRuleNodeIds,
        'affectedLabels': affectedLabels,
      },
    },
    now: occurredAt,
  );
}

List<AutomationEventRecord> automationEventsFromNodes(
  Iterable<MindmapNode> nodes,
) {
  final events = <AutomationEventRecord>[];
  for (final node in nodes) {
    final event = automationEventFromNode(node);
    if (event != null) events.add(event);
  }
  events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return List.unmodifiable(events);
}

AutomationEventRecord? automationEventFromNode(MindmapNode node) {
  final data = node.data[automationEventDataKey];
  if (data is! Map) return null;
  final eventData = data.cast<String, Object?>();

  final id = _stringValue(eventData['id']);
  final type = _eventTypeFromName(_stringValue(eventData['type']));
  final title = _stringValue(eventData['title']);
  final message = _stringValue(eventData['message']);
  final occurredAt = DateTime.tryParse(
    _stringValue(eventData['occurredAt']) ?? '',
  );

  if (id == null ||
      type == null ||
      title == null ||
      message == null ||
      occurredAt == null) {
    return null;
  }

  return AutomationEventRecord(
    nodeId: node.id,
    id: id,
    type: type,
    title: title,
    message: message,
    day: node.day,
    occurredAt: occurredAt,
    affectedRuleNodeIds: _stringList(eventData['affectedRuleNodeIds']),
    affectedLabels: _stringList(eventData['affectedLabels']),
  );
}

AutomationEventType? _eventTypeFromName(String? name) {
  for (final type in AutomationEventType.values) {
    if (type.name == name) return type;
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return List.unmodifiable([
    for (final item in value)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ]);
}
