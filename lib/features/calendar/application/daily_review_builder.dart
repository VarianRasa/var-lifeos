/// Daily review journal body generation.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

String dailyReviewTitle(DateTime day) => 'Daily review — ${dayKey(day)}';

String buildDailyReviewBody(DateTime day, List<MindmapNode> nodes) {
  final activeNodes = nodes.where((node) => !node.isArchived).toList();
  final completedTasks = activeNodes
      .where(
        (node) =>
            node.type == NodeType.task &&
            (node.isDone || node.status == NodeStatus.done),
      )
      .toList();
  final openTasks = activeNodes
      .where(
        (node) =>
            node.type == NodeType.task &&
            !node.isDone &&
            node.status != NodeStatus.done &&
            node.status != NodeStatus.next,
      )
      .toList();
  final blocked = activeNodes
      .where((node) => node.status == NodeStatus.waiting)
      .toList();

  return [
    '# ${dailyReviewTitle(day)}',
    '',
    '## Wins',
    '- ',
    '',
    '## Completed',
    if (completedTasks.isEmpty)
      '- None yet'
    else
      ..._bulletTitles(completedTasks),
    '',
    '## Blocked',
    if (blocked.isEmpty) '- None' else ..._bulletTitles(blocked),
    '',
    '## Lessons',
    '- ',
    '',
    '## Carry to tomorrow',
    if (openTasks.isEmpty) '- None' else ..._bulletTitles(openTasks),
    '',
    '## Tomorrow top 3',
    '- ',
    '- ',
    '- ',
  ].join('\n');
}

List<String> extractTomorrowTop3(String body) {
  final lines = body.split('\n');
  final items = <String>[];
  var inSection = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.startsWith('## ')) {
      inSection = line.toLowerCase() == '## tomorrow top 3';
      continue;
    }
    if (!inSection || line.isEmpty) continue;

    final value = line.replaceFirst(RegExp(r'^[-*]\s*'), '').trim();
    if (value.isEmpty) continue;
    items.add(value);
    if (items.length == 3) break;
  }

  return List.unmodifiable(items);
}

List<String> _bulletTitles(List<MindmapNode> nodes) {
  return [
    for (final node in nodes.take(8))
      '- ${node.title.trim().isEmpty ? node.type.label : node.title.trim()}',
  ];
}
