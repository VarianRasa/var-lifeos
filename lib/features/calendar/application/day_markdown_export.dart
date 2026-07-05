/// Markdown export for a single day.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';

String buildDayMarkdownExport({
  required DateTime day,
  required List<MindmapNode> nodes,
}) {
  final active =
      nodes
          .where(
            (node) => !node.isArchived && node.day.dateOnly == day.dateOnly,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final completedTasks = active
      .where((node) => node.type == NodeType.task && _isComplete(node))
      .toList();
  final openTasks = active
      .where((node) => node.type == NodeType.task && !_isComplete(node))
      .toList();
  final notes = active
      .where(
        (node) => node.type == NodeType.note || node.type == NodeType.journal,
      )
      .toList();
  final links = active
      .where(
        (node) =>
            node.type == NodeType.link ||
            node.type == NodeType.resource ||
            node.type == NodeType.bookmark,
      )
      .toList();
  final decisions = active
      .where((node) => node.type == NodeType.decision)
      .toList();
  final carryOver = openTasks.take(5).toList();

  final buffer = StringBuffer()
    ..writeln('# Day summary — ${dayKey(day)}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln('- Total nodes: ${active.length}')
    ..writeln('- Completed tasks: ${completedTasks.length}')
    ..writeln('- Open tasks: ${openTasks.length}')
    ..writeln('- Notes/journals: ${notes.length}')
    ..writeln('- Links/resources: ${links.length}')
    ..writeln('- Decisions: ${decisions.length}')
    ..writeln();

  _writeNodeSection(buffer, 'Completed tasks', completedTasks, checked: true);
  _writeNodeSection(buffer, 'Open tasks', openTasks);
  _writeNodeSection(buffer, 'Notes / journal', notes, includeBody: true);
  _writeNodeSection(buffer, 'Links / resources', links, includeBody: true);
  _writeNodeSection(buffer, 'Decisions', decisions, includeBody: true);
  _writeNodeSection(buffer, 'Tomorrow carry-over', carryOver);

  return buffer.toString().trimRight();
}

void _writeNodeSection(
  StringBuffer buffer,
  String title,
  List<MindmapNode> nodes, {
  bool checked = false,
  bool includeBody = false,
}) {
  buffer
    ..writeln('## $title')
    ..writeln();
  if (nodes.isEmpty) {
    buffer
      ..writeln('_None_')
      ..writeln();
    return;
  }
  for (final node in nodes) {
    final marker = node.type == NodeType.task ? (checked ? '[x]' : '[ ]') : '-';
    final title = node.title.trim().isEmpty
        ? 'Untitled ${node.type.label}'
        : node.title.trim();
    if (node.type == NodeType.task) {
      buffer.writeln('- $marker $title${_metadataSuffix(node)}');
    } else {
      buffer.writeln('- $title${_metadataSuffix(node)}');
    }
    if (includeBody && node.body.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(_indentBody(node.body.trim()))
        ..writeln();
    }
  }
  buffer.writeln();
}

String _metadataSuffix(MindmapNode node) {
  final parts = [
    if (node.priority != NodePriority.none) node.priority.label,
    if (node.project.isNotEmpty) 'project: ${node.project}',
    if (node.area.isNotEmpty) 'area: ${node.area}',
    if (node.tags.isNotEmpty) node.tags.map((tag) => '#$tag').join(' '),
    if (node.dueDate != null) 'due: ${dayKey(node.dueDate!)}',
  ];
  return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
}

String _indentBody(String body) {
  return body.split('\n').map((line) => '  > $line').join('\n');
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}
