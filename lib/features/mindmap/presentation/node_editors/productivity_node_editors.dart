import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sticky_colors.dart';
import '../../../../core/theme/node_visuals.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/goal_progress.dart';
import '../../domain/habit_completion.dart';
import '../../domain/kanban_board.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_presentation.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/plan_progress.dart';
import '../../domain/task_checklist_progress.dart';

import '../widgets/sticky_note_card_widget.dart';
import 'checklist_node_editor.dart';
import 'kanban_node_editor.dart';
import 'note_node_editor.dart';
import 'plan_node_editor.dart';
import 'timer_node_editor.dart';

typedef NodeTextDraftCallback = void Function(String value);
typedef NodePayloadDraftCallback = void Function(Object value);
typedef NodeDraftCallback = void Function(MindmapNode value);
typedef NodeAsyncPayloadAction = Future<void> Function(Object value);
typedef NodeAsyncDraftAction = Future<void> Function(MindmapNode value);
typedef NodeActionErrorCallback =
    void Function(Object error, StackTrace stackTrace);
typedef TaskAttachmentAddCallback = Future<TaskAttachmentReference?> Function();
typedef TaskAttachmentActionCallback =
    Future<void> Function(TaskAttachmentReference attachment);
typedef ResourceAssetAddCallback = Future<ResourceAsset?> Function();
typedef ResourceAssetOpenCallback = Future<void> Function(ResourceAsset asset);

abstract interface class NodeDraftTimer {
  void cancel();
}

typedef NodeDraftSchedule =
    NodeDraftTimer Function(Duration duration, void Function() callback);

final class NodeRenderContext {
  const NodeRenderContext({
    required this.node,
    required this.effectivePreset,
    this.typedPayload,
    this.attachmentBytes,
    this.attachmentLoading = false,
    this.attachmentError,
    this.onMediaAction,
  });

  final MindmapNode node;
  final NodeSizePreset effectivePreset;
  final Object? typedPayload;
  final Uint8List? attachmentBytes;
  final bool attachmentLoading;
  final String? attachmentError;
  final NodePayloadDraftCallback? onMediaAction;
}

final class NodeEditContext {
  const NodeEditContext({
    required this.node,
    required this.typedDraft,
    required this.effectivePreset,
    required this.validationErrors,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onDraftChanged,
    required this.onNodeDraftChanged,
    this.cachedPayload,
    this.attachmentBytes,
    this.attachmentLoading = false,
    this.attachmentError,
    this.onMediaAction,
    this.onTaskChecklistAction,
    this.onTaskAttachmentAdd,
    this.onTaskAttachmentOpen,
    this.onTaskAttachmentRemove,
    this.onResourceAssetAdd,
    this.onResourceAssetOpen,
    this.resourceFolderSuggestions = const <List<String>>[],
    this.onKanbanAttachmentAdd,
    this.onKanbanAttachmentOpen,
    this.onKanbanAttachmentRemove,
    this.onPlanAttachmentAdd,
    this.onPlanAttachmentOpen,
    this.onPlanAttachmentRemove,
    this.onKanbanAction,
    this.onPlanAction,
    this.onGoalAction,
    this.onHabitAction,
    this.onTimerAction,
    this.onKnowledgeAction,
    this.onItineraryAction,
    this.onEmptyAction,
    this.onActionError,
    this.videoPlaybackScheduler,
    this.videoPlaybackDebounce = const Duration(milliseconds: 750),
  });

  final MindmapNode node;
  final Object typedDraft;
  final Object? cachedPayload;
  final NodeSizePreset effectivePreset;
  final List<String> validationErrors;
  final NodeTextDraftCallback onTitleChanged;
  final NodeTextDraftCallback onBodyChanged;
  final NodePayloadDraftCallback onDraftChanged;
  final NodeDraftCallback onNodeDraftChanged;
  final Uint8List? attachmentBytes;
  final bool attachmentLoading;
  final String? attachmentError;
  final NodeAsyncPayloadAction? onMediaAction;
  final NodeAsyncDraftAction? onTaskChecklistAction;
  final TaskAttachmentAddCallback? onTaskAttachmentAdd;
  final TaskAttachmentActionCallback? onTaskAttachmentOpen;
  final TaskAttachmentActionCallback? onTaskAttachmentRemove;
  final ResourceAssetAddCallback? onResourceAssetAdd;
  final ResourceAssetOpenCallback? onResourceAssetOpen;
  final List<List<String>> resourceFolderSuggestions;
  final KanbanAttachmentAddCallback? onKanbanAttachmentAdd;
  final KanbanAttachmentActionCallback? onKanbanAttachmentOpen;
  final KanbanAttachmentActionCallback? onKanbanAttachmentRemove;
  final PlanAttachmentAddCallback? onPlanAttachmentAdd;
  final PlanAttachmentActionCallback? onPlanAttachmentOpen;
  final PlanAttachmentActionCallback? onPlanAttachmentRemove;
  final NodeAsyncPayloadAction? onKanbanAction;
  final NodeAsyncDraftAction? onPlanAction;
  final NodeAsyncDraftAction? onGoalAction;
  final NodeAsyncPayloadAction? onHabitAction;
  final NodeAsyncPayloadAction? onTimerAction;
  final NodeAsyncPayloadAction? onKnowledgeAction;
  final NodeAsyncPayloadAction? onItineraryAction;
  final NodeAsyncPayloadAction? onEmptyAction;
  final NodeActionErrorCallback? onActionError;
  final NodeDraftSchedule? videoPlaybackScheduler;
  final Duration videoPlaybackDebounce;
}

Widget buildProductivityNodeContent(NodeRenderContext context) {
  if (!_isProductivity(context.node.type)) return _FallbackContent(context);
  return _ProductivityContent(context);
}

Widget buildProductivityNodeInlineEditor(NodeEditContext context) {
  if (!_isProductivity(context.node.type)) return _FallbackEditor(context);
  return _ProductivityEditor(context);
}

