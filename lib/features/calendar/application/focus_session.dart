/// Local focus-session metadata helpers for mission mode.
library;

import '../../mindmap/domain/mindmap_node.dart';

const focusSessionsDataKey = 'focusSessions';
const todayMissionDataKey = 'todayMission';

final class FocusSessionRecord {
  const FocusSessionRecord({
    required this.startedAt,
    required this.endedAt,
    required this.durationMinutes,
  });

  factory FocusSessionRecord.fromJson(Map<String, Object?> json) {
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '');
    final duration = json['durationMinutes'];
    return FocusSessionRecord(
      startedAt: startedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: endedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      durationMinutes: duration is num ? duration.round() : 0,
    );
  }

  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMinutes;

  Map<String, Object?> toJson() {
    return {
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationMinutes': durationMinutes,
    };
  }
}

List<FocusSessionRecord> focusSessionsForNode(MindmapNode node) {
  final raw = node.data[focusSessionsDataKey];
  if (raw is! List) return const [];
  return List.unmodifiable([
    for (final item in raw)
      if (item is Map)
        FocusSessionRecord.fromJson(item.cast<String, Object?>()),
  ]);
}

int totalFocusMinutes(MindmapNode node) {
  return focusSessionsForNode(
    node,
  ).fold<int>(0, (total, session) => total + session.durationMinutes);
}

String nextFocusAction(MindmapNode node) {
  for (final line in node.body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('- [ ]')) {
      final action = trimmed.substring(5).trim();
      if (action.isNotEmpty) return action;
    }
  }
  final title = node.title.trim();
  if (title.isNotEmpty) return title;
  return 'Define next action';
}

MindmapNode markTodayMission(MindmapNode node, {required bool isMission}) {
  return node.copyWith(
    data: {...node.data, todayMissionDataKey: isMission},
    updatedAt: DateTime.now(),
  );
}

bool isTodayMission(MindmapNode node) {
  return node.data[todayMissionDataKey] == true;
}

bool canAddTodayMission(
  Iterable<MindmapNode> nodes,
  MindmapNode node, {
  int limit = 3,
}) {
  if (isTodayMission(node)) return true;
  final count = nodes.where((candidate) {
    return candidate.id != node.id && isTodayMission(candidate);
  }).length;
  return count < limit;
}

MindmapNode addFocusSession(
  MindmapNode node, {
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  final duration = endedAt.difference(startedAt).inMinutes;
  if (duration <= 0) return node;
  final sessions = focusSessionsForNode(node);
  final next = [
    ...sessions,
    FocusSessionRecord(
      startedAt: startedAt,
      endedAt: endedAt,
      durationMinutes: duration,
    ),
  ];
  return node.copyWith(
    data: {
      ...node.data,
      focusSessionsDataKey: [for (final session in next) session.toJson()],
    },
    updatedAt: endedAt,
  );
}
