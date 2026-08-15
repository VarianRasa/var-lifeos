/// Dialog for creating a node on a day's mindmap.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_template.dart';

final class AddNodeDraft {
  const AddNodeDraft({
    required this.type,
    required this.title,
    required this.body,
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

  final NodeType type;
  final String title;
  final String body;
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
}

Future<AddNodeDraft?> showAddNodeDialog(BuildContext context) {
  return showDialog<AddNodeDraft>(
    context: context,
    builder: (context) => const _NodeEditorDialog.add(),
  );
}

final class EditNodeResult {
  const EditNodeResult.save(this.draft) : shouldDelete = false;

  const EditNodeResult.delete() : draft = null, shouldDelete = true;

  final AddNodeDraft? draft;
  final bool shouldDelete;
}

Future<EditNodeResult?> showEditNodeDialog(
  BuildContext context,
  MindmapNode node,
) {
  return showDialog<EditNodeResult>(
    context: context,
    builder: (context) => _NodeEditorDialog.edit(node: node),
  );
}

class _NodeEditorDialog extends StatefulWidget {
  const _NodeEditorDialog.add()
    : node = null,
      keyPrefix = 'add-node',
      allowDelete = false;

  const _NodeEditorDialog.edit({required MindmapNode this.node})
    : keyPrefix = 'node-editor',
      allowDelete = true;

  final MindmapNode? node;
  final String keyPrefix;
  final bool allowDelete;

  @override
  State<_NodeEditorDialog> createState() => _NodeEditorDialogState();
}

class _NodeEditorDialogState extends State<_NodeEditorDialog> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _projectController = TextEditingController();
  final _areaController = TextEditingController();
  final _tagsController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _progressController = TextEditingController();
  final _relatedNodeIdsController = TextEditingController();
  final _checklistController = TextEditingController();
  final _kanbanCardsController = TextEditingController();
  final _habitTargetController = TextEditingController();
  final _habitCompletionsController = TextEditingController();
  final _goalMilestonesController = TextEditingController();
  final _goalCompletedMilestonesController = TextEditingController();
  final _planStepsController = TextEditingController();
  final _planCompletedStepsController = TextEditingController();
  final _noteSourceController = TextEditingController();
  final _journalMoodController = TextEditingController();
  final _journalEnergyController = TextEditingController();
  final _journalPromptController = TextEditingController();
  final _journalGratitudeController = TextEditingController();
  final _calValueController = TextEditingController();
  final _calUnitController = TextEditingController();
  final _calLocationController = TextEditingController();
  final _calParticipantsController = TextEditingController();
  final _calAttendeesController = TextEditingController();
  final _calAgendaController = TextEditingController();
  final _calDecisionsController = TextEditingController();
  final _calActionsController = TextEditingController();
  final _calOptionsController = TextEditingController();
  final _calSelectedOptionController = TextEditingController();
  final _calReasonController = TextEditingController();
  final _calRemindAtController = TextEditingController();
  NodeType _type = NodeType.task;
  NodeStatus _status = NodeStatus.open;
  NodePriority _priority = NodePriority.none;
  String _habitRecurrence = 'daily';
  bool _isPinned = false;
  bool _isArchived = false;
  bool _journalWeeklyReview = false;
  bool _journalMonthlyReview = false;
  bool _hasCalendarPayload = false;
  CalendarNodeKind? _calendarKind;
  String? _selectedTemplateId;
  String? _titleError;
  String? _dueDateError;
  String? _progressError;

  bool get _isEditing => widget.node != null;

  String _nodeTypeDescription(NodeType type) => switch (type) {
    NodeType.task =>
      'A checklist item with sub-tasks and direct completion toggle.',
    NodeType.kanban =>
      'A mini Kanban board with customizable cards and 3 columns (To Do, Doing, Done).',
    NodeType.plan => 'A sequential timeline of steps to complete in order.',
    NodeType.note =>
      'A simple document for keeping structured notes and external reference links.',
    NodeType.journal =>
      'A daily reflection node to track mood, energy, and gratitude list.',
    NodeType.habit =>
      'A recurring task to build streaks and track daily compliance.',
    NodeType.goal =>
      'A milestone-based target to track overall progress and achievement.',
    NodeType.link =>
      'A shortcut node containing an external URL and back-references.',
    NodeType.event =>
      'A calendar-aware event with agenda, location, and reminders.',
    NodeType.decision =>
      'A decision log with options, chosen path, and rationale.',
    NodeType.resource =>
      'A reusable reference, asset, reading, or external material.',
    NodeType.idea =>
      'A lightweight spark for concepts, experiments, and incubation.',
    NodeType.question =>
      'An open question with context, possible answers, and follow-up.',
    NodeType.contact =>
      'A person or organization with role, channel, and relationship notes.',
    NodeType.metric => 'A measurable value, KPI, health signal, or trend.',
    NodeType.expense => 'A spending, cost, purchase, or budget note.',
    NodeType.bookmark => 'A saved URL, reference, or external destination.',
    NodeType.routine =>
      'A repeatable workflow, ritual, or operating checklist.',
    NodeType.mood => 'A daily mood log with energy slider and emoji tracking.',
    NodeType.timer =>
      'A focus session timer (Pomodoro) with customizable durations.',
    NodeType.quote => 'A quotation card with author details.',
    NodeType.audio => 'A voice memo or audio recording card.',
    NodeType.checklist => 'A checklist card with interactive checkable items.',
    NodeType.canvas => 'A sketchpad card for drawing directly inside.',
    NodeType.weather => 'A weather logger tracking conditions and temperature.',
    NodeType.fit => 'A fitness tracker for steps, water intake, and workouts.',
    NodeType.empty => 'A basic spacer/empty node.',
    NodeType.itinerary =>
      'A travel itinerary with destinations, dates, and ordered agenda items.',
    NodeType.image =>
      'An image reference with source, accessible alt text, and caption.',
    NodeType.video =>
      'A video reference with source, playback metadata, and caption.',
    NodeType.frame =>
      'A visual container frame to group and organize multiple nodes together.',
    NodeType.swatch =>
      'A color swatch and moodboard palette card for design projects.',
  };

  @override
  void initState() {
    super.initState();
    final node = widget.node;
    if (node != null) {
      _type = node.type;
      _status = node.status;
      _priority = node.priority;
      _isPinned = node.isPinned;
      _isArchived = node.isArchived;
      _titleController.text = node.title;
      _bodyController.text = node.body;
      _projectController.text = node.project;
      _areaController.text = node.area;
      _tagsController.text = node.tags.join(', ');
      _dueDateController.text = node.dueDate == null
          ? ''
          : dayKey(node.dueDate!);
      _progressController.text = node.progress == 0
          ? ''
          : (node.progress * 100).round().toString();
      _relatedNodeIdsController.text = node.relatedNodeIds.join(', ');
      _checklistController.text = node.checklist
          .map((item) => item.title)
          .join('\n');
      _loadTypeSpecificData(node.data);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _projectController.dispose();
    _areaController.dispose();
    _tagsController.dispose();
    _dueDateController.dispose();
    _progressController.dispose();
    _relatedNodeIdsController.dispose();
    _checklistController.dispose();
    _kanbanCardsController.dispose();
    _habitTargetController.dispose();
    _habitCompletionsController.dispose();
    _goalMilestonesController.dispose();
    _goalCompletedMilestonesController.dispose();
    _planStepsController.dispose();
    _planCompletedStepsController.dispose();
    _noteSourceController.dispose();
    _journalMoodController.dispose();
    _journalEnergyController.dispose();
    _journalPromptController.dispose();
    _journalGratitudeController.dispose();
    _calValueController.dispose();
    _calUnitController.dispose();
    _calLocationController.dispose();
    _calParticipantsController.dispose();
    _calAttendeesController.dispose();
    _calAgendaController.dispose();
    _calDecisionsController.dispose();
    _calActionsController.dispose();
    _calOptionsController.dispose();
    _calSelectedOptionController.dispose();
    _calReasonController.dispose();
    _calRemindAtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppDesignTokens.of(context);
    final typeColor = NodeVisuals.color(context, _type);
    final contentHeight = (MediaQuery.sizeOf(context).height * 0.65)
        .clamp(400.0, 600.0)
        .toDouble();

    return AlertDialog(
      title: Text(_isEditing ? 'Edit node' : 'Add node'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SizedBox(
        width: 500,
        height: contentHeight,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choiceSection(context, 'Type', [
                for (final type in _primaryNodeTypes) _typeChoiceChip(type),
              ], wrap: true),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: ShapeDecoration(
                  color: typeColor.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.radiusElement),
                    side: BorderSide(color: typeColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(NodeVisuals.icon(_type), color: typeColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _nodeTypeDescription(_type),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 16),
                _choiceSection(context, 'Quick Template', [
                  for (final template in defaultNodeTemplates)
                    ChoiceChip(
                      key: ValueKey(
                        '${widget.keyPrefix}-template-${template.id}',
                      ),
                      label: Text(template.label),
                      selected: _selectedTemplateId == template.id,
                      onSelected: (_) => _applyTemplate(template),
                    ),
                ], wrap: true),
                const SizedBox(height: 10),
                _choiceSection(context, 'More Types', [
                  for (final type in _advancedNodeTypes) _typeChoiceChip(type),
                ]),
              ],
              const SizedBox(height: 24),
              Text('Basics', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('${widget.keyPrefix}-title-field'),
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: _titleError,
                  prefixIcon: const Icon(Icons.title),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_titleError != null) {
                    setState(() => _titleError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                key: ValueKey('${widget.keyPrefix}-body-field'),
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  prefixIcon: Icon(Icons.notes),
                  alignLabelWithHint: true,
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 24),
              Text('Categorize', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _choiceSection(context, 'Status', [
                for (final status in NodeStatus.values)
                  ChoiceChip(
                    key: ValueKey('${widget.keyPrefix}-status-${status.name}'),
                    label: Text(status.label),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ]),
              const SizedBox(height: 16),
              _choiceSection(context, 'Priority', [
                for (final priority in NodePriority.values)
                  ChoiceChip(
                    key: ValueKey(
                      '${widget.keyPrefix}-priority-${priority.name}',
                    ),
                    label: Text(priority.label),
                    selected: _priority == priority,
                    onSelected: (_) => setState(() => _priority = priority),
                  ),
              ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-project-field'),
                      controller: _projectController,
                      decoration: const InputDecoration(
                        labelText: 'Project',
                        hintText: 'Launch App',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-area-field'),
                      controller: _areaController,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        hintText: 'Health, Finance',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: ValueKey('${widget.keyPrefix}-tags-field'),
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'work, launch',
                  prefixIcon: Icon(Icons.tag),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 24),
              Text('Details', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-due-date-field'),
                      controller: _dueDateController,
                      decoration: InputDecoration(
                        labelText: 'Due date',
                        hintText: 'YYYY-MM-DD',
                        errorText: _dueDateError,
                        prefixIcon: const Icon(Icons.calendar_today),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_dueDateError != null) {
                          setState(() => _dueDateError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-progress-field'),
                      controller: _progressController,
                      decoration: InputDecoration(
                        labelText: 'Progress %',
                        hintText: '0-100',
                        errorText: _progressError,
                        prefixIcon: const Icon(Icons.percent),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_progressError != null) {
                          setState(() => _progressError = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      key: ValueKey('${widget.keyPrefix}-pinned-switch'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      value: _isPinned,
                      onChanged: (value) => setState(() => _isPinned = value),
                      title: const Text('Pinned'),
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      key: ValueKey('${widget.keyPrefix}-archived-switch'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      value: _isArchived,
                      onChanged: (value) => setState(() => _isArchived = value),
                      title: const Text('Archived'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: ValueKey('${widget.keyPrefix}-related-ids-field'),
                controller: _relatedNodeIdsController,
                decoration: const InputDecoration(
                  labelText: 'Related node IDs',
                  hintText: 'node-a, node-b',
                  prefixIcon: Icon(Icons.link),
                ),
                minLines: 1,
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'Node Specific Details',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _typeSpecificSection(context),
              if (_hasCalendarPayload) ...[
                const SizedBox(height: 16),
                _calendarPayloadSection(context),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.allowDelete)
          TextButton.icon(
            key: const ValueKey('delete-node'),
            onPressed: () =>
                Navigator.of(context).pop(const EditNodeResult.delete()),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-node'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _applyTemplate(NodeTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _type = template.type;
      _status = template.status;
      _priority = template.priority;
      _titleController.text = template.title;
      _bodyController.text = template.body;
      _projectController.text = template.project;
      _areaController.text = template.area;
      _tagsController.text = template.tags.join(', ');
      _progressController.text = template.progress == 0
          ? ''
          : (template.progress * 100).round().toString();
      _checklistController.text = template.checklist.join('\n');
      _loadTypeSpecificData(template.data);
    });
  }

  void _loadTypeSpecificData(Map<String, Object?> data) {
    _kanbanCardsController.text = KanbanBoard.fromNodeData(
      data,
    ).cards.map((card) => '${card.column.name}: ${card.title}').join('\n');
    final habitData = _sectionData(data, 'habit');
    _habitRecurrence = habitData['recurrence'] as String? ?? 'daily';
    _habitTargetController.text = habitData['target'] as String? ?? '';
    _habitCompletionsController.text = _stringListFromData(
      habitData['completions'],
    ).join('\n');
    final goalData = _sectionData(data, 'goal');
    _goalMilestonesController.text = _stringListFromData(
      goalData['milestones'],
    ).join('\n');
    _goalCompletedMilestonesController.text = _stringListFromData(
      goalData['completedMilestones'],
    ).join('\n');
    _planStepsController.text = _stringListFromData(
      _sectionData(data, 'plan')['steps'],
    ).join('\n');
    _planCompletedStepsController.text = _stringListFromData(
      _sectionData(data, 'plan')['completedSteps'],
    ).join('\n');
    _noteSourceController.text =
        (_sectionData(data, 'note')['source'] as String?) ??
        (_sectionData(data, 'link')['url'] as String?) ??
        '';
    final journalData = _sectionData(data, 'journal');
    _journalMoodController.text = _fieldText(journalData['mood']);
    _journalEnergyController.text = _fieldText(journalData['energy']);
    _journalPromptController.text = journalData['prompt'] as String? ?? '';
    _journalGratitudeController.text = _stringListFromData(
      journalData['gratitude'],
    ).join('\n');
    _journalWeeklyReview = journalData['isWeeklyReview'] == true;
    _journalMonthlyReview = journalData['isMonthlyReview'] == true;

    final payload = calendarNodePayloadFromData(data);
    _hasCalendarPayload = payload != null;
    _calendarKind = payload?.kind;
    _calValueController.text = payload?.value ?? '';
    _calUnitController.text = payload?.unit ?? '';
    _calLocationController.text = payload?.location ?? '';
    _calParticipantsController.text = payload?.participants ?? '';
    _calAttendeesController.text = payload?.attendees ?? '';
    _calAgendaController.text = payload?.agenda ?? '';
    _calDecisionsController.text = payload?.decisions ?? '';
    _calActionsController.text = payload?.actions ?? '';
    _calOptionsController.text = payload?.options ?? '';
    _calSelectedOptionController.text = payload?.selectedOption ?? '';
    _calReasonController.text = payload?.reason ?? '';
    _calRemindAtController.text = payload?.remindAt ?? '';
  }

  static const List<NodeType> _primaryNodeTypes = [
    NodeType.note,
    NodeType.canvas,
    NodeType.image,
    NodeType.task,
    NodeType.link,
    NodeType.kanban,
    NodeType.frame,
    NodeType.swatch,
  ];

  static const List<NodeType> _advancedNodeTypes = [
    NodeType.video,
    NodeType.audio,
  ];

  ChoiceChip _typeChoiceChip(NodeType type) {
    return ChoiceChip(
      key: ValueKey('${widget.keyPrefix}-type-${type.name}'),
      label: Text(type.label),
      selected: _type == type,
      onSelected: (_) {
        setState(() {
          _type = type;
          _selectedTemplateId = null;
        });
      },
    );
  }

  Widget _choiceSection(
    BuildContext context,
    String label,
    List<Widget> choices, {
    bool wrap = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        if (wrap)
          Wrap(spacing: 8, runSpacing: 8, children: choices)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < choices.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  choices[index],
                ],
              ],
            ),
          ),
      ],
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Title is required');
      return;
    }

    final dueDate = _parseDueDate();
    if (_dueDateError != null) return;

    final progress = _parseProgress();
    if (_progressError != null) return;

    final draft = AddNodeDraft(
      type: _type,
      title: title,
      body: _bodyController.text.trim(),
      status: _status,
      priority: _priority,
      project: _projectController.text.trim(),
      area: _areaController.text.trim(),
      tags: _parseTags(),
      dueDate: dueDate,
      progress: progress,
      isPinned: _isPinned,
      isArchived: _isArchived,
      checklist: _type == NodeType.task
          ? _parseChecklist()
          : const <TaskChecklistItem>[],
      relatedNodeIds: _parseRelatedNodeIds(),
      data: _parseTypeSpecificData(),
    );
    if (_isEditing) {
      Navigator.of(context).pop(EditNodeResult.save(draft));
    } else {
      Navigator.of(context).pop(draft);
    }
  }

  Widget _typeSpecificSection(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusElement,
          ),
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: switch (_type) {
          NodeType.empty => const SizedBox.shrink(),
          NodeType.task => TextField(
            key: ValueKey('${widget.keyPrefix}-checklist-field'),
            controller: _checklistController,
            decoration: const InputDecoration(labelText: 'Checklist'),
            minLines: 2,
            maxLines: 4,
          ),
          NodeType.kanban => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KanbanInputSummary(text: _kanbanCardsController.text),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('${widget.keyPrefix}-kanban-cards-field'),
                controller: _kanbanCardsController,
                decoration: const InputDecoration(
                  labelText: 'Cards',
                  hintText: 'todo: Scope\ndoing: Build\ndone: Review',
                  helperText: 'Use todo:/doing:/done: prefixes.',
                ),
                minLines: 3,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
          NodeType.habit => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recurrence', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final recurrence in ['daily', 'weekly', 'monthly'])
                    ChoiceChip(
                      key: ValueKey(
                        '${widget.keyPrefix}-habit-recurrence-$recurrence',
                      ),
                      label: Text(_titleCase(recurrence)),
                      selected: _habitRecurrence == recurrence,
                      onSelected: (_) =>
                          setState(() => _habitRecurrence = recurrence),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('${widget.keyPrefix}-habit-target-field'),
                controller: _habitTargetController,
                decoration: const InputDecoration(labelText: 'Target'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('${widget.keyPrefix}-habit-completions-field'),
                controller: _habitCompletionsController,
                decoration: const InputDecoration(
                  labelText: 'Completions',
                  hintText: 'YYYY-MM-DD per line',
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          NodeType.goal => Column(
            children: [
              TextField(
                key: ValueKey('${widget.keyPrefix}-goal-milestones-field'),
                controller: _goalMilestonesController,
                decoration: const InputDecoration(labelText: 'Milestones'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey(
                  '${widget.keyPrefix}-goal-completed-milestones-field',
                ),
                controller: _goalCompletedMilestonesController,
                decoration: const InputDecoration(
                  labelText: 'Completed milestones',
                ),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          NodeType.plan => Column(
            children: [
              TextField(
                key: ValueKey('${widget.keyPrefix}-plan-steps-field'),
                controller: _planStepsController,
                decoration: const InputDecoration(labelText: 'Steps'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('${widget.keyPrefix}-plan-completed-steps-field'),
                controller: _planCompletedStepsController,
                decoration: const InputDecoration(labelText: 'Completed steps'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
          NodeType.note => TextField(
            key: ValueKey('${widget.keyPrefix}-note-source-field'),
            controller: _noteSourceController,
            decoration: const InputDecoration(labelText: 'Source'),
          ),
          NodeType.journal => Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-journal-mood-field'),
                      controller: _journalMoodController,
                      decoration: const InputDecoration(labelText: 'Mood'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: ValueKey('${widget.keyPrefix}-journal-energy-field'),
                      controller: _journalEnergyController,
                      decoration: const InputDecoration(labelText: 'Energy'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('${widget.keyPrefix}-journal-prompt-field'),
                controller: _journalPromptController,
                decoration: const InputDecoration(labelText: 'Prompt'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: ValueKey('${widget.keyPrefix}-journal-gratitude-field'),
                controller: _journalGratitudeController,
                decoration: const InputDecoration(labelText: 'Gratitude'),
                minLines: 2,
                maxLines: 4,
              ),
              CheckboxListTile(
                key: ValueKey('${widget.keyPrefix}-journal-weekly-review'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Weekly review'),
                value: _journalWeeklyReview,
                onChanged: (value) {
                  setState(() => _journalWeeklyReview = value ?? false);
                },
              ),
              CheckboxListTile(
                key: ValueKey('${widget.keyPrefix}-journal-monthly-review'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Monthly review'),
                value: _journalMonthlyReview,
                onChanged: (value) {
                  setState(() => _journalMonthlyReview = value ?? false);
                },
              ),
            ],
          ),
          NodeType.link => TextField(
            key: ValueKey('${widget.keyPrefix}-link-url-field'),
            controller: _noteSourceController,
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          NodeType.event => const Text(
            'Use Calendar payload fields below for agenda, location, participants, and reminder.',
          ),
          NodeType.decision => const Text(
            'Use Calendar payload fields below for options, selected option, and rationale.',
          ),
          NodeType.resource => TextField(
            key: ValueKey('${widget.keyPrefix}-resource-source-field'),
            controller: _noteSourceController,
            decoration: const InputDecoration(labelText: 'Source / URL'),
          ),
          NodeType.idea => const Text(
            'Capture the spark in the description, then connect it to plans, goals, or resources.',
          ),
          NodeType.question => const Text(
            'Capture the question, context, possible answers, and next follow-up.',
          ),
          NodeType.contact => const Text(
            'Use the description for name, role, channel, and relationship notes.',
          ),
          NodeType.metric => const Text(
            'Use the description for value, unit, cadence, and trend notes.',
          ),
          NodeType.expense => const Text(
            'Use the description for amount, category, date, and budget notes.',
          ),
          NodeType.bookmark => TextField(
            key: ValueKey('${widget.keyPrefix}-bookmark-url-field'),
            controller: _noteSourceController,
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          NodeType.routine => const Text(
            'Use the description for trigger, steps, cadence, and checklist.',
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _calendarPayloadSection(BuildContext context) {
    final payloadKind = _calendarKind ?? CalendarNodeKind.event;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusElement,
          ),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Calendar Details',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove calendar details',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _hasCalendarPayload = false;
                    _calendarKind = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CalendarNodeKind>(
              initialValue: payloadKind,
              decoration: const InputDecoration(labelText: 'Kind'),
              items: [
                for (final kind in CalendarNodeKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (kind) {
                if (kind != null) setState(() => _calendarKind = kind);
              },
            ),
            const SizedBox(height: 12),
            if (payloadKind == CalendarNodeKind.event) ...[
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-location-field'),
                controller: _calLocationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _calParticipantsController,
                decoration: const InputDecoration(labelText: 'Participants'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
            if (payloadKind == CalendarNodeKind.reminder)
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-remind-at-field'),
                controller: _calRemindAtController,
                decoration: const InputDecoration(
                  labelText: 'Remind At',
                  hintText: '14:00 or tomorrow 09:00',
                ),
              ),
            if (payloadKind == CalendarNodeKind.meeting) ...[
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-agenda-field'),
                controller: _calAgendaController,
                decoration: const InputDecoration(labelText: 'Agenda'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-attendees-field'),
                controller: _calAttendeesController,
                decoration: const InputDecoration(
                  labelText: 'Attendees (one per line)',
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _calDecisionsController,
                decoration: const InputDecoration(labelText: 'Decisions'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _calActionsController,
                decoration: const InputDecoration(labelText: 'Action Items'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
            if (payloadKind == CalendarNodeKind.decision) ...[
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-options-field'),
                controller: _calOptionsController,
                decoration: const InputDecoration(
                  labelText: 'Options (one per line)',
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey(
                  '${widget.keyPrefix}-calendar-selected-option-field',
                ),
                controller: _calSelectedOptionController,
                decoration: const InputDecoration(labelText: 'Selected Option'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _calReasonController,
                decoration: const InputDecoration(labelText: 'Reason'),
                minLines: 2,
                maxLines: 4,
              ),
            ],
            if (payloadKind == CalendarNodeKind.metric) ...[
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-value-field'),
                controller: _calValueController,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: ValueKey('${widget.keyPrefix}-calendar-unit-field'),
                controller: _calUnitController,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _parseTags() {
    return _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  List<String> _parseRelatedNodeIds() {
    final seen = <String>{};
    final relatedNodeIds = <String>[];

    for (final nodeId in _relatedNodeIdsController.text.split(
      RegExp(r'[,\n]'),
    )) {
      final value = nodeId.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      relatedNodeIds.add(value);
    }

    return relatedNodeIds;
  }

  DateTime? _parseDueDate() {
    final rawValue = _dueDateController.text.trim();
    if (rawValue.isEmpty) {
      setState(() => _dueDateError = null);
      return null;
    }

    final parsed = DateTime.tryParse(rawValue)?.dateOnly;
    setState(() {
      _dueDateError = parsed == null ? 'Use YYYY-MM-DD' : null;
    });
    return parsed;
  }

  double _parseProgress() {
    final rawValue = _progressController.text.trim().replaceAll('%', '');
    if (rawValue.isEmpty) {
      setState(() => _progressError = null);
      return 0;
    }

    final parsed = double.tryParse(rawValue.replaceAll(',', '.'));
    setState(() {
      _progressError = parsed == null ? 'Use a number' : null;
    });
    if (parsed == null) return 0;
    return parsed > 1 ? parsed / 100 : parsed;
  }

  List<TaskChecklistItem> _parseChecklist() {
    final existingByTitle = {
      for (final item in widget.node?.checklist ?? const <TaskChecklistItem>[])
        item.title.trim().toLowerCase(): item,
    };
    final lines = _checklistController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    return [
      for (var index = 0; index < lines.length; index++)
        existingByTitle[lines[index].toLowerCase()]?.copyWith(
              title: lines[index],
            ) ??
            TaskChecklistItem(id: 'item-${index + 1}', title: lines[index]),
    ];
  }

  Map<String, Object?> _parseTypeSpecificData() {
    final Map<String, Object?> data = switch (_type) {
      NodeType.task => const <String, Object?>{},
      NodeType.kanban => _parseKanbanData(),
      NodeType.habit => {
        'habit': {
          'recurrence': _habitRecurrence,
          'target': _habitTargetController.text.trim(),
          'completions': _parseDateKeys(_habitCompletionsController.text),
        },
      },
      NodeType.goal => {
        'goal': {
          'milestones': _parseLines(_goalMilestonesController.text),
          'completedMilestones': _parseLines(
            _goalCompletedMilestonesController.text,
          ),
        },
      },
      NodeType.plan => {
        'plan': {
          'steps': _parseLines(_planStepsController.text),
          'completedSteps': _parseLines(_planCompletedStepsController.text),
        },
      },
      NodeType.note => {
        'note': {'source': _noteSourceController.text.trim()},
      },
      NodeType.journal => {
        'journal': {
          'mood': _parseRating(_journalMoodController.text),
          'energy': _parseRating(_journalEnergyController.text),
          'prompt': _journalPromptController.text.trim(),
          'gratitude': _parseLines(_journalGratitudeController.text),
          'isWeeklyReview': _journalWeeklyReview,
          if (_journalMonthlyReview) 'isMonthlyReview': true,
        },
      },
      NodeType.link => {
        'link': {'url': _noteSourceController.text.trim()},
      },
      NodeType.event => const <String, Object?>{},
      NodeType.decision => const <String, Object?>{},
      NodeType.resource => {
        'note': {'source': _noteSourceController.text.trim()},
      },
      NodeType.idea => const <String, Object?>{},
      NodeType.question => const <String, Object?>{},
      NodeType.contact => const <String, Object?>{},
      NodeType.metric => const <String, Object?>{},
      NodeType.expense => const <String, Object?>{},
      NodeType.bookmark => {
        'link': {'url': _noteSourceController.text.trim()},
      },
      NodeType.routine => const <String, Object?>{},
      NodeType.empty => const <String, Object?>{},
      _ => const <String, Object?>{},
    };
    return {...data, ..._parseCalendarPayloadData()};
  }

  Map<String, Object?> _parseCalendarPayloadData() {
    if (!_hasCalendarPayload || _calendarKind == null) return const {};
    return CalendarNodePayload(
      kind: _calendarKind!,
      value: _calValueController.text.trim(),
      unit: _calUnitController.text.trim(),
      location: _calLocationController.text.trim(),
      participants: _calParticipantsController.text.trim(),
      attendees: _calAttendeesController.text.trim(),
      agenda: _calAgendaController.text.trim(),
      decisions: _calDecisionsController.text.trim(),
      actions: _calActionsController.text.trim(),
      options: _calOptionsController.text.trim(),
      selectedOption: _calSelectedOptionController.text.trim(),
      reason: _calReasonController.text.trim(),
      remindAt: _calRemindAtController.text.trim(),
    ).toJson();
  }

  Map<String, Object?> _parseKanbanData() {
    final existingByTitle = {
      for (final card in KanbanBoard.fromNodeData(
        widget.node?.data ?? const {},
      ).cards)
        card.title.trim().toLowerCase(): card,
    };
    final cards = <KanbanCard>[];
    var index = 0;
    for (final rawLine in _kanbanCardsController.text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(':');
      final prefix = separator > 0 ? line.substring(0, separator).trim() : '';
      final title = separator > 0 ? line.substring(separator + 1).trim() : line;
      if (title.isEmpty) continue;
      final column = KanbanColumn.fromName(prefix);
      cards.add(
        existingByTitle[title.toLowerCase()]?.copyWith(
              title: title,
              column: column,
            ) ??
            KanbanCard(id: 'card-${++index}', title: title, column: column),
      );
    }

    return {'kanban': KanbanBoard(cards: cards).toJson()};
  }
}

class _KanbanInputSummary extends StatelessWidget {
  const _KanbanInputSummary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final counts = _kanbanInputCounts(text);
    final todo = counts[KanbanColumn.todo] ?? 0;
    final doing = counts[KanbanColumn.doing] ?? 0;
    final done = counts[KanbanColumn.done] ?? 0;
    final total = todo + doing + done;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        Chip(
          avatar: const Icon(Icons.view_kanban_outlined, size: 16),
          label: Text('Cards $total'),
          visualDensity: VisualDensity.compact,
        ),
        Chip(label: Text('Todo $todo'), visualDensity: VisualDensity.compact),
        Chip(label: Text('Doing $doing'), visualDensity: VisualDensity.compact),
        Chip(label: Text('Done $done'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

Map<KanbanColumn, int> _kanbanInputCounts(String text) {
  final counts = <KanbanColumn, int>{
    KanbanColumn.todo: 0,
    KanbanColumn.doing: 0,
    KanbanColumn.done: 0,
  };
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf(':');
    final prefix = separator > 0 ? line.substring(0, separator).trim() : '';
    final title = separator > 0 ? line.substring(separator + 1).trim() : line;
    if (title.isEmpty) continue;
    final column = KanbanColumn.fromName(prefix);
    counts[column] = (counts[column] ?? 0) + 1;
  }
  return counts;
}

Map<String, Object?> _sectionData(Map<String, Object?> data, String key) {
  final section = data[key];
  if (section is Map) return section.cast<String, Object?>();
  return const {};
}

List<String> _stringListFromData(Object? value) {
  if (value is! List) return const [];
  return _parseLines(
    [
      for (final item in value)
        if (item is String) item,
    ].join('\n'),
  );
}

List<String> _parseLines(String value) {
  return value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

List<String> _parseDateKeys(String value) {
  final seen = <String>{};
  final keys = <String>[];
  for (final rawValue in value.split(RegExp(r'[,\n]'))) {
    final parsed = DateTime.tryParse(rawValue.trim())?.dateOnly;
    if (parsed == null) continue;
    final key = dayKey(parsed);
    if (seen.add(key)) keys.add(key);
  }
  return keys;
}

int _parseRating(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null) return 0;
  return parsed.clamp(1, 5);
}

String _fieldText(Object? value) {
  if (value == null) return '';
  return value.toString();
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