bool _isProductivity(NodeType type) => switch (type) {
  NodeType.task ||
  NodeType.kanban ||
  NodeType.plan ||
  NodeType.note ||
  NodeType.habit ||
  NodeType.goal ||
  NodeType.routine ||
  NodeType.checklist ||
  NodeType.timer => true,
  _ => false,
};

final class _ProductivityContent extends StatelessWidget {
  const _ProductivityContent(this.context);

  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final node = context.node;
    final preset = context.effectivePreset;
    final compact = preset == NodeSizePreset.compact;

    if (node.type == NodeType.note) {
      final colorName = node.data['stickyColor'] as String?;
      final colorOption = StickyColorOption.fromName(colorName);
      return StickyNoteCardWidget(
        title: node.title,
        body: node.body,
        colorOption: colorOption,
      );
    }

    return Container(
      key: ValueKey<String>('productivity-${node.type.name}-${preset.name}'),
      padding: EdgeInsets.all(compact ? 10 : 14),
      color: Theme.of(buildContext).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(node: node, compact: compact),
          if (compact && node.type == NodeType.routine) ...[
            const SizedBox(height: 4),
            _RoutineView(payload: HabitRoutinePayload.fromNode(node)),
          ],
          if (!compact) ...[
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey<String>('productivity-${node.type.name}-details'),
                child: _TypeDetails(node: node, preset: preset),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({required this.node, required this.compact});

  final MindmapNode node;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        NodeVisuals.icon(node.type),
        size: compact ? 16 : 20,
        color: NodeVisuals.color(context, node.type),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          node.title,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: (compact
              ? Theme.of(context).textTheme.labelLarge
              : Theme.of(context).textTheme.titleMedium),
        ),
      ),
      if (node.isDone) const Icon(Icons.check, size: 16),
    ],
  );
}

final class _TypeDetails extends StatelessWidget {
  const _TypeDetails({required this.node, required this.preset});

  final MindmapNode node;
  final NodeSizePreset preset;

  bool get expanded =>
      preset == NodeSizePreset.large || preset == NodeSizePreset.wide;

  @override
  Widget build(BuildContext context) => switch (node.type) {
    NodeType.task || NodeType.checklist => _ChecklistView(
      payload: TaskChecklistPayload.fromNode(node),
      showAll: expanded,
    ),
    NodeType.kanban => _KanbanView(
      payload: KanbanPayload.fromNode(node),
      showAll: expanded,
    ),
    NodeType.plan => _ProgressList(
      items: PlanPayload.fromNode(node).steps,
      completed: PlanPayload.fromNode(node).completedSteps,
      showAll: expanded,
    ),
    NodeType.goal => _ProgressList(
      items: GoalPayload.fromNode(node).milestones,
      completed: GoalPayload.fromNode(node).completedMilestones,
      showAll: expanded,
    ),
    NodeType.habit => _HabitView(
      payload: HabitRoutinePayload.fromNode(node),
      showAll: expanded,
    ),
    NodeType.routine => _RoutineView(
      payload: HabitRoutinePayload.fromNode(node),
    ),
    NodeType.timer => _TimerView(payload: TimerPayload.fromNode(node)),
    NodeType.note => Text(
      node.body.isEmpty ? 'No note content' : node.body,
      maxLines: expanded ? 12 : 4,
      overflow: TextOverflow.ellipsis,
    ),
    _ => const SizedBox.shrink(),
  };
}

final class _ProductivityEditor extends StatelessWidget {
  const _ProductivityEditor(this.context);

  final NodeEditContext context;

