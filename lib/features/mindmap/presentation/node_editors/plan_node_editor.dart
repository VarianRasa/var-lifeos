import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/project_plan.dart';

typedef PlanAttachmentAddCallback =
    Future<ProjectPlanAttachmentReference?> Function();
typedef PlanAttachmentActionCallback =
    Future<void> Function(ProjectPlanAttachmentReference attachment);

final class PlanNodeEditor extends StatefulWidget {
  const PlanNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    this.onAttachmentAdd,
    this.onAttachmentOpen,
    this.onAttachmentRemove,
    super.key,
  });
  final MindmapNode node;
  final PlanPayload payload;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<PlanPayload> onPayloadChanged;
  final PlanAttachmentAddCallback? onAttachmentAdd;
  final PlanAttachmentActionCallback? onAttachmentOpen;
  final PlanAttachmentActionCallback? onAttachmentRemove;
  @override
  State<PlanNodeEditor> createState() => _PlanNodeEditorState();
}

final class _PlanNodeEditorState extends State<PlanNodeEditor> {
  ProjectPlan get project => widget.payload.project;
  void _emit(ProjectPlan value) =>
      widget.onPayloadChanged(PlanPayload(project: value));

  Future<String?> _name(String title) async {
    var value = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(80),
          ],
          onChanged: (next) => value = next,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhase() async {
    final title = await _name('Add phase');
    if (title == null || title.isEmpty) return;
    _emit(
      project.copyWith(
        phases: <ProjectPhase>[
          ...project.phases,
          ProjectPhase(
            id: 'phase-${const Uuid().v4()}',
            title: title,
            order: project.phases.length,
          ),
        ],
      ),
    );
  }

  void _phase(ProjectPhase value) => _emit(
    project.copyWith(
      phases: <ProjectPhase>[
        for (final item in project.phases) item.id == value.id ? value : item,
      ],
    ),
  );

  Future<void> _addMilestone(ProjectPhase phase) async {
    final title = await _name('Add milestone');
    if (title == null || title.isEmpty) return;
    _phase(
      phase.copyWith(
        milestones: <ProjectMilestone>[
          ...phase.milestones,
          ProjectMilestone(
            id: 'milestone-${const Uuid().v4()}',
            title: title,
            order: phase.milestones.length,
          ),
        ],
      ),
    );
  }

  void _milestone(String phaseId, ProjectMilestone value) {
    final phase = project.phases.firstWhere((item) => item.id == phaseId);
    _phase(
      phase.copyWith(
        milestones: <ProjectMilestone>[
          for (final item in phase.milestones)
            item.id == value.id ? value : item,
        ],
      ),
    );
  }

  Future<void> _addTask(String phaseId, ProjectMilestone milestone) async {
    final title = await _name('Add task');
    if (title == null || title.isEmpty) return;
    _milestone(
      phaseId,
      milestone.copyWith(
        tasks: <ProjectTask>[
          ...milestone.tasks,
          ProjectTask(
            id: 'task-${const Uuid().v4()}',
            title: title,
            order: milestone.tasks.length,
          ),
        ],
      ),
    );
  }

  void _task(ProjectTask value) => _emit(project.updateTask(value));
  void _toggle(ProjectTask task) => _task(
    task.copyWith(
      status: task.status == ProjectTaskStatus.done
          ? ProjectTaskStatus.planned
          : ProjectTaskStatus.done,
    ),
  );
  void _check(ProjectTask task, String id) => _task(
    task.copyWith(
      checklist: <ProjectTaskChecklistItem>[
        for (final item in task.checklist)
          item.id == id ? item.copyWith(isDone: !item.isDone) : item,
      ],
    ),
  );

  Future<void> _edit(ProjectTask task) async {
    final value = await showDialog<ProjectTask>(
      context: context,
      builder: (_) => _TaskDialog(project: project, task: task),
    );
    if (value != null) {
      _task(value);
    }
  }

  Future<void> _attach(ProjectTask task) async {
    final value = await widget.onAttachmentAdd?.call();
    if (value != null) {
      _task(
        task.copyWith(
          attachments: <ProjectPlanAttachmentReference>[
            ...task.attachments,
            value,
          ],
        ),
      );
    }
  }

