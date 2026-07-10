import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/date_utils.dart';
import '../application/mindmap_providers.dart';
import '../domain/goal_progress.dart';
import '../domain/habit_completion.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';
import '../domain/plan_progress.dart';
import 'mindmap_canvas.dart'; // for nodeColor, nodeIcon

class _InlineNodePageEditor extends ConsumerStatefulWidget {
  const _InlineNodePageEditor({required this.node});

  final MindmapNode node;

  @override
  ConsumerState<_InlineNodePageEditor> createState() =>
      _InlineNodePageEditorState();
}

class _InlineNodePageEditorState extends ConsumerState<_InlineNodePageEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late NodeStatus _status;
  late NodePriority _priority;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _body = TextEditingController();
    _hydrate(widget.node);
    for (final controller in [_title, _body]) {
      controller.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void didUpdateWidget(covariant _InlineNodePageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.node != widget.node) _hydrate(widget.node);
  }

  void _hydrate(MindmapNode node) {
    _title.text = node.title;
    _body.text = node.body;
    _status = node.status;
    _priority = node.priority;
    _dirty = false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final node = widget.node;
    final updated = node.copyWith(
      title: _title.text.trim().isEmpty ? node.title : _title.text.trim(),
      body: _body.text.trim(),
      status: _status,
      priority: _priority,
      updatedAt: DateTime.now(),
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (mounted) setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final node = widget.node;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(nodeIcon(node.type), color: nodeColor(node.type)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Edit ${node.type.label} on page',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _dirty ? _save : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Rich description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<NodeStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: NodeStatus.values
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      if (v != null) {
                        _status = v;
                        _dirty = true;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<NodePriority>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: NodePriority.values
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      if (v != null) {
                        _priority = v;
                        _dirty = true;
                      }
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use the workspace below for ${node.type.label.toLowerCase()}-specific fields.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableTaskWorkspace extends ConsumerStatefulWidget {
  const _EditableTaskWorkspace({required this.node});
  final MindmapNode node;
  @override
  ConsumerState<_EditableTaskWorkspace> createState() =>
      _EditableTaskWorkspaceState();
}

class _EditableTaskWorkspaceState
    extends ConsumerState<_EditableTaskWorkspace> {
  final _newItem = TextEditingController();
  Future<void> _save(List<TaskChecklistItem> items) async {
    final updated = widget.node.copyWith(
      checklist: items,
      updatedAt: DateTime.now(),
    );
    final repo = ref.read(mindmapRepositoryProvider);
    await repo.saveNode(updated);
    invalidateMindmapState(ref, day: widget.node.day);
  }

  @override
  void dispose() {
    _newItem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.node.checklist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: item.isDone,
            title: TextFormField(
              initialValue: item.title,
              decoration: const InputDecoration(border: InputBorder.none),
              onFieldSubmitted: (value) => _save([
                for (final current in items)
                  current.id == item.id
                      ? current.copyWith(title: value.trim())
                      : current,
              ]),
            ),
            onChanged: (value) => _save([
              for (final current in items)
                current.id == item.id
                    ? current.copyWith(isDone: value ?? false)
                    : current,
            ]),
            secondary: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _save([
                for (final current in items)
                  if (current.id != item.id) current,
              ]),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newItem,
                decoration: const InputDecoration(
                  labelText: 'Add checklist item',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                final title = _newItem.text.trim();
                if (title.isEmpty) return;
                _newItem.clear();
                _save([
                  ...items,
                  TaskChecklistItem(
                    id: 'item-${DateTime.now().microsecondsSinceEpoch}',
                    title: title,
                  ),
                ]);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditablePlanWorkspace extends _EditableLineWorkspace {
  const _EditablePlanWorkspace({required super.node})
    : super(kind: _LineWorkspaceKind.plan);
}

class _EditableGoalWorkspace extends _EditableLineWorkspace {
  const _EditableGoalWorkspace({required super.node})
    : super(kind: _LineWorkspaceKind.goal);
}

enum _LineWorkspaceKind { plan, goal }

class _EditableLineWorkspace extends ConsumerStatefulWidget {
  const _EditableLineWorkspace({required this.node, required this.kind});
  final MindmapNode node;
  final _LineWorkspaceKind kind;
  @override
  ConsumerState<_EditableLineWorkspace> createState() =>
      _EditableLineWorkspaceState();
}

class _EditableLineWorkspaceState
    extends ConsumerState<_EditableLineWorkspace> {
  final _newItem = TextEditingController();
  List<String> get _items => widget.kind == _LineWorkspaceKind.plan
      ? planSteps(widget.node)
      : goalMilestones(widget.node);
  Set<String> get _done => widget.kind == _LineWorkspaceKind.plan
      ? completedPlanSteps(widget.node).toSet()
      : completedGoalMilestones(widget.node).toSet();
  Future<void> _save(List<String> items, Set<String> done) async {
    final key = widget.kind == _LineWorkspaceKind.plan ? 'plan' : 'goal';
    final updatedData = {
      ...widget.node.data,
      key: widget.kind == _LineWorkspaceKind.plan
          ? {'steps': items, 'completedSteps': done.toList()}
          : {'milestones': items, 'completedMilestones': done.toList()},
    };
    final repo = ref.read(mindmapRepositoryProvider);
    await repo.saveNode(
      widget.node.copyWith(data: updatedData, updatedAt: DateTime.now()),
    );
    invalidateMindmapState(ref, day: widget.node.day);
  }

  @override
  void dispose() {
    _newItem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final done = _done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: done.contains(item),
            title: TextFormField(
              initialValue: item,
              decoration: const InputDecoration(border: InputBorder.none),
              onFieldSubmitted: (value) {
                final renamed = value.trim();
                if (renamed.isEmpty) return;
                _save(
                  [
                    for (final current in items)
                      current == item ? renamed : current,
                  ],
                  {
                    for (final current in done)
                      current == item ? renamed : current,
                  },
                );
              },
            ),
            onChanged: (value) {
              final nextDone = {...done};
              if (value ?? false) {
                nextDone.add(item);
              } else {
                nextDone.remove(item);
              }
              _save(items, nextDone);
            },
            secondary: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _save([
                for (final current in items)
                  if (current != item) current,
              ], {...done}..remove(item)),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newItem,
                decoration: InputDecoration(
                  labelText: widget.kind == _LineWorkspaceKind.plan
                      ? 'Add step'
                      : 'Add milestone',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                final value = _newItem.text.trim();
                if (value.isEmpty) return;
                _newItem.clear();
                _save([...items, value], done);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditableKanbanWorkspace extends ConsumerStatefulWidget {
  const _EditableKanbanWorkspace({required this.node});
  final MindmapNode node;
  @override
  ConsumerState<_EditableKanbanWorkspace> createState() =>
      _EditableKanbanWorkspaceState();
}

class _EditableKanbanWorkspaceState
    extends ConsumerState<_EditableKanbanWorkspace> {
  final _newCards = {
    for (final c in KanbanColumn.values) c: TextEditingController(),
  };
  KanbanBoard get _board => KanbanBoard.fromNodeData(widget.node.data);
  KanbanColumn? _previous(KanbanColumn column) => switch (column) {
    KanbanColumn.todo => null,
    KanbanColumn.doing => KanbanColumn.todo,
    KanbanColumn.done => KanbanColumn.doing,
  };

  Future<void> _save(KanbanBoard board) async {
    final repo = ref.read(mindmapRepositoryProvider);
    await repo.saveNode(
      widget.node.copyWith(
        data: {...widget.node.data, 'kanban': board.toJson()},
        updatedAt: DateTime.now(),
      ),
    );
    invalidateMindmapState(ref, day: widget.node.day);
  }

  @override
  void dispose() {
    for (final c in _newCards.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final columns = [
          for (final column in KanbanColumn.values)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      column.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    for (final card in board.cardsFor(column))
                      Card(
                        child: ListTile(
                          title: TextFormField(
                            initialValue: card.title,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                            ),
                            onFieldSubmitted: (value) => _save(
                              KanbanBoard(
                                cards: [
                                  for (final current in board.cards)
                                    current.id == card.id
                                        ? current.copyWith(title: value.trim())
                                        : current,
                                ],
                              ),
                            ),
                          ),
                          trailing: Wrap(
                            children: [
                              if (_previous(column) != null)
                                IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: () => _save(
                                    KanbanBoard(
                                      cards: [
                                        for (final current in board.cards)
                                          current.id == card.id
                                              ? current.copyWith(
                                                  column: _previous(column),
                                                )
                                              : current,
                                      ],
                                    ),
                                  ),
                                ),
                              if (column.next != null)
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _save(
                                    KanbanBoard(
                                      cards: [
                                        for (final current in board.cards)
                                          current.id == card.id
                                              ? current.copyWith(
                                                  column: column.next!,
                                                )
                                              : current,
                                      ],
                                    ),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _save(
                                  KanbanBoard(
                                    cards: [
                                      for (final current in board.cards)
                                        if (current.id != card.id) current,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newCards[column],
                            decoration: const InputDecoration(
                              labelText: 'New card',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final title = _newCards[column]!.text.trim();
                            if (title.isEmpty) return;
                            _newCards[column]!.clear();
                            _save(
                              KanbanBoard(
                                cards: [
                                  ...board.cards,
                                  KanbanCard(
                                    id: 'card-${DateTime.now().microsecondsSinceEpoch}',
                                    title: title,
                                    column: column,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ];
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final column in columns) Expanded(child: column),
                ],
              )
            : Column(mainAxisSize: MainAxisSize.min, children: columns);
      },
    );
  }
}

class _EditableFieldWorkspace extends ConsumerStatefulWidget {
  const _EditableFieldWorkspace({required this.node, required this.fields});
  final MindmapNode node;
  final List<String> fields;
  @override
  ConsumerState<_EditableFieldWorkspace> createState() =>
      _EditableFieldWorkspaceState();
}

class _EditableFieldWorkspaceState
    extends ConsumerState<_EditableFieldWorkspace> {
  late final Map<String, TextEditingController> _controllers;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        field: TextEditingController(text: _valueFor(field)),
    };
    for (final controller in _controllers.values) {
      controller.addListener(() => setState(() => _dirty = true));
    }
  }

  String _valueFor(String field) {
    final data = widget.node.data;
    final section = data[_sectionKey];
    if (section is Map && section[field] != null) {
      return section[field].toString();
    }
    if (data[field] != null) return data[field].toString();
    return '';
  }

  String get _sectionKey => switch (widget.node.type) {
    NodeType.habit => 'habit',
    NodeType.journal => 'journal',
    NodeType.note || NodeType.resource => 'note',
    NodeType.link || NodeType.bookmark => 'link',
    NodeType.goal => 'goal',
    NodeType.plan => 'plan',
    _ => widget.node.type.name,
  };

  String _label(String field) {
    return field
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}')
        .replaceAll('_', ' ')
        .trim()
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Future<void> _save() async {
    final section = <String, Object?>{
      for (final entry in _controllers.entries)
        entry.key: entry.value.text.trim(),
    };
    final data = {...widget.node.data, _sectionKey: section, ...section};
    final repo = ref.read(mindmapRepositoryProvider);
    await repo.saveNode(
      widget.node.copyWith(data: data, updatedAt: DateTime.now()),
    );
    invalidateMindmapState(ref, day: widget.node.day);
    if (mounted) setState(() => _dirty = false);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in widget.fields) ...[
          TextField(
            controller: _controllers[field],
            minLines:
                {
                  'agenda',
                  'actions',
                  'options',
                  'summary',
                  'keyPoints',
                  'completions',
                }.contains(field)
                ? 3
                : 1,
            maxLines:
                {
                  'agenda',
                  'actions',
                  'options',
                  'summary',
                  'keyPoints',
                  'completions',
                }.contains(field)
                ? 8
                : 1,
            decoration: InputDecoration(labelText: _label(field)),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _dirty ? _save : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save workspace'),
          ),
        ),
      ],
    );
  }
}

class NodeDetailPage extends ConsumerWidget {
  const NodeDetailPage({required this.date, required this.nodeId, super.key});

  final DateTime date;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allNodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Mindmap',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            goToDay(context, date, highlightNodeId: nodeId);
          },
        ),
        title: allNodesAsync.maybeWhen(
          data: (nodes) {
            final node = nodes.where((n) => n.id == nodeId).firstOrNull;
            return Text(
              node == null ? 'Node Details' : '${node.type.label} Page',
            );
          },
          orElse: () => const Text('Node Details'),
        ),
      ),
      body: allNodesAsync.when(
        data: (nodes) {
          final node = nodes.where((n) => n.id == nodeId).firstOrNull;
          if (node == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Node not found or has been deleted.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go(AppRoute.calendar.path),
                    child: const Text('Go to Calendar'),
                  ),
                ],
              ),
            );
          }

          // Calculate related/backlink nodes
          final relatedNodes = nodes.where((n) {
            return n.id != node.id &&
                (node.relatedNodeIds.contains(n.id) ||
                    n.relatedNodeIds.contains(node.id));
          }).toList();

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Layout: Grid-like split for large screens, linear for small screens
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 700;
                        final leftPanel = _buildLeftPanel(context, ref, node);
                        final rightPanel = _buildRightPanel(
                          context,
                          ref,
                          node,
                          relatedNodes,
                        );

                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: leftPanel),
                              const SizedBox(width: 24),
                              Expanded(flex: 5, child: rightPanel),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftPanel,
                              const SizedBox(height: 24),
                              rightPanel,
                            ],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildLeftPanel(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final icon = nodeIcon(node.type);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category/Header Badge Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  avatar: Icon(icon, color: color, size: 16),
                  label: Text(
                    node.type.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: color.withValues(alpha: 0.1),
                  side: BorderSide(color: color.withValues(alpha: 0.2)),
                ),
                if (node.isPinned)
                  Icon(
                    Icons.push_pin,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              node.title.isEmpty ? 'Untitled ${node.type.name}' : node.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Metadata chips (Status, Priority, Project, Area, Date)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (node.status != NodeStatus.open ||
                    node.type == NodeType.task)
                  _buildMetaChip(
                    context,
                    Icons.lens,
                    node.status.label,
                    node.status == NodeStatus.done
                        ? Colors.green
                        : (node.status == NodeStatus.doing
                              ? Colors.blue
                              : Colors.orange),
                  ),
                if (node.priority != NodePriority.none)
                  _buildMetaChip(
                    context,
                    Icons.priority_high,
                    node.priority.label,
                    node.priority == NodePriority.high
                        ? Colors.red
                        : (node.priority == NodePriority.medium
                              ? Colors.orange
                              : Colors.grey),
                  ),
                if (node.project.isNotEmpty)
                  _buildMetaChip(
                    context,
                    Icons.folder_outlined,
                    'Proj: ${node.project}',
                    theme.colorScheme.primary,
                  ),
                if (node.area.isNotEmpty)
                  _buildMetaChip(
                    context,
                    Icons.category_outlined,
                    'Area: ${node.area}',
                    theme.colorScheme.secondary,
                  ),
                if (node.dueDate != null)
                  _buildMetaChip(
                    context,
                    Icons.event_outlined,
                    'Due: ${DateFormat('yyyy-MM-dd').format(node.dueDate!)}',
                    node.dueDate!.isBefore(DateTime.now().dateOnly)
                        ? Colors.red
                        : Colors.green,
                  ),
              ],
            ),
            const Divider(height: 32),
            // Body / Description
            Text('Description', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                node.body.isEmpty ? 'No description provided.' : node.body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: node.body.isEmpty ? theme.hintColor : null,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Created/Updated Dates
            Text(
              'Created: ${DateFormat('yyyy-MM-dd HH:mm').format(node.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            Text(
              'Updated: ${DateFormat('yyyy-MM-dd HH:mm').format(node.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit fields directly in the workspace →',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    IconButton.filledTonal(
                      tooltip: node.isPinned ? 'Unpin' : 'Pin',
                      icon: Icon(
                        node.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                      ),
                      onPressed: () => _togglePin(ref, node),
                    ),
                    IconButton.filledTonal(
                      tooltip: node.isArchived ? 'Unarchive' : 'Archive',
                      icon: Icon(
                        node.isArchived
                            ? Icons.unarchive
                            : Icons.archive_outlined,
                      ),
                      onPressed: () => _toggleArchive(ref, node),
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, ref, node),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
    List<MindmapNode> relatedNodes,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InlineNodePageEditor(node: node),
        const SizedBox(height: 16),
        // Type-Specific Feature Container
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(nodeIcon(node.type), color: nodeColor(node.type)),
                        const SizedBox(width: 8),
                        Text(
                          '${node.type.label} workspace',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    if (node.progress > 0)
                      Text(
                        '${(node.progress * 100).round()}% Completed',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
                if (node.progress > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: node.progress,
                      minHeight: 8,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
                const Divider(height: 32),
                _buildTypeSpecificDashboard(context, ref, node),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Related / Connected Nodes
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.device_hub,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text('Connected Nodes', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                if (relatedNodes.isEmpty)
                  Text(
                    'No other nodes are linked to this node.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.8,
                        ),
                    itemCount: relatedNodes.length,
                    itemBuilder: (context, index) {
                      final rel = relatedNodes[index];
                      final col = nodeColor(rel.type);
                      return InkWell(
                        onTap: () {
                          // Navigate to related node detail
                          context.go(
                            '/calendar/${dayKey(rel.day)}/node/${rel.id}',
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: 0.6),
                            ),
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  nodeIcon(rel.type),
                                  color: col,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      rel.title.isEmpty
                                          ? 'Untitled ${rel.type.name}'
                                          : rel.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      dayKey(rel.day),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.hintColor),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: theme.hintColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSpecificDashboard(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    switch (node.type) {
      case NodeType.task:
        return _EditableTaskWorkspace(node: node);
      case NodeType.kanban:
        return _EditableKanbanWorkspace(node: node);
      case NodeType.plan:
        return _EditablePlanWorkspace(node: node);
      case NodeType.goal:
        return _EditableGoalWorkspace(node: node);
      case NodeType.habit:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['target', 'recurrence', 'completions'],
        );
      case NodeType.journal:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['mood', 'energy', 'prompt', 'gratitude'],
        );
      case NodeType.note:
        return _EditableFieldWorkspace(node: node, fields: const ['source']);
      case NodeType.link:
        return _EditableFieldWorkspace(node: node, fields: const ['url']);
      case NodeType.event:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['location', 'participants', 'agenda', 'actions'],
        );
      case NodeType.decision:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['options', 'selectedOption', 'reason'],
        );
      case NodeType.resource:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['source', 'summary', 'keyPoints'],
        );
      case NodeType.idea:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['spark', 'whyItMatters', 'nextExperiment'],
        );
      case NodeType.question:
        return _EditableTaskWorkspace(node: node);
      case NodeType.contact:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['role', 'company', 'email', 'phone'],
        );
      case NodeType.metric:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['value', 'unit', 'trend', 'target'],
        );
      case NodeType.expense:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['amount', 'category', 'merchant', 'payment'],
        );
      case NodeType.bookmark:
        return _EditableFieldWorkspace(node: node, fields: const ['url']);
      case NodeType.routine:
        return _EditableTaskWorkspace(node: node);
      case NodeType.empty:
        return _EditableFieldWorkspace(
          node: node,
          fields: const ['placeholder'],
        );
      default:
        return _EditableFieldWorkspace(
          node: node,
          fields: const [],
        );
    }
  }

  // TASK DASHBOARD
  // ignore: unused_element
  Widget _buildTaskDashboard(WidgetRef ref, MindmapNode node) {
    if (node.checklist.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'This task has no checklist items. Edit the node to add some!',
        ),
      );
    }

    return Column(
      children: node.checklist.map((item) {
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            item.title,
            style: TextStyle(
              decoration: item.isDone ? TextDecoration.lineThrough : null,
              color: item.isDone ? Colors.grey : null,
            ),
          ),
          value: item.isDone,
          onChanged: (val) {
            if (val != null) {
              _toggleChecklistItem(ref, node, item.id, val);
            }
          },
        );
      }).toList(),
    );
  }

  // KANBAN DASHBOARD
  // ignore: unused_element
  Widget _buildKanbanDashboard(WidgetRef ref, MindmapNode node) {
    final board = KanbanBoard.fromNodeData(node.data);

    Widget columnFor(KanbanColumn col, bool isWide) {
      final content = Container(
        margin: EdgeInsets.only(
          right: isWide && col != KanbanColumn.values.last ? 12 : 0,
          bottom: isWide ? 0 : 12,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  col.label.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${board.cardsFor(col).length}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (board.cardsFor(col).isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No cards here',
                    style: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...board.cardsFor(col).map((card) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(child: Text(card.title)),
                        if (col.next != null)
                          IconButton(
                            tooltip: 'Move to ${col.next!.label}',
                            icon: const Icon(Icons.arrow_forward_outlined),
                            onPressed: () {
                              _moveKanbanCard(ref, node, board, card.id);
                            },
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      );
      return isWide ? Expanded(child: content) : content;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final columns = [
          for (final col in KanbanColumn.values) columnFor(col, isWide),
        ];
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columns,
              )
            : Column(children: columns);
      },
    );
  }

  // PLAN DASHBOARD
  // ignore: unused_element
  Widget _buildPlanDashboard(WidgetRef ref, MindmapNode node) {
    final steps = planSteps(node);
    if (steps.isEmpty) {
      return const Text('This plan has no steps. Edit the node to add some!');
    }

    final completed = completedPlanSteps(node);
    return Column(
      children: steps.map((step) {
        final isDone = completed.contains(step);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            step,
            style: TextStyle(
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone ? Colors.grey : null,
            ),
          ),
          value: isDone,
          onChanged: (val) {
            if (val != null) {
              _togglePlanStepItem(ref, node, step, val);
            }
          },
        );
      }).toList(),
    );
  }

  // GOAL DASHBOARD
  // ignore: unused_element
  Widget _buildGoalDashboard(WidgetRef ref, MindmapNode node) {
    final milestones = goalMilestones(node);
    if (milestones.isEmpty) {
      return const Text(
        'This goal has no milestones. Edit the node to add some!',
      );
    }

    final completed = completedGoalMilestones(node);
    return Column(
      children: milestones.map((milestone) {
        final isDone = completed.contains(milestone);
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            milestone,
            style: TextStyle(
              decoration: isDone ? TextDecoration.lineThrough : null,
              color: isDone ? Colors.grey : null,
            ),
          ),
          value: isDone,
          onChanged: (val) {
            if (val != null) {
              _toggleGoalMilestoneItem(ref, node, milestone, val);
            }
          },
        );
      }).toList(),
    );
  }

  // HABIT DASHBOARD
  // ignore: unused_element
  Widget _buildHabitDashboard(
    BuildContext context,
    WidgetRef ref,
    MindmapNode node,
  ) {
    final completions = habitCompletionKeys(node);
    final currentStreak = calculateCurrentStreak(node);
    final maxStreak = calculateMaxStreak(node);
    final theme = Theme.of(context);

    // We render the past 14 days completion tracker
    final List<DateTime> pastDays = List.generate(14, (index) {
      return DateTime.now().dateOnly.subtract(Duration(days: 13 - index));
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Streak Tracker',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (currentStreak > 0) ...[
                  Text(
                    '🔥 $currentStreak day streak',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(max: $maxStreak)',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  '${completions.length} total completions',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: pastDays.map((day) {
            final isDone = completions.contains(dayKey(day));
            final isToday = day.isSameDay(DateTime.now());

            return InkWell(
              onTap: () => _toggleHabitDay(ref, node, day, !isDone),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isDone
                      ? Colors.green.withValues(alpha: 0.15)
                      : (isToday
                            ? Colors.blue.withValues(alpha: 0.05)
                            : Colors.transparent),
                  border: Border.all(
                    color: isDone
                        ? Colors.green
                        : (isToday
                              ? Colors.blue
                              : Colors.grey.withValues(alpha: 0.3)),
                    width: isToday ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('E').format(day).substring(0, 2),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.green
                            : (isToday ? Colors.blue : Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? Colors.green
                            : (isToday ? Colors.blue : null),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          '* Tap any day above to toggle completion state for that day.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: Colors.grey,
          ),
        ),
        const Divider(height: 32),
        _HabitHeatmap(node: node),
      ],
    );
  }

  // JOURNAL DASHBOARD
  // ignore: unused_element
  Widget _buildJournalDashboard(WidgetRef ref, MindmapNode node) {
    final theme = Theme.of(ref.context);
    final journal = node.data['journal'] as Map?;
    if (journal == null) {
      return const Text('This journal entry has no details yet.');
    }

    final mood = journal['mood'] as int?;
    final energy = journal['energy'] as int?;
    final prompt = journal['prompt'] as String?;
    final gratitudes = (journal['gratitude'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mood != null || energy != null) ...[
          Row(
            children: [
              if (mood != null)
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.wb_sunny_outlined,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text('Mood', style: theme.textTheme.labelSmall),
                          Text(
                            '$mood/10',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (mood != null && energy != null) const SizedBox(width: 8),
              if (energy != null)
                Expanded(
                  child: Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.bolt,
                            color: Colors.yellow,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text('Energy', style: theme.textTheme.labelSmall),
                          Text(
                            '$energy/10',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (prompt != null && prompt.trim().isNotEmpty) ...[
          Text('Daily Reflection Prompt', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(prompt, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 16),
        ],
        if (gratitudes.isNotEmpty) ...[
          Text('Gratitude List', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          ...gratitudes.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 14,
                    color: Colors.red.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(g)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildEventDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    final details = <_DashboardDetail>[
      _DashboardDetail('Agenda', body['agenda'] ?? _firstBodyLine(node)),
      _DashboardDetail(
        'Location',
        body['location'] ?? _dataValue(node, 'location'),
      ),
      _DashboardDetail('Reminder', _dataValue(node, 'remindAt')),
      _DashboardDetail('Participants', _dataValue(node, 'participants')),
    ];
    return _buildStructuredDashboard(context, node, details, 'Event plan');
  }

  // ignore: unused_element
  Widget _buildDecisionDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    final details = <_DashboardDetail>[
      _DashboardDetail(
        'Decision',
        _dataValue(node, 'selectedOption').isEmpty
            ? body['decision']
            : _dataValue(node, 'selectedOption'),
      ),
      _DashboardDetail(
        'Rationale',
        _dataValue(node, 'reason').isEmpty
            ? body['rationale']
            : _dataValue(node, 'reason'),
      ),
      _DashboardDetail(
        'Options',
        _dataValue(node, 'options').isEmpty
            ? body['options']
            : _dataValue(node, 'options'),
      ),
    ];
    return _buildStructuredDashboard(context, node, details, 'Decision log');
  }

  // ignore: unused_element
  Widget _buildResourceDashboard(BuildContext context, MindmapNode node) {
    final source = _noteSource(node);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Source', source),
      _DashboardDetail('Summary', _firstBodyLine(node)),
    ], 'Reusable reference');
  }

  // ignore: unused_element
  Widget _buildIdeaDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Spark', body['spark'] ?? _firstBodyLine(node)),
      _DashboardDetail('Why it matters', body['why it matters']),
      _DashboardDetail('Next experiment', body['next experiment']),
    ], 'Idea incubator');
  }

  // ignore: unused_element
  Widget _buildQuestionDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Question', body['question'] ?? _firstBodyLine(node)),
      _DashboardDetail('Context', body['context']),
      _DashboardDetail('Possible answers', body['possible answers']),
      _DashboardDetail(
        'Follow-up',
        node.checklist.map((e) => e.title).join('\n'),
      ),
    ], 'Open loop');
  }

  // ignore: unused_element
  Widget _buildContactDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Name', body['name'] ?? node.title),
      _DashboardDetail('Role', _dataOrBody(node, body, 'role')),
      _DashboardDetail('Company', _dataOrBody(node, body, 'company')),
      _DashboardDetail('Email', _dataOrBody(node, body, 'email')),
      _DashboardDetail('Phone', _dataOrBody(node, body, 'phone')),
      _DashboardDetail('Notes', body['notes']),
    ], 'Relationship card');
  }

  // ignore: unused_element
  Widget _buildMetricDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Value', _dataOrBody(node, body, 'value')),
      _DashboardDetail('Unit', _dataOrBody(node, body, 'unit')),
      _DashboardDetail('Trend', _dataOrBody(node, body, 'trend')),
      _DashboardDetail('Target', _dataOrBody(node, body, 'target')),
      _DashboardDetail(
        'Progress',
        node.progress > 0 ? '${(node.progress * 100).round()}%' : '',
      ),
    ], 'Measurement');
  }

  // ignore: unused_element
  Widget _buildExpenseDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Amount', _dataOrBody(node, body, 'amount')),
      _DashboardDetail('Category', _dataOrBody(node, body, 'category')),
      _DashboardDetail('Merchant', _dataOrBody(node, body, 'merchant')),
      _DashboardDetail('Payment', _dataOrBody(node, body, 'payment')),
      _DashboardDetail('Notes', body['notes']),
    ], 'Spending note');
  }

  // ignore: unused_element
  Widget _buildBookmarkDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    final url = _dataOrBody(node, body, 'url').isEmpty
        ? _linkUrl(node)
        : _dataOrBody(node, body, 'url');
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('URL', url),
      _DashboardDetail('Why saved', body['why saved']),
    ], 'Saved link');
  }

  // ignore: unused_element
  Widget _buildRoutineDashboard(BuildContext context, MindmapNode node) {
    final body = _bodyFields(node.body);
    final steps = node.checklist.isEmpty
        ? body['steps']
        : node.checklist.map((e) => e.title).join('\n');
    return _buildStructuredDashboard(context, node, [
      _DashboardDetail('Trigger', body['trigger']),
      _DashboardDetail('Steps', steps),
      _DashboardDetail(
        'Progress',
        node.checklist.isEmpty
            ? ''
            : '${node.completedChecklistCount}/${node.checklist.length}',
      ),
    ], 'Operating routine');
  }

  Widget _buildStructuredDashboard(
    BuildContext context,
    MindmapNode node,
    List<_DashboardDetail> details,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    final color = nodeColor(node.type);
    final visible = details
        .where((detail) => detail.value.trim().isNotEmpty)
        .toList();
    if (visible.isEmpty) {
      return Text(
        'No structured ${node.type.label.toLowerCase()} details yet. Use Edit to add them.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(nodeIcon(node.type), color: color),
            const SizedBox(width: 8),
            Text(subtitle, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final detail in visible)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    border: Border.all(color: color.withValues(alpha: 0.28)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(detail.value.trim()),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Tip: Edit this node to refine structured fields.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Map<String, String> _bodyFields(String body) {
    final fields = <String, String>{};
    final lines = body.split('\n');
    String? current;
    final buffer = StringBuffer();
    void flush() {
      if (current == null) return;
      fields[current] = buffer.toString().trim();
      buffer.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('## ')) {
        flush();
        current = line.substring(3).trim().toLowerCase();
        continue;
      }
      final colon = line.indexOf(':');
      if (colon > 0 && line.length <= 120) {
        flush();
        current = line.substring(0, colon).trim().toLowerCase();
        buffer.write(line.substring(colon + 1).trim());
        continue;
      }
      if (current != null && line.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line.replaceFirst(RegExp(r'^-\s*'), ''));
      }
    }
    flush();
    return fields;
  }

  String _firstBodyLine(MindmapNode node) {
    return node.body
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('##'))
            .map((line) => line.replaceFirst(RegExp(r'^-\s*'), ''))
            .firstOrNull ??
        '';
  }

  String _dataValue(MindmapNode node, String key) =>
      node.data[key]?.toString() ?? '';

  String _dataOrBody(MindmapNode node, Map<String, String> body, String key) {
    final value = _dataValue(node, key).trim();
    return value.isEmpty ? body[key] ?? '' : value;
  }

  String _noteSource(MindmapNode node) {
    final direct = node.data['source']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;
    final note = node.data['note'];
    return note is Map ? note['source']?.toString() ?? '' : '';
  }

  String _linkUrl(MindmapNode node) {
    final direct = node.data['url']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;
    final link = node.data['link'];
    return link is Map ? link['url']?.toString() ?? '' : '';
  }

  // NOTE DASHBOARD
  // ignore: unused_element
  Widget _buildNoteDashboard(BuildContext context, MindmapNode node) {
    final noteData = node.data['note'] as Map?;
    final source = noteData?['source'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source.isNotEmpty) ...[
          const Text(
            'Note Source:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: source));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Source link copied to clipboard'),
                ),
              );
            },
            child: Text(
              source,
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Notes are formatted in simple text block. Use Edit button to add or change details.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  // LINK DASHBOARD
  // ignore: unused_element
  Widget _buildLinkDashboard(BuildContext context, MindmapNode node) {
    final linkData = node.data['link'] as Map?;
    final url = linkData?['url'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url.isEmpty)
          const Text('No URL link has been configured.')
        else ...[
          const Text('URL Link', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Link',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied URL link to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // STATE HELPERS
  void _toggleChecklistItem(
    WidgetRef ref,
    MindmapNode node,
    String itemId,
    bool isDone,
  ) async {
    final updatedChecklist = node.checklist.map((item) {
      return item.id == itemId ? item.copyWith(isDone: isDone) : item;
    }).toList();

    final doneCount = updatedChecklist.where((item) => item.isDone).length;
    final progress = updatedChecklist.isEmpty
        ? 0.0
        : doneCount / updatedChecklist.length;
    final allDone =
        doneCount == updatedChecklist.length && updatedChecklist.isNotEmpty;

    final updatedNode = node.copyWith(
      checklist: updatedChecklist,
      progress: progress,
      isDone: allDone,
      status: allDone
          ? NodeStatus.done
          : (progress > 0 ? NodeStatus.doing : NodeStatus.open),
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _moveKanbanCard(
    WidgetRef ref,
    MindmapNode node,
    KanbanBoard board,
    String cardId,
  ) async {
    final updatedBoard = board.moveCardToNextColumn(cardId);
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(
      node.copyWith(
        data: {...node.data, 'kanban': updatedBoard.toJson()},
        updatedAt: DateTime.now(),
      ),
    );
    invalidateMindmapState(ref, day: node.day);
  }

  void _togglePlanStepItem(
    WidgetRef ref,
    MindmapNode node,
    String step,
    bool isDone,
  ) async {
    final completed = completedPlanSteps(node).toList();
    if (isDone) {
      if (!completed.contains(step)) completed.add(step);
    } else {
      completed.remove(step);
    }
    completed.sort();

    final steps = planSteps(node);
    final completedCount = completed.length;
    final progress = steps.isEmpty ? 0.0 : completedCount / steps.length;
    final isComplete = completedCount == steps.length && steps.isNotEmpty;

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'plan': {
          ...(node.data['plan'] as Map? ?? {}),
          'steps': steps,
          'completedSteps': completed,
        },
      },
      progress: progress,
      status: isComplete
          ? NodeStatus.done
          : (progress > 0 ? NodeStatus.doing : NodeStatus.open),
      isDone: isComplete,
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleGoalMilestoneItem(
    WidgetRef ref,
    MindmapNode node,
    String milestone,
    bool isDone,
  ) async {
    final completed = completedGoalMilestones(node).toList();
    if (isDone) {
      if (!completed.contains(milestone)) completed.add(milestone);
    } else {
      completed.remove(milestone);
    }
    completed.sort();

    final milestones = goalMilestones(node);
    final completedCount = completed.length;
    final progress = milestones.isEmpty
        ? 0.0
        : completedCount / milestones.length;

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'goal': {
          ...(node.data['goal'] as Map? ?? {}),
          'milestones': milestones,
          'completedMilestones': completed,
        },
      },
      progress: progress,
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleHabitDay(
    WidgetRef ref,
    MindmapNode node,
    DateTime day,
    bool isDone,
  ) async {
    final keys = habitCompletionKeys(node).toList();
    final dayStr = dayKey(day.dateOnly);
    if (isDone) {
      if (!keys.contains(dayStr)) keys.add(dayStr);
    } else {
      keys.remove(dayStr);
    }
    keys.sort();

    final updatedNode = node.copyWith(
      data: {
        ...node.data,
        'habit': {...(node.data['habit'] as Map? ?? {}), 'completions': keys},
      },
      updatedAt: DateTime.now(),
    );

    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _togglePin(WidgetRef ref, MindmapNode node) async {
    final updatedNode = node.copyWith(
      isPinned: !node.isPinned,
      updatedAt: DateTime.now(),
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _toggleArchive(WidgetRef ref, MindmapNode node) async {
    final updatedNode = node.copyWith(
      isArchived: !node.isArchived,
      updatedAt: DateTime.now(),
    );
    final repository = ref.read(mindmapRepositoryProvider);
    await repository.saveNode(updatedNode);
    invalidateMindmapState(ref, day: node.day);
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, MindmapNode node) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Node'),
        content: Text(
          'Are you sure you want to delete "${node.title.isEmpty ? 'Untitled' : node.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final repository = ref.read(mindmapRepositoryProvider);
              await repository.deleteNode(node.id);
              invalidateMindmapState(ref, day: node.day);
              if (context.mounted) {
                Navigator.pop(context); // Close dialog
                goToDay(context, node.day); // Redirect to day page
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _DashboardDetail {
  const _DashboardDetail(this.label, String? value) : value = value ?? '';

  final String label;
  final String value;
}

class _HabitHeatmap extends StatelessWidget {
  const _HabitHeatmap({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completions = habitCompletionKeys(node);
    final today = DateTime.now().dateOnly;
    final offsetDays = today.weekday % 7;
    final startDate = today.subtract(Duration(days: 52 * 7 + offsetDays));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Completions Heatmap',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(53, (weekIndex) {
                  return Column(
                    children: List.generate(7, (dayIndex) {
                      final day = startDate.add(
                        Duration(days: weekIndex * 7 + dayIndex),
                      );
                      final key = dayKey(day);
                      final isDone = completions.contains(key);
                      final isFuture = day.isAfter(today);
                      final isToday = day.isSameDay(today);

                      Color cellColor;
                      if (isFuture) {
                        cellColor = theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.1);
                      } else if (isDone) {
                        cellColor = nodeColor(NodeType.habit);
                      } else if (isToday) {
                        cellColor = nodeColor(NodeType.habit).withValues(alpha: 0.15);
                      } else {
                        cellColor = theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4);
                      }

                      BorderSide borderSide;
                      if (isToday) {
                        borderSide = BorderSide(
                          color: nodeColor(NodeType.habit),
                          width: 1.5,
                        );
                      } else {
                        borderSide = BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.25,
                          ),
                          width: 0.75,
                        );
                      }

                      final formattedDate = DateFormat(
                        'EEEE, MMM d, yyyy',
                      ).format(day);
                      final statusText = isDone
                          ? 'Completed'
                          : (isFuture ? 'Future' : 'Not completed');

                      return Tooltip(
                        message: '$formattedDate: $statusText',
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(2.0),
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.fromBorderSide(borderSide),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
