/// Markdown checklist extraction for note/task bodies.
library;

import 'mindmap_node.dart';

final _markdownChecklistPattern = RegExp(
  r'^\s*[-*+]\s+\[( |x|X)\]\s+(.+?)\s*$',
);

List<TaskChecklistItem> parseMarkdownChecklist(String body) {
  final items = <TaskChecklistItem>[];
  var index = 0;
  for (final line in body.split('\n')) {
    final match = _markdownChecklistPattern.firstMatch(line);
    if (match == null) continue;
    final title = match.group(2)?.trim() ?? '';
    if (title.isEmpty) continue;
    items.add(
      TaskChecklistItem(
        id: 'md-${index++}-${title.hashCode.abs()}',
        title: title,
        isDone: (match.group(1) ?? '').toLowerCase() == 'x',
      ),
    );
  }
  return List.unmodifiable(items);
}