  Future<void> _removeAttachment(
    ProjectTask task,
    ProjectPlanAttachmentReference attachment,
  ) async {
    await widget.onAttachmentRemove?.call(attachment);
    _task(
      task.copyWith(
        attachments: task.attachments
            .where((item) => item.id != attachment.id)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phases = [...project.phases]
      ..sort((a, b) => a.order.compareTo(b.order));
    return ColoredBox(
      key: const ValueKey<String>('plan-project-editor'),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                key: ValueKey<String>(
                  'productivity-${widget.node.id}-title-field',
                ),
                initialValue: widget.node.title,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.route_outlined),
                  hintText: 'Project title',
                  isDense: true,
                ),
                onChanged: widget.onTitleChanged,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey<String>(
                  'productivity-${widget.node.id}-body-field',
                ),
                initialValue: widget.node.body,
                maxLines: 3,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(500),
                ],
                decoration: const InputDecoration(
                  hintText: 'Project objective and context',
                  isDense: true,
                ),
                onChanged: widget.onBodyChanged,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  DropdownButton<ProjectPlanStatus>(
                    value: project.status,
                    items: <DropdownMenuItem<ProjectPlanStatus>>[
                      for (final value in ProjectPlanStatus.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_label(value.name)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) _emit(project.copyWith(status: value));
                    },
                  ),
                  _Chip('${phases.length} phases'),
                  _Chip('${project.milestoneCount} milestones'),
                  _Chip('${project.taskCount} tasks'),
                  _Chip('${project.blockedTaskCount} blocked'),
                  FilledButton.tonalIcon(
                    key: const ValueKey<String>('plan-add-phase'),
                    onPressed: _addPhase,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Phase'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: project.progress),
              const SizedBox(height: 12),
              if (phases.isEmpty)
                _Empty(label: 'Add first phase', onTap: _addPhase),
              for (var index = 0; index < phases.length; index++) ...<Widget>[
                DragTarget<_PhaseDrag>(
                  onWillAcceptWithDetails: (details) =>
                      details.data.id != phases[index].id,
                  onAcceptWithDetails: (details) =>
                      _emit(project.movePhase(details.data.id, index)),
                  builder: (context, candidates, rejects) => _Phase(
                    phase: phases[index],
                    project: project,
                    highlighted: candidates.isNotEmpty,
                    onAddMilestone: () => _addMilestone(phases[index]),
                    onMilestone: (value) => _milestone(phases[index].id, value),
                    onAddTask: (value) => _addTask(phases[index].id, value),
                    onTask: _task,
                    onToggle: _toggle,
                    onCheck: _check,
                    onEdit: _edit,
                    onAttach: _attach,
                    onOpenAttachment: widget.onAttachmentOpen,
                    onRemoveAttachment: _removeAttachment,
                    onMoveMilestone: (id, target) => _emit(
                      project.moveMilestone(id, phases[index].id, target),
                    ),
                    onMoveTask: (id, milestoneId, target) =>
                        _emit(project.moveTask(id, milestoneId, target)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _Phase extends StatelessWidget {
  const _Phase({
    required this.phase,
    required this.project,
    required this.highlighted,
    required this.onAddMilestone,
    required this.onMilestone,
    required this.onAddTask,
    required this.onTask,
    required this.onToggle,
    required this.onCheck,
    required this.onEdit,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
    required this.onMoveMilestone,
    required this.onMoveTask,
  });
  final ProjectPhase phase;
  final ProjectPlan project;
  final bool highlighted;
  final VoidCallback onAddMilestone;
  final ValueChanged<ProjectMilestone> onMilestone;
  final ValueChanged<ProjectMilestone> onAddTask;
  final ValueChanged<ProjectTask> onTask;
  final ValueChanged<ProjectTask> onToggle;
  final void Function(ProjectTask, String) onCheck;
  final ValueChanged<ProjectTask> onEdit;
  final ValueChanged<ProjectTask> onAttach;
  final PlanAttachmentActionCallback? onOpenAttachment;
  final void Function(ProjectTask, ProjectPlanAttachmentReference)
  onRemoveAttachment;
  final void Function(String, int) onMoveMilestone;
  final void Function(String, String, int) onMoveTask;

  @override
  Widget build(BuildContext context) {
    final milestones = [...phase.milestones]
      ..sort((a, b) => a.order.compareTo(b.order));
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('plan-phase-${phase.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(
          color: highlighted ? colors.primary : colors.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Draggable<_PhaseDrag>(
                key: ValueKey<String>('plan-phase-drag-${phase.id}'),
                data: _PhaseDrag(phase.id),
                feedback: Material(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(phase.title),
                  ),
                ),
                child: const Icon(Icons.drag_indicator_rounded, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  phase.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${(phase.progress * 100).round()}%'),
            ],
          ),
          LinearProgressIndicator(value: phase.progress),
          const SizedBox(height: 8),
          for (var index = 0; index < milestones.length; index++) ...<Widget>[
            DragTarget<_MilestoneDrag>(
              onWillAcceptWithDetails: (details) =>
                  details.data.id != milestones[index].id,
              onAcceptWithDetails: (details) =>
                  onMoveMilestone(details.data.id, index),
              builder: (context, candidates, rejects) => _Milestone(
                milestone: milestones[index],
                project: project,
                highlighted: candidates.isNotEmpty,
                onAddTask: () => onAddTask(milestones[index]),
                onTask: onTask,
                onToggle: onToggle,
                onCheck: onCheck,
                onEdit: onEdit,
                onAttach: onAttach,
                onOpenAttachment: onOpenAttachment,
                onRemoveAttachment: onRemoveAttachment,
                onMoveTask: (id, target) =>
                    onMoveTask(id, milestones[index].id, target),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextButton.icon(
            key: ValueKey<String>('plan-add-milestone-${phase.id}'),
            onPressed: onAddMilestone,
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add milestone'),
          ),
        ],
      ),
    );
  }
}

final class _Milestone extends StatelessWidget {
  const _Milestone({
    required this.milestone,
    required this.project,
    required this.highlighted,
    required this.onAddTask,
    required this.onTask,
    required this.onToggle,
    required this.onCheck,
    required this.onEdit,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
    required this.onMoveTask,
  });
  final ProjectMilestone milestone;
  final ProjectPlan project;
  final bool highlighted;
  final VoidCallback onAddTask;
  final ValueChanged<ProjectTask> onTask;
  final ValueChanged<ProjectTask> onToggle;
  final void Function(ProjectTask, String) onCheck;
  final ValueChanged<ProjectTask> onEdit;
  final ValueChanged<ProjectTask> onAttach;
  final PlanAttachmentActionCallback? onOpenAttachment;
  final void Function(ProjectTask, ProjectPlanAttachmentReference)
  onRemoveAttachment;
  final void Function(String, int) onMoveTask;

  @override
  Widget build(BuildContext context) {
    final tasks = [...milestone.tasks]
      ..sort((a, b) => a.order.compareTo(b.order));
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>('plan-milestone-${milestone.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: highlighted ? colors.primary : colors.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Draggable<_MilestoneDrag>(
                key: ValueKey<String>('plan-milestone-drag-${milestone.id}'),
                data: _MilestoneDrag(milestone.id),
                feedback: Material(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(milestone.title),
                  ),
                ),
                child: const Icon(Icons.drag_indicator_rounded, size: 18),
              ),
              const Icon(Icons.flag_outlined, size: 17),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  milestone.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text('${milestone.completedTaskCount}/${tasks.length}'),
            ],
          ),
          LinearProgressIndicator(value: milestone.progress),
          const SizedBox(height: 7),
          for (var index = 0; index < tasks.length; index++) ...<Widget>[
            DragTarget<_TaskDrag>(
              onWillAcceptWithDetails: (details) =>
                  details.data.id != tasks[index].id,
              onAcceptWithDetails: (details) =>
                  onMoveTask(details.data.id, index),
              builder: (context, candidates, rejects) => _Task(
                task: tasks[index],
                project: project,
                highlighted: candidates.isNotEmpty,
                onToggle: () => onToggle(tasks[index]),
                onEdit: () => onEdit(tasks[index]),
                onCheck: (id) => onCheck(tasks[index], id),
                onAttach: () => onAttach(tasks[index]),
                onOpenAttachment: onOpenAttachment,
                onRemoveAttachment: (value) =>
                    onRemoveAttachment(tasks[index], value),
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (tasks.isEmpty)
            _Empty(label: 'Add first task', onTap: onAddTask)
          else
            TextButton.icon(
              key: ValueKey<String>('plan-add-task-${milestone.id}'),
              onPressed: onAddTask,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Add task'),
            ),
        ],
      ),
    );
  }
}

final class _Task extends StatelessWidget {
  const _Task({
    required this.task,
    required this.project,
    required this.highlighted,
    required this.onToggle,
    required this.onEdit,
    required this.onCheck,
    required this.onAttach,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
  });
  final ProjectTask task;
  final ProjectPlan project;
  final bool highlighted;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final ValueChanged<String> onCheck;
  final VoidCallback onAttach;
  final PlanAttachmentActionCallback? onOpenAttachment;
  final ValueChanged<ProjectPlanAttachmentReference> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dependencies = task.normalizedDependencyTaskIds
        .map(project.taskById)
        .whereType<ProjectTask>();
    return Container(
      key: ValueKey<String>('plan-task-${task.id}'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(
          color: highlighted ? colors.primary : colors.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Draggable<_TaskDrag>(
                key: ValueKey<String>('plan-task-drag-${task.id}'),
                data: _TaskDrag(task.id),
                feedback: Material(
                  elevation: 8,
                  child: SizedBox(
                    width: 300,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(task.title),
                    ),
                  ),
                ),
                child: const Icon(Icons.drag_indicator_rounded, size: 18),
              ),
              IconButton(
                key: ValueKey<String>('plan-task-toggle-${task.id}'),
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
                icon: Icon(
                  task.status == ProjectTaskStatus.done
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 19,
                ),
              ),
              Expanded(
                child: Text(
                  task.title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    decoration: task.status == ProjectTaskStatus.done
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>('plan-task-edit-${task.id}'),
                tooltip: 'Edit task',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          if (task.description.isNotEmpty) Text(task.description),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: <Widget>[
              _Meta(Icons.sync_alt, _label(task.status.name)),
              if (task.priority != ProjectTaskPriority.none)
                _Meta(Icons.flag_outlined, _label(task.priority.name)),
              if (task.startDate != null)
                _Meta(
                  Icons.play_circle_outline,
                  'Starts ${DateFormat('d MMM yyyy').format(task.startDate!)}',
                ),
              if (task.deadline != null)
                _Meta(
                  Icons.event_outlined,
                  'Due ${DateFormat('d MMM yyyy').format(task.deadline!)}',
                ),
              if (task.estimatedMinutes != null)
                _Meta(
                  Icons.timer_outlined,
                  'Estimate ${task.estimatedMinutes}m',
                ),
              if (task.actualMinutes != null)
                _Meta(Icons.timelapse, 'Actual ${task.actualMinutes}m'),
              for (final label in task.labels) _Chip(label),
            ],
          ),
          if (dependencies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text('Dependencies', style: Theme.of(context).textTheme.labelSmall),
            Wrap(
              spacing: 5,
              children: <Widget>[
                for (final item in dependencies) _Chip(item.title),
              ],
            ),
          ],
          if (task.status == ProjectTaskStatus.blocked &&
              task.blockingReason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Blocked: ${task.blockingReason}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
          if (task.checklist.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Checklist ${task.completedChecklistCount}/${task.checklist.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            for (final item in task.checklist)
              InkWell(
                key: ValueKey<String>('plan-checklist-${task.id}-${item.id}'),
                onTap: () => onCheck(item.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        item.isDone
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 17,
                      ),
                      const SizedBox(width: 5),
                      Expanded(child: Text(item.title)),
                    ],
                  ),
                ),
              ),
          ],
          Row(
            children: <Widget>[
              Text(
                'Attachments',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              IconButton(
                key: ValueKey<String>('plan-add-attachment-${task.id}'),
                tooltip: 'Add attachment',
                visualDensity: VisualDensity.compact,
                onPressed: onAttach,
                icon: const Icon(Icons.add, size: 17),
              ),
            ],
          ),
          for (final attachment in task.attachments)
            ListTile(
              key: ValueKey<String>(
                'plan-attachment-${task.id}-${attachment.id}',
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
              title: Text(
                attachment.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: onOpenAttachment == null
                  ? null
                  : () => onOpenAttachment!(attachment),
              trailing: IconButton(
                onPressed: () => onRemoveAttachment(attachment),
                icon: const Icon(Icons.delete_outline, size: 17),
              ),
            ),
        ],
      ),
    );
  }
}

final class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.project, required this.task});
  final ProjectPlan project;
  final ProjectTask task;
  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

final class _TaskDialogState extends State<_TaskDialog> {
  late String title = widget.task.title;
  late String description = widget.task.description;
  late ProjectTaskStatus status = widget.task.status;
  late ProjectTaskPriority priority = widget.task.priority;
  late String labels = widget.task.labels.join(', ');
  late String estimate = widget.task.estimatedMinutes?.toString() ?? '';
  late String actual = widget.task.actualMinutes?.toString() ?? '';
  late DateTime? startDate = widget.task.startDate;
  late DateTime? deadline = widget.task.deadline;
  late String blocking = widget.task.blockingReason;
  late String checklist = widget.task.checklist
      .map((item) => item.title)
      .join('\n');
  late Set<String> dependencies = widget.task.normalizedDependencyTaskIds
      .toSet();

  Future<DateTime?> _pickDate(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

  @override
  Widget build(BuildContext context) {
    final invalidDates =
        startDate != null && deadline != null && deadline!.isBefore(startDate!);
    return AlertDialog(
      title: const Text('Edit task'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                initialValue: title,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) => setState(() => title = value),
              ),
              TextFormField(
                initialValue: description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
                onChanged: (value) => description = value,
              ),
              DropdownButtonFormField<ProjectTaskStatus>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: <DropdownMenuItem<ProjectTaskStatus>>[
                  for (final value in ProjectTaskStatus.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                ],
                onChanged: (value) => setState(() => status = value ?? status),
              ),
              DropdownButtonFormField<ProjectTaskPriority>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: <DropdownMenuItem<ProjectTaskPriority>>[
                  for (final value in ProjectTaskPriority.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => priority = value ?? priority),
              ),
              TextFormField(
                initialValue: labels,
                decoration: const InputDecoration(labelText: 'Labels'),
                onChanged: (value) => labels = value,
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      initialValue: estimate,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Estimate'),
                      onChanged: (value) => estimate = value,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: actual,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(labelText: 'Actual'),
                      onChanged: (value) => actual = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _DateButton(
                      key: const ValueKey<String>('plan-task-start-date'),
                      label: 'Start',
                      value: startDate,
                      onPick: () async {
                        final value = await _pickDate(startDate);
                        if (value != null) setState(() => startDate = value);
                      },
                      onClear: startDate == null
                          ? null
                          : () => setState(() => startDate = null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateButton(
                      key: const ValueKey<String>('plan-task-deadline'),
                      label: 'Deadline',
                      value: deadline,
                      onPick: () async {
                        final value = await _pickDate(deadline);
                        if (value != null) setState(() => deadline = value);
                      },
                      onClear: deadline == null
                          ? null
                          : () => setState(() => deadline = null),
                    ),
                  ),
                ],
              ),
              if (startDate != null &&
                  deadline != null &&
                  deadline!.isBefore(startDate!))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Deadline must be on or after start date.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextFormField(
                initialValue: blocking,
                decoration: const InputDecoration(labelText: 'Blocking reason'),
                onChanged: (value) => blocking = value,
              ),
              TextFormField(
                initialValue: checklist,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Checklist',
                  hintText: 'One item per line',
                ),
                onChanged: (value) => checklist = value,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Dependencies',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final task in widget.project.tasks)
                if (task.id != widget.task.id)
                  CheckboxListTile(
                    dense: true,
                    value: dependencies.contains(task.id),
                    title: Text(task.title),
                    onChanged: (selected) => setState(() {
                      if (selected ?? false) {
                        dependencies.add(task.id);
                      } else {
                        dependencies.remove(task.id);
                      }
                    }),
                  ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: title.trim().isEmpty || invalidDates
              ? null
              : () {
                  final old = <String, ProjectTaskChecklistItem>{
                    for (final item in widget.task.checklist) item.title: item,
                  };
                  final items = checklist
                      .split('\n')
                      .map((value) => value.trim())
                      .where((value) => value.isNotEmpty);
                  Navigator.pop(
                    context,
                    widget.task.copyWith(
                      title: title.trim(),
                      description: description.trim(),
                      status: status,
                      priority: priority,
                      labels: labels
                          .split(',')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toSet()
                          .toList(),
                      dependencyTaskIds: dependencies.toList(),
                      startDate: startDate,
                      clearStartDate: startDate == null,
                      deadline: deadline,
                      clearDeadline: deadline == null,
                      estimatedMinutes: int.tryParse(estimate),
                      clearEstimatedMinutes: estimate.isEmpty,
                      actualMinutes: int.tryParse(actual),
                      clearActualMinutes: actual.isEmpty,
                      blockingReason: blocking.trim(),
                      checklist: <ProjectTaskChecklistItem>[
                        for (final item in items)
                          old[item] ??
                              ProjectTaskChecklistItem(
                                id: 'check-${const Uuid().v4()}',
                                title: item,
                              ),
                      ],
                    ),
                  );
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

final class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Row(
      children: <Widget>[
        Expanded(
          child: TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              value == null
                  ? 'Choose date'
                  : DateFormat('d MMM yyyy').format(value!),
            ),
          ),
        ),
        if (onClear != null)
          IconButton(
            tooltip: 'Clear $label',
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    ),
  );
}

final class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

final class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 13),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

final class _Empty extends StatelessWidget {
  const _Empty({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

final class _PhaseDrag {
  const _PhaseDrag(this.id);
  final String id;
}

final class _MilestoneDrag {
  const _MilestoneDrag(this.id);
  final String id;
}

final class _TaskDrag {
  const _TaskDrag(this.id);
  final String id;
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp('([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