  @override
  Widget build(BuildContext buildContext) {
    if (context.node.type == NodeType.task) {
      return _TaskInlineEditor(context: context);
    }
    if (context.node.type == NodeType.habit) {
      return _HabitInlineEditor(context: context);
    }
    if (context.node.type == NodeType.routine) {
      return _RoutineInlineEditor(context: context);
    }
    if (context.node.type == NodeType.goal) {
      return _GoalInlineEditor(context: context);
    }
    if (context.node.type == NodeType.checklist) {
      final payload = context.typedDraft is ChecklistPayload
          ? context.typedDraft as ChecklistPayload
          : ChecklistPayload.fromNode(context.node);
      return ChecklistNodeEditor(
        node: context.node,
        payload: payload,
        onTitleChanged: context.onTitleChanged,
        onBodyChanged: context.onBodyChanged,
        onPayloadChanged: context.onDraftChanged,
      );
    }
    if (context.node.type == NodeType.note) {
      final payload = context.typedDraft is NotePayload
          ? context.typedDraft as NotePayload
          : NotePayload.fromNode(context.node);
      return NoteNodeEditor(
        node: context.node,
        payload: payload,
        onTitleChanged: context.onTitleChanged,
        onBodyChanged: context.onBodyChanged,
        onPayloadChanged: context.onDraftChanged,
        onNodeChanged: context.onNodeDraftChanged,
        onAttachmentAdd: context.onTaskAttachmentAdd,
        onAttachmentOpen: context.onTaskAttachmentOpen,
        onAttachmentRemove: context.onTaskAttachmentRemove,
        validationErrors: context.validationErrors,
      );
    }
    if (context.node.type == NodeType.kanban) {
      final payload = context.typedDraft is KanbanPayload
          ? context.typedDraft as KanbanPayload
          : KanbanPayload.fromNode(context.node);
      return KanbanNodeEditor(
        node: context.node,
        payload: payload,
        onTitleChanged: context.onTitleChanged,
        onBodyChanged: context.onBodyChanged,
        onPayloadChanged: (value) {
          final callback = context.onKanbanAction;
          callback == null ? context.onDraftChanged(value) : callback(value);
        },
        onAttachmentAdd: context.onKanbanAttachmentAdd,
        onAttachmentOpen: context.onKanbanAttachmentOpen,
        onAttachmentRemove: context.onKanbanAttachmentRemove,
      );
    }
    if (context.node.type == NodeType.plan) {
      final payload = context.typedDraft is PlanPayload
          ? context.typedDraft as PlanPayload
          : PlanPayload.fromNode(context.node);
      return PlanNodeEditor(
        node: context.node,
        payload: payload,
        onTitleChanged: context.onTitleChanged,
        onBodyChanged: context.onBodyChanged,
        onPayloadChanged: context.onDraftChanged,
        onAttachmentAdd: context.onPlanAttachmentAdd,
        onAttachmentOpen: context.onPlanAttachmentOpen,
        onAttachmentRemove: context.onPlanAttachmentRemove,
      );
    }
    if (context.node.type == NodeType.timer) {
      final payload = context.typedDraft is TimerPayload
          ? context.typedDraft as TimerPayload
          : TimerPayload.fromNode(context.node);
      return TimerNodeEditor(
        node: context.node,
        payload: payload,
        onTitleChanged: context.onTitleChanged,
        onBodyChanged: context.onBodyChanged,
        onPayloadChanged: context.onDraftChanged,
      );
    }
    return Container(
      color: Theme.of(buildContext).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: ValueKey<String>(
                'productivity-${context.node.id}-title-field',
              ),
              initialValue: context.node.title,
              decoration: const InputDecoration(
                labelText: 'Title',
                isDense: true,
              ),
              onChanged: context.onTitleChanged,
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey<String>(
                'productivity-${context.node.id}-body-field',
              ),
              initialValue: context.node.body,
              decoration: const InputDecoration(
                labelText: 'Details',
                alignLabelWithHint: true,
                isDense: true,
              ),
              minLines: context.effectivePreset == NodeSizePreset.compact
                  ? 1
                  : 2,
              maxLines: context.effectivePreset == NodeSizePreset.wide ? 6 : 4,
              onChanged: context.onBodyChanged,
            ),
            const SizedBox(height: 12),
            _DraftActions(context),
            if (context.node.type == NodeType.habit ||
                context.node.type == NodeType.routine) ...[
              const SizedBox(height: 12),
              _HabitHeatmap(
                completionKeys: HabitRoutinePayload.fromNode(
                  context.node,
                ).completions.toSet(),
              ),
            ],
            for (final error in context.validationErrors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(buildContext).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _TaskInlineEditor extends StatefulWidget {
  const _TaskInlineEditor({required this.context});

  final NodeEditContext context;

  @override
  State<_TaskInlineEditor> createState() => _TaskInlineEditorState();
}

final class _TaskInlineEditorState extends State<_TaskInlineEditor> {
  NodeEditContext get edit => widget.context;

  TaskChecklistPayload get payload => edit.typedDraft is TaskChecklistPayload
      ? edit.typedDraft as TaskChecklistPayload
      : TaskChecklistPayload.fromNode(edit.node);

  Future<String?> _requestText({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (text) => Navigator.pop(dialogContext, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim();
  }

  void _updatePayload(TaskChecklistPayload next) => edit.onDraftChanged(next);

  Future<void> _addSubtask() async {
    final title = await _requestText(title: 'Add subtask', label: 'Subtask');
    if (title == null || title.isEmpty) return;
    _updatePayload(
      payload.copyWith(
        items: [
          ...payload.items,
          TaskChecklistItem(id: const Uuid().v4(), title: title),
        ],
      ),
    );
  }

  Future<void> _editSubtask(TaskChecklistItem item) async {
    final title = await _requestText(
      title: 'Edit subtask',
      label: 'Subtask',
      initialValue: item.title,
    );
    if (title == null || title.isEmpty || title == item.title) return;
    _updatePayload(
      payload.copyWith(
        items: [
          for (final current in payload.items)
            if (current.id == item.id)
              current.copyWith(title: title)
            else
              current,
        ],
      ),
    );
  }

  void _toggleSubtask(TaskChecklistItem item, bool value) {
    final items = [
      for (final current in payload.items)
        if (current.id == item.id) current.copyWith(isDone: value) else current,
    ];
    final completed = items.where((current) => current.isDone).length;
    final progress = items.isEmpty ? 0.0 : completed / items.length;
    edit.onNodeDraftChanged(
      payload
          .copyWith(items: items)
          .toNode(
            edit.node.copyWith(progress: progress, updatedAt: DateTime.now()),
          ),
    );
  }

  void _deleteSubtask(TaskChecklistItem item) => _updatePayload(
    payload.copyWith(
      items: [
        for (final current in payload.items)
          if (current.id != item.id)
            current.parentId == item.id
                ? current.copyWith(parentId: item.parentId)
                : current,
      ],
    ),
  );

  void _reorderSubtask(int oldIndex, int newIndex) => _updatePayload(
    payload.copyWith(
      items: moveTaskChecklistItem(payload.items, oldIndex, newIndex),
    ),
  );

  void _indentSubtask(TaskChecklistItem item) {
    final index = payload.items.indexWhere((value) => value.id == item.id);
    if (index <= 0) return;
    final parentId = payload.items[index - 1].id;
    final updated = setTaskChecklistParent(payload.items, item.id, parentId);
    if (updated == null || updated == item) return;
    _updatePayload(
      payload.copyWith(
        items: [
          for (final current in payload.items)
            current.id == item.id ? updated : current,
        ],
      ),
    );
  }

  void _outdentSubtask(TaskChecklistItem item) {
    final updated = setTaskChecklistParent(payload.items, item.id, null);
    if (updated == null || updated == item) return;
    _updatePayload(
      payload.copyWith(
        items: [
          for (final current in payload.items)
            current.id == item.id ? updated : current,
        ],
      ),
    );
  }

  Future<void> _pickDeadline() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: edit.node.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    edit.onNodeDraftChanged(
      edit.node.copyWith(dueDate: selected.dateOnly, updatedAt: DateTime.now()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: ValueKey<String>('task-inline-editor-${edit.node.id}'),
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: ValueKey<String>(
                    'productivity-${edit.node.id}-title-field',
                  ),
                  initialValue: edit.node.title,
                  decoration: const InputDecoration(
                    hintText: 'Task title',
                    prefixIcon: Icon(Icons.task_alt_rounded),
                    isDense: true,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                  onChanged: edit.onTitleChanged,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey<String>(
                    'productivity-${edit.node.id}-body-field',
                  ),
                  initialValue: edit.node.body,
                  decoration: const InputDecoration(
                    hintText: 'Add details…',
                    alignLabelWithHint: true,
                    isDense: true,
                  ),
                  minLines: 2,
                  maxLines: 4,
                  inputFormatters: [LengthLimitingTextInputFormatter(255)],
                  onChanged: edit.onBodyChanged,
                ),
                if (payload.items.any((item) => !item.isDone)) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final next = payload.items.firstWhere(
                        (item) => !item.isDone,
                      );
                      _toggleSubtask(next, true);
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      'Complete ${payload.items.firstWhere((item) => !item.isDone).title}',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _TaskSection(
                  title: 'Priority',
                  icon: Icons.flag_outlined,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final priority in NodePriority.values)
                        ChoiceChip(
                          label: Text(priority.label),
                          selected: edit.node.priority == priority,
                          onSelected: (_) => edit.onNodeDraftChanged(
                            edit.node.copyWith(
                              priority: priority,
                              updatedAt: DateTime.now(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _TaskSection(
                  title: 'Deadline',
                  icon: Icons.event_outlined,
                  trailing: edit.node.dueDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Clear deadline',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => edit.onNodeDraftChanged(
                            edit.node.copyWith(
                              clearDueDate: true,
                              updatedAt: DateTime.now(),
                            ),
                          ),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  child: OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      edit.node.dueDate == null
                          ? 'Set deadline'
                          : DateFormat(
                              'EEE, d MMM yyyy',
                            ).format(edit.node.dueDate!),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _TaskSection(
                  title: 'Subtasks',
                  icon: Icons.checklist_rounded,
                  trailing: IconButton(
                    key: const ValueKey<String>('task-add-subtask'),
                    tooltip: 'Add subtask',
                    visualDensity: VisualDensity.compact,
                    onPressed: _addSubtask,
                    icon: const Icon(Icons.add, size: 19),
                  ),
                  child: payload.items.isEmpty
                      ? const _TaskEmptyState(label: 'No subtasks yet')
                      : ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: payload.items.length,
                          onReorderItem: _reorderSubtask,
                          itemBuilder: (context, index) {
                            final item = payload.items[index];
                            return _TaskSubtaskTile(
                              key: ValueKey<String>('task-subtask-${item.id}'),
                              item: item,
                              depth: _taskChecklistDepth(item, payload.items),
                              index: index,
                              canIndent: index > 0,
                              canOutdent: item.parentId != null,
                              onChanged: (value) => _toggleSubtask(item, value),
                              onEdit: () => _editSubtask(item),
                              onDelete: () => _deleteSubtask(item),
                              onIndent: () => _indentSubtask(item),
                              onOutdent: () => _outdentSubtask(item),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 10),
                _TaskSection(
                  title: 'Attachments',
                  icon: Icons.attach_file_rounded,
                  trailing: IconButton(
                    key: const ValueKey<String>('task-add-attachment'),
                    tooltip: 'Add attachment',
                    visualDensity: VisualDensity.compact,
                    onPressed: edit.onTaskAttachmentAdd == null
                        ? null
                        : () async {
                            final attachment =
                                await edit.onTaskAttachmentAdd!();
                            if (attachment == null) return;
                            _updatePayload(
                              payload.copyWith(
                                attachments: [
                                  ...payload.attachments,
                                  attachment,
                                ],
                              ),
                            );
                          },
                    icon: const Icon(Icons.add, size: 19),
                  ),
                  child: payload.attachments.isEmpty
                      ? const _TaskEmptyState(label: 'No attachments')
                      : Column(
                          children: [
                            for (final attachment in payload.attachments)
                              Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(_fileIcon(attachment.mimeType)),
                                  title: Text(
                                    attachment.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    _fileSize(attachment.byteLength),
                                  ),
                                  onTap: edit.onTaskAttachmentOpen == null
                                      ? null
                                      : () => edit.onTaskAttachmentOpen!(
                                          attachment,
                                        ),
                                  trailing: IconButton(
                                    tooltip: 'Remove attachment',
                                    onPressed: () async {
                                      await edit.onTaskAttachmentRemove?.call(
                                        attachment,
                                      );
                                      _updatePayload(
                                        payload.copyWith(
                                          attachments: payload.attachments
                                              .where(
                                                (item) =>
                                                    item.id != attachment.id,
                                              )
                                              .toList(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                for (final error in edit.validationErrors)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          );
          if (constraints.hasBoundedHeight && constraints.maxHeight < 650) {
            return SingleChildScrollView(child: content);
          }
          return SingleChildScrollView(child: content);
        },
      ),
    );
  }
}

final class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 7),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

final class _TaskSubtaskTile extends StatelessWidget {
  const _TaskSubtaskTile({
    required this.item,
    required this.depth,
    required this.index,
    required this.canIndent,
    required this.canOutdent,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onIndent,
    required this.onOutdent,
    super.key,
  });

  final TaskChecklistItem item;
  final int depth;
  final int index;
  final bool canIndent;
  final bool canOutdent;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: depth * 20),
    child: Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_indicator, size: 18),
          ),
        ),
        Checkbox(
          value: item.isDone,
          visualDensity: VisualDensity.compact,
          onChanged: (value) => onChanged(value ?? false),
        ),
        Expanded(
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              decoration: item.isDone ? TextDecoration.lineThrough : null,
              color: item.isDone
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ),
        PopupMenuButton<_TaskSubtaskAction>(
          tooltip: 'Subtask actions',
          onSelected: (action) {
            switch (action) {
              case _TaskSubtaskAction.outdent:
                onOutdent();
              case _TaskSubtaskAction.indent:
                onIndent();
              case _TaskSubtaskAction.edit:
                onEdit();
              case _TaskSubtaskAction.delete:
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _TaskSubtaskAction.outdent,
              enabled: canOutdent,
              child: const Text('Outdent subtask'),
            ),
            PopupMenuItem(
              value: _TaskSubtaskAction.indent,
              enabled: canIndent,
              child: const Text('Indent subtask'),
            ),
            const PopupMenuItem(
              value: _TaskSubtaskAction.edit,
              child: Text('Edit subtask'),
            ),
            const PopupMenuItem(
              value: _TaskSubtaskAction.delete,
              child: Text('Delete subtask'),
            ),
          ],
        ),
      ],
    ),
  );
}

enum _TaskSubtaskAction { outdent, indent, edit, delete }

int _taskChecklistDepth(TaskChecklistItem item, List<TaskChecklistItem> items) {
  final byId = {for (final value in items) value.id: value};
  var parentId = item.parentId;
  var depth = 0;
  final visited = <String>{item.id};
  while (parentId != null && visited.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    depth++;
    parentId = parent.parentId;
  }
  return depth;
}

final class _TaskEmptyState extends StatelessWidget {
  const _TaskEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

IconData _fileIcon(String mimeType) {
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType.startsWith('video/')) return Icons.movie_outlined;
  if (mimeType.startsWith('audio/')) return Icons.audio_file_outlined;
  if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mimeType.startsWith('text/')) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

final class _HabitInlineEditor extends StatelessWidget {
  const _HabitInlineEditor({required this.context});

  final NodeEditContext context;

  HabitRoutinePayload get payload => context.typedDraft is HabitRoutinePayload
      ? context.typedDraft as HabitRoutinePayload
      : HabitRoutinePayload.fromNode(context.node);

  @override
  Widget build(BuildContext buildContext) {
    final completionKeys = payload.completions.toSet();
    final completed = completionKeys.contains(dayKey(context.node.day));
    final recentCount = List.generate(
      7,
      (index) => dayKey(context.node.day.subtract(Duration(days: index))),
    ).where(completionKeys.contains).length;

    return Container(
      color: Theme.of(buildContext).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey<String>('productivity-habit-title-field'),
              initialValue: context.node.title,
              decoration: const InputDecoration(
                labelText: 'Habit',
                prefixIcon: Icon(Icons.repeat_rounded),
                isDense: true,
              ),
              onChanged: context.onTitleChanged,
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey<String>('productivity-habit-body-field'),
              initialValue: context.node.body,
              decoration: const InputDecoration(
                labelText: 'Why this matters',
                alignLabelWithHint: true,
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: context.onBodyChanged,
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey<String>('productivity-habit-target-field'),
              initialValue: payload.target,
              decoration: const InputDecoration(
                labelText: 'Target',
                hintText: 'Example: 30 minutes',
                prefixIcon: Icon(Icons.flag_outlined),
                isDense: true,
              ),
              onChanged: (value) => context.onDraftChanged(
                HabitRoutinePayload(
                  target: value,
                  recurrence: payload.recurrence,
                  completions: payload.completions,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Repeat', style: Theme.of(buildContext).textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final recurrence in const [
                  ('daily', 'Daily'),
                  ('weekdays', 'Weekdays'),
                  ('weekly', 'Weekly'),
                  ('monthly', 'Monthly'),
                ])
                  ChoiceChip(
                    key: ValueKey<String>(
                      'productivity-habit-recurrence-${recurrence.$1}',
                    ),
                    label: Text(recurrence.$2),
                    selected: payload.recurrence == recurrence.$1,
                    onSelected: (_) => context.onDraftChanged(
                      HabitRoutinePayload(
                        target: payload.target,
                        recurrence: recurrence.$1,
                        completions: payload.completions,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey<String>('habit-toggle-today'),
                  onPressed: () async {
                    final draft = context.node.copyWith(
                      data: payload.toData(context.node.data),
                    );
                    final action = completed
                        ? removeHabitCompletion(draft, context.node.day)
                        : logHabitCompletion(draft, context.node.day);
                    final callback = context.onHabitAction;
                    callback == null
                        ? context.onNodeDraftChanged(action)
                        : await callback(action);
                  },
                  icon: Icon(
                    completed ? Icons.undo_rounded : Icons.check_rounded,
                    size: 18,
                  ),
                  label: Text(completed ? 'Undo today' : 'Complete today'),
                ),
                Chip(
                  avatar: const Icon(Icons.local_fire_department_outlined),
                  label: Text('$recentCount / 7 days'),
                ),
                Chip(label: Text('${completionKeys.length} total')),
              ],
            ),
            const SizedBox(height: 12),
            _HabitHeatmap(completionKeys: completionKeys),
            for (final error in context.validationErrors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(buildContext).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _GoalInlineEditor extends StatefulWidget {
  const _GoalInlineEditor({required this.context});

  final NodeEditContext context;

  @override
  State<_GoalInlineEditor> createState() => _GoalInlineEditorState();
}

final class _GoalInlineEditorState extends State<_GoalInlineEditor> {
  final TextEditingController _newMilestoneController = TextEditingController();

  NodeEditContext get edit => widget.context;
  GoalPayload get payload => edit.typedDraft is GoalPayload
      ? edit.typedDraft as GoalPayload
      : GoalPayload.fromNode(edit.node);

  @override
  void dispose() {
    _newMilestoneController.dispose();
    super.dispose();
  }

  void _emit(List<String> milestones, List<String> completed) {
    edit.onDraftChanged(
      GoalPayload(milestones: milestones, completedMilestones: completed),
    );
  }

  void _addMilestone() {
    final value = _newMilestoneController.text.trim();
    if (value.isEmpty) return;
    _emit([...payload.milestones, value], payload.completedMilestones);
    _newMilestoneController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completedKeys = payload.completedMilestones
        .map((item) => item.trim().toLowerCase())
        .toSet();
    final progress = payload.milestones.isEmpty
        ? 0.0
        : completedKeys.length / payload.milestones.length;

    return Container(
      key: const ValueKey<String>('productivity-goal-editor'),
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey<String>('productivity-goal-title-field'),
                  initialValue: edit.node.title,
                  decoration: const InputDecoration(
                    labelText: 'Goal',
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                    isDense: true,
                  ),
                  onChanged: edit.onTitleChanged,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  key: const ValueKey<String>('productivity-goal-body-field'),
                  initialValue: edit.node.body,
                  decoration: const InputDecoration(
                    labelText: 'Motivation and outcome',
                    prefixIcon: Icon(Icons.auto_awesome_outlined),
                    isDense: true,
                  ),
                  minLines: 1,
                  maxLines: 2,
                  onChanged: edit.onBodyChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${completedKeys.length}/${payload.milestones.length} milestones',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey<String>('goal-new-milestone-field'),
                  controller: _newMilestoneController,
                  decoration: const InputDecoration(
                    labelText: 'Add milestone',
                    hintText: 'Next measurable result',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addMilestone(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey<String>('goal-add-milestone'),
                tooltip: 'Add milestone',
                onPressed: _addMilestone,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (
                    var index = 0;
                    index < payload.milestones.length;
                    index++
                  )
                    SizedBox(
                      width: itemWidth,
                      child: Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          key: ValueKey<String>('goal-milestone-$index'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: TextFormField(
                            initialValue: payload.milestones[index],
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                            ),
                            maxLines: 1,
                            onChanged: (value) {
                              final next = [...payload.milestones];
                              final old = next[index];
                              next[index] = value;
                              final completed = [
                                for (final item in payload.completedMilestones)
                                  if (item.trim().toLowerCase() ==
                                      old.trim().toLowerCase())
                                    value
                                  else
                                    item,
                              ];
                              _emit(next, completed);
                            },
                          ),
                          secondary: IconButton(
                            tooltip: 'Delete milestone',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              final removed = payload.milestones[index];
                              _emit(
                                [...payload.milestones]..removeAt(index),
                                payload.completedMilestones
                                    .where(
                                      (item) =>
                                          item.trim().toLowerCase() !=
                                          removed.trim().toLowerCase(),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          value: completedKeys.contains(
                            payload.milestones[index].trim().toLowerCase(),
                          ),
                          onChanged: (checked) {
                            final milestone = payload.milestones[index];
                            final completed = [...payload.completedMilestones];
                            checked ?? false
                                ? completed.add(milestone)
                                : completed.removeWhere(
                                    (item) =>
                                        item.trim().toLowerCase() ==
                                        milestone.trim().toLowerCase(),
                                  );
                            _emit(payload.milestones, completed);
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (payload.milestones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final draft = edit.node.copyWith(
                  data: payload.toData(edit.node.data),
                );
                final next = nextGoalMilestone(draft);
                return FilledButton.tonalIcon(
                  onPressed: next == null
                      ? null
                      : () async {
                          final action = advanceGoalMilestone(draft);
                          final callback = edit.onGoalAction;
                          callback == null
                              ? edit.onNodeDraftChanged(action)
                              : await callback(action);
                        },
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(
                    next == null ? 'Goal complete' : 'Complete $next',
                  ),
                );
              },
            ),
          ],
          for (final error in edit.validationErrors)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}

final class _RoutineInlineEditor extends StatelessWidget {
  const _RoutineInlineEditor({required this.context});

  final NodeEditContext context;

  HabitRoutinePayload get payload => context.typedDraft is HabitRoutinePayload
      ? context.typedDraft as HabitRoutinePayload
      : HabitRoutinePayload.fromNode(context.node);

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final completionKeys = payload.completions.toSet();
    final activeDayKey = dayKey(context.node.day);
    final completed = completionKeys.contains(activeDayKey);
    final recentDays = List.generate(
      28,
      (index) => context.node.day.subtract(Duration(days: 27 - index)),
    );
    final recentCount = recentDays
        .where((day) => completionKeys.contains(dayKey(day)))
        .length;

    void update({
      String? target,
      String? recurrence,
      List<String>? completions,
    }) {
      context.onDraftChanged(
        HabitRoutinePayload(
          target: target ?? payload.target,
          recurrence: recurrence ?? payload.recurrence,
          completions: completions ?? payload.completions,
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('productivity-routine-editor'),
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey<String>(
                        'productivity-routine-title-field',
                      ),
                      initialValue: context.node.title,
                      decoration: const InputDecoration(
                        labelText: 'Routine',
                        prefixIcon: Icon(Icons.route_outlined),
                        isDense: true,
                      ),
                      onChanged: context.onTitleChanged,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      key: const ValueKey<String>(
                        'productivity-routine-body-field',
                      ),
                      initialValue: context.node.body,
                      decoration: const InputDecoration(
                        labelText: 'Trigger and steps',
                        hintText: 'After I wake up, prepare and start...',
                        alignLabelWithHint: true,
                        isDense: true,
                      ),
                      minLines: 3,
                      maxLines: 3,
                      onChanged: context.onBodyChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: const ValueKey<String>(
                        'productivity-routine-target-field',
                      ),
                      initialValue: payload.target,
                      decoration: const InputDecoration(
                        labelText: 'Success target',
                        hintText: 'Example: Finish morning reset',
                        prefixIcon: Icon(Icons.flag_outlined),
                        isDense: true,
                      ),
                      onChanged: (value) => update(target: value),
                    ),
                    const SizedBox(height: 10),
                    Text('Cadence', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final recurrence in const [
                          ('daily', 'Daily'),
                          ('weekdays', 'Weekdays'),
                          ('weekly', 'Weekly'),
                          ('monthly', 'Monthly'),
                        ])
                          ChoiceChip(
                            key: ValueKey<String>(
                              'productivity-routine-recurrence-${recurrence.$1}',
                            ),
                            label: Text(recurrence.$2),
                            selected: payload.recurrence == recurrence.$1,
                            onSelected: (_) =>
                                update(recurrence: recurrence.$1),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey<String>('routine-toggle-today'),
                onPressed: () async {
                  final next = {...completionKeys};
                  completed
                      ? next.remove(activeDayKey)
                      : next.add(activeDayKey);
                  final action = HabitRoutinePayload(
                    target: payload.target,
                    recurrence: payload.recurrence,
                    completions: next.toList()..sort(),
                  );
                  final callback = context.onHabitAction;
                  callback == null
                      ? context.onDraftChanged(action)
                      : await callback(action);
                },
                icon: Icon(
                  completed ? Icons.undo_rounded : Icons.playlist_add_check,
                ),
                label: Text(completed ? 'Undo check-in' : 'Complete routine'),
              ),
              const SizedBox(width: 8),
              Chip(label: Text('$recentCount / 28 days')),
              const SizedBox(width: 8),
              Chip(label: Text('${completionKeys.length} total')),
            ],
          ),
          const SizedBox(height: 14),
          Text('Last 4 weeks', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            key: const ValueKey<String>('routine-four-week-tracker'),
            children: [
              for (final day in recentDays)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: completionKeys.contains(dayKey(day))
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (final error in context.validationErrors)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }
}

final class _DraftActions extends StatelessWidget {
  const _DraftActions(this.context);

  final NodeEditContext context;

  @override
  Widget build(BuildContext buildContext) => switch (context.node.type) {
    NodeType.kanban => _kanban(),
    NodeType.plan => _plan(),
    NodeType.goal => _goal(),
    NodeType.habit || NodeType.routine => _habit(),
    NodeType.task || NodeType.checklist => _checklist(),
    NodeType.timer => _timer(),
    NodeType.note => const SizedBox.shrink(),
    _ => const SizedBox.shrink(),
  };

  Widget _kanban() {
    final payload = context.typedDraft is KanbanPayload
        ? context.typedDraft as KanbanPayload
        : KanbanPayload.fromNode(context.node);
    final movable = payload.cards.where((card) => card.column.next != null);
    if (movable.isEmpty) return const Text('All cards complete');
    final card = movable.first;
    return FilledButton.tonalIcon(
      key: const ValueKey<String>('kanban-advance-card'),
      onPressed: () async {
        final board = KanbanBoard(
          cards: payload.cards,
        ).moveCardToNextColumn(card.id);
        final KanbanPayload action = KanbanPayload(cards: board.cards);
        final NodeAsyncPayloadAction? callback = context.onKanbanAction;
        callback == null
            ? context.onDraftChanged(action)
            : await callback(action);
      },
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: Text('Advance ${card.title}'),
    );
  }

  Widget _plan() {
    final payload = context.typedDraft is PlanPayload
        ? context.typedDraft as PlanPayload
        : PlanPayload.fromNode(context.node);
    final completed = payload.completedSteps.toSet();
    final next = payload.steps
        .where((step) => !completed.contains(step))
        .firstOrNull;
    return _ActionButton(
      label: next == null ? 'Plan complete' : 'Complete $next',
      enabled: next != null,
      onPressed: () async {
        final draft = context.node.copyWith(
          data: payload.toData(context.node.data),
        );
        final MindmapNode action = advancePlanStep(draft);
        final NodeAsyncDraftAction? callback = context.onPlanAction;
        callback == null
            ? context.onNodeDraftChanged(action)
            : await callback(action);
      },
    );
  }

  Widget _goal() {
    final payload = context.typedDraft is GoalPayload
        ? context.typedDraft as GoalPayload
        : GoalPayload.fromNode(context.node);
    final completed = payload.completedMilestones.toSet();
    final next = payload.milestones
        .where((item) => !completed.contains(item))
        .firstOrNull;
    return _ActionButton(
      label: next == null ? 'Goal complete' : 'Complete $next',
      enabled: next != null,
      onPressed: () async {
        final draft = context.node.copyWith(
          data: payload.toData(context.node.data),
        );
        final MindmapNode action = advanceGoalMilestone(draft);
        final NodeAsyncDraftAction? callback = context.onGoalAction;
        callback == null
            ? context.onNodeDraftChanged(action)
            : await callback(action);
      },
    );
  }

  Widget _habit() {
    final payload = context.typedDraft is HabitRoutinePayload
        ? context.typedDraft as HabitRoutinePayload
        : HabitRoutinePayload.fromNode(context.node);
    final completed = context.node.type == NodeType.habit
        ? hasHabitCompletionOn(context.node, context.node.day)
        : payload.completions.contains(
            context.node.day.toIso8601String().split('T').first,
          );
    return _ActionButton(
      label: completed ? 'Completed today' : 'Complete today',
      enabled: !completed,
      onPressed: () async {
        if (context.node.type == NodeType.habit) {
          final draft = context.node.copyWith(
            data: payload.toData(context.node.data),
          );
          final MindmapNode action = logHabitCompletion(
            draft,
            context.node.day,
          );
          final NodeAsyncPayloadAction? callback = context.onHabitAction;
          callback == null
              ? context.onNodeDraftChanged(action)
              : await callback(action);
          return;
        }
        final key = context.node.day.toIso8601String().split('T').first;
        final HabitRoutinePayload action = HabitRoutinePayload(
          target: payload.target,
          recurrence: payload.recurrence,
          completions: [...payload.completions, key],
        );
        final NodeAsyncPayloadAction? callback = context.onHabitAction;
        callback == null
            ? context.onDraftChanged(action)
            : await callback(action);
      },
    );
  }

  Widget _checklist() {
    final payload = context.typedDraft is TaskChecklistPayload
        ? context.typedDraft as TaskChecklistPayload
        : TaskChecklistPayload.fromNode(context.node);
    if (payload.items.isEmpty) return const Text('No checklist items');
    final item = payload.items.first;
    if (context.node.type == NodeType.task) {
      final draftNode = payload.toNode(context.node);
      final next = nextOpenChecklistItem(draftNode);
      return _ActionButton(
        label: next == null ? 'Checklist complete' : 'Complete ${next.title}',
        enabled: next != null,
        onPressed: () async {
          final MindmapNode action = completeNextChecklistItem(draftNode);
          final NodeAsyncDraftAction? callback = context.onTaskChecklistAction;
          callback == null
              ? context.onNodeDraftChanged(action)
              : await callback(action);
        },
      );
    }
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(item.title),
      value: item.isDone,
      onChanged: (value) => context.onDraftChanged(
        payload.copyWith(
          items: [
            item.copyWith(isDone: value ?? false),
            ...payload.items.skip(1),
          ],
        ),
      ),
    );
  }

  Widget _timer() {
    final payload = context.typedDraft is TimerPayload
        ? context.typedDraft as TimerPayload
        : TimerPayload.fromNode(context.node);
    return _ActionButton(
      label: 'Reset timer',
      enabled: payload.timerInitialSeconds != null,
      onPressed: () async {
        final TimerPayload action = TimerPayload(timer: payload.timer.reset());
        final NodeAsyncPayloadAction? callback = context.onTimerAction;
        callback == null
            ? context.onDraftChanged(action)
            : await callback(action);
      },
    );
  }
}

final class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: enabled ? onPressed : null,
    child: Text(label, overflow: TextOverflow.ellipsis),
  );
}

final class _ChecklistView extends StatelessWidget {
  const _ChecklistView({required this.payload, required this.showAll});

  final TaskChecklistPayload payload;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final items = showAll ? payload.items : payload.items.take(3);
    return Column(
      children: [
        for (final item in items)
          Row(
            children: [
              Icon(
                item.isDone ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(item.title, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
      ],
    );
  }
}

final class _KanbanView extends StatelessWidget {
  const _KanbanView({required this.payload, required this.showAll});

  final KanbanPayload payload;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final cards = showAll ? payload.cards : payload.cards.take(4);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final card in cards)
          Chip(label: Text('${card.column.label}: ${card.title}')),
      ],
    );
  }
}

final class _ProgressList extends StatelessWidget {
  const _ProgressList({
    required this.items,
    required this.completed,
    required this.showAll,
  });

  final List<String> items;
  final List<String> completed;
  final bool showAll;

  @override
  Widget build(BuildContext context) {
    final visible = showAll ? items : items.take(3);
    return Column(
      children: [
        for (final item in visible)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              completed.contains(item)
                  ? Icons.check_circle
                  : Icons.circle_outlined,
              size: 18,
            ),
            title: Text(item, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

final class _RoutineView extends StatelessWidget {
  const _RoutineView({required this.payload});

  final HabitRoutinePayload payload;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.event_repeat_outlined, size: 14),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          payload.target.isEmpty
              ? payload.recurrence
              : '${payload.recurrence} · ${payload.target}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 6),
      Text('${payload.completions.length} check-ins'),
    ],
  );
}

final class _HabitView extends StatelessWidget {
  const _HabitView({required this.payload, required this.showAll});

  final HabitRoutinePayload payload;
  final bool showAll;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(payload.target.isEmpty ? 'No target' : payload.target),
      const SizedBox(height: 6),
      Text('${payload.recurrence} · ${payload.completions.length} completions'),
      if (showAll && payload.completions.isNotEmpty)
        Text(payload.completions.take(7).join(' · ')),
    ],
  );
}

final class _HabitHeatmap extends StatefulWidget {
  const _HabitHeatmap({required this.completionKeys});

  final Set<String> completionKeys;

  @override
  State<_HabitHeatmap> createState() => _HabitHeatmapState();
}

final class _HabitHeatmapState extends State<_HabitHeatmap> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime today = DateTime.now().dateOnly;
    final int offsetDays = today.weekday % 7;
    final DateTime startDate = today.subtract(
      Duration(days: 52 * 7 + offsetDays),
    );

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
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(53, (int weekIndex) {
                  return Column(
                    children: List.generate(7, (int dayIndex) {
                      final DateTime day = startDate.add(
                        Duration(days: weekIndex * 7 + dayIndex),
                      );
                      final bool isDone = widget.completionKeys.contains(
                        dayKey(day),
                      );
                      final bool isFuture = day.isAfter(today);
                      final bool isToday = day.isSameDay(today);
                      final Color habitColor =
                          AppThemeVariantColors.of(
                            AppThemeVariant.astryxNeutral,
                          ).nodeColors[NodeType.habit] ??
                          Colors.grey;
                      final Color cellColor = isFuture
                          ? theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.1)
                          : isDone
                          ? habitColor
                          : isToday
                          ? habitColor.withValues(alpha: 0.15)
                          : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4);
                      final BorderSide borderSide = isToday
                          ? BorderSide(color: habitColor, width: 1.5)
                          : BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.25),
                              width: 0.75,
                            );
                      final String statusText = isDone
                          ? 'Completed'
                          : isFuture
                          ? 'Future'
                          : 'Not completed';

                      return Tooltip(
                        message:
                            '${DateFormat('EEEE, MMM d, yyyy').format(day)}: '
                            '$statusText',
                        child: Container(
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.all(2),
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

final class _TimerView extends StatelessWidget {
  const _TimerView({required this.payload});

  final TimerPayload payload;

  @override
  Widget build(BuildContext context) {
    final seconds = payload.timerSeconds ?? payload.timerInitialSeconds ?? 0;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return Text(
      '$minutes:$remainder',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}

final class _FallbackContent extends StatelessWidget {
  const _FallbackContent(this.context);

  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(context.node.title, overflow: TextOverflow.ellipsis),
  );
}

final class _FallbackEditor extends StatelessWidget {
  const _FallbackEditor(this.context);

  final NodeEditContext context;

  @override
  Widget build(BuildContext buildContext) => TextFormField(
    initialValue: context.node.title,
    onChanged: context.onTitleChanged,
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
