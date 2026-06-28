import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../application/mindmap_providers.dart';
import '../domain/canvas_position.dart';
import '../domain/kanban_board.dart';
import '../domain/mindmap_node.dart';
import 'mindmap_canvas.dart'; // for nodeIcon, nodeColor

class NodeEditorPanel extends ConsumerStatefulWidget {
  const NodeEditorPanel({
    super.key,
    required this.node,
    required this.onSave,
    required this.onClose,
    required this.onDelete,
    this.onCollapse,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onSave;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback? onCollapse;

  @override
  ConsumerState<NodeEditorPanel> createState() => _NodeEditorPanelState();
}

class _NodeEditorPanelState extends ConsumerState<NodeEditorPanel> {
  late MindmapNode _draft;

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _projectController = TextEditingController();
  final _areaController = TextEditingController();
  final _tagsController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _progressController = TextEditingController();
  final _relatedNodeIdsController = TextEditingController();

  // Feature controllers
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
  final _timeBlockStartController = TextEditingController();
  final _timeBlockEndController = TextEditingController();

  // Calendar payload controllers
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

  String _habitRecurrence = 'daily';
  bool _journalWeeklyReview = false;
  bool _journalMonthlyReview = false;

  // Calendar payload state
  bool _hasCalendarPayload = false;
  CalendarNodeKind? _calendarKind;

  String? _titleError;
  String? _dateError;
  String? _progressError;
  String? _autocompleteQuery;

  // Active features
  bool _hasChecklist = false;
  bool _hasDueDate = false;
  bool _hasTags = false;
  bool _hasContext = false; // Project/Area
  bool _hasProgress = false;
  bool _hasKanban = false;
  bool _hasHabit = false;
  bool _hasGoal = false;
  bool _hasPlan = false;
  bool _hasJournal = false;
  bool _hasNote = false;
  bool _hasLink = false;
  bool _hasTimeBlock = false;

  @override
  void initState() {
    super.initState();
    _initDraft(widget.node);
    _bodyController.addListener(_onBodyChanged);
  }

  @override
  void didUpdateWidget(NodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _initDraft(widget.node);
    }
  }

  void _initDraft(MindmapNode node) {
    _draft = node;
    _titleController.text = node.title;
    _bodyController.text = node.body;
    _projectController.text = node.project;
    _areaController.text = node.area;
    _tagsController.text = node.tags.join(', ');
    _dueDateController.text = node.dueDate == null ? '' : dayKey(node.dueDate!);
    _progressController.text = node.progress == 0
        ? ''
        : (node.progress * 100).round().toString();
    _relatedNodeIdsController.text = node.relatedNodeIds.join(', ');

    _hasChecklist = node.checklist.isNotEmpty;
    _hasDueDate = node.dueDate != null;
    _hasTags = node.tags.isNotEmpty;
    _hasContext = node.project.isNotEmpty || node.area.isNotEmpty;
    _hasProgress = node.progress > 0;

    final data = node.data;
    _hasKanban = data.containsKey('kanban') || node.type == NodeType.kanban;
    _hasHabit = data.containsKey('habit') || node.type == NodeType.habit;
    _hasGoal = data.containsKey('goal') || node.type == NodeType.goal;
    _hasPlan = data.containsKey('plan') || node.type == NodeType.plan;
    _hasJournal = data.containsKey('journal') || node.type == NodeType.journal;
    _hasNote = data.containsKey('note') || node.type == NodeType.note;
    _hasLink = data.containsKey('link') || node.type == NodeType.link;
    _hasTimeBlock = data.containsKey('time_block');

    final payload = calendarNodePayloadFromData(data);
    _hasCalendarPayload = payload != null;
    _calendarKind = payload?.kind;
    if (payload != null) {
      _calValueController.text = payload.value ?? '';
      _calUnitController.text = payload.unit ?? '';
      _calLocationController.text = payload.location ?? '';
      _calParticipantsController.text = payload.participants ?? '';
      _calAttendeesController.text = payload.attendees ?? '';
      _calAgendaController.text = payload.agenda ?? '';
      _calDecisionsController.text = payload.decisions ?? '';
      _calActionsController.text = payload.actions ?? '';
      _calOptionsController.text = payload.options ?? '';
      _calSelectedOptionController.text = payload.selectedOption ?? '';
      _calReasonController.text = payload.reason ?? '';
      _calRemindAtController.text = payload.remindAt ?? '';
    }

    _checklistController.text = node.checklist
        .map((item) => item.title)
        .join('\n');
    _loadTypeSpecificData(data);
  }

  void _loadTypeSpecificData(Map<String, Object?> data) {
    if (data['kanban'] is Map) {
      final board = KanbanBoard.fromJson(
        data['kanban'] as Map<String, Object?>,
      );
      _kanbanCardsController.text = board.cards.map((c) => c.title).join('\n');
    }
    if (data['habit'] is Map) {
      final habitData = data['habit'] as Map;
      _habitRecurrence = habitData['recurrence'] as String? ?? 'daily';
      _habitTargetController.text = habitData['target'] as String? ?? '';
      // Completions are managed through the app, not manually edited.
      // Leave the field empty so users don't see raw date strings.
    }
    if (data['goal'] is Map) {
      final goalData = data['goal'] as Map;
      final milestones = goalData['milestones'];
      if (milestones is List) {
        _goalMilestonesController.text = milestones.join('\n');
      }
      final completed = goalData['completedMilestones'];
      if (completed is List) {
        _goalCompletedMilestonesController.text = completed.join('\n');
      }
    }
    if (data['plan'] is Map) {
      final planData = data['plan'] as Map;
      final steps = planData['steps'];
      if (steps is List) _planStepsController.text = steps.join('\n');
      final completed = planData['completedSteps'];
      if (completed is List) {
        _planCompletedStepsController.text = completed.join('\n');
      }
    }
    if (data['note'] is Map) {
      _noteSourceController.text =
          (data['note'] as Map)['source'] as String? ?? '';
    }
    if (data['journal'] is Map) {
      final journalData = data['journal'] as Map;
      _journalMoodController.text = journalData['mood']?.toString() ?? '';
      _journalEnergyController.text = journalData['energy']?.toString() ?? '';
      _journalPromptController.text = journalData['prompt'] as String? ?? '';
      final gratitudes = journalData['gratitude'];
      if (gratitudes is List) {
        _journalGratitudeController.text = gratitudes.join('\n');
      }
      _journalWeeklyReview = journalData['isWeeklyReview'] as bool? ?? false;
      _journalMonthlyReview = journalData['isMonthlyReview'] as bool? ?? false;
    }
    if (data['link'] is Map) {
      _noteSourceController.text =
          (data['link'] as Map)['url'] as String? ?? '';
    }
    if (data['time_block'] is Map) {
      final tb = data['time_block'] as Map;
      _timeBlockStartController.text = tb['startTime'] as String? ?? '';
      _timeBlockEndController.text = tb['endTime'] as String? ?? '';
    } else {
      _timeBlockStartController.text = '';
      _timeBlockEndController.text = '';
    }
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _projectController.dispose();
    _areaController.dispose();
    _timeBlockStartController.dispose();
    _timeBlockEndController.dispose();
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
    super.dispose();
  }

  void _onBodyChanged() {
    final query = _getAutocompleteQuery(_bodyController);
    if (query != _autocompleteQuery) {
      setState(() {
        _autocompleteQuery = query;
      });
    }
  }

  String? _getAutocompleteQuery(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid || selection.baseOffset != selection.extentOffset) {
      return null;
    }
    final cursor = selection.baseOffset;
    final lastOpen = text.substring(0, cursor).lastIndexOf('[[');
    if (lastOpen == -1) return null;

    final substring = text.substring(lastOpen, cursor);
    if (substring.contains(']]')) return null;

    return substring.substring(2);
  }

  void _insertAutocomplete(String nodeTitle) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final cursor = selection.baseOffset;
    final lastOpen = text.substring(0, cursor).lastIndexOf('[[');
    if (lastOpen == -1) return;

    final newText = text.replaceRange(lastOpen, cursor, '[[$nodeTitle]]');

    _bodyController.removeListener(_onBodyChanged);
    _bodyController.text = newText;

    final newCursorPos = lastOpen + nodeTitle.length + 4;
    _bodyController.selection = TextSelection.collapsed(offset: newCursorPos);
    _bodyController.addListener(_onBodyChanged);

    setState(() {
      _autocompleteQuery = null;
    });
  }

  Widget _buildAutocompleteSuggestions() {
    if (_autocompleteQuery == null) return const SizedBox.shrink();

    final allNodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? [];
    final query = _autocompleteQuery!.trim().toLowerCase();

    final suggestions = allNodes
        .where(
          (node) =>
              node.id != _draft.id &&
              !node.isArchived &&
              node.title.trim().toLowerCase().contains(query),
        )
        .take(5)
        .toList();

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Link to Node',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          if (suggestions.isEmpty && query.isNotEmpty)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.add,
                color: theme.colorScheme.primary,
                size: 18,
              ),
              title: Text(
                'Create node "$_autocompleteQuery"',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: () => _insertAutocomplete(_autocompleteQuery!.trim()),
            )
          else if (suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Type to search nodes...',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else ...[
            for (final node in suggestions)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  nodeIcon(node.type),
                  size: 18,
                  color: nodeColor(node.type),
                ),
                title: Text(node.title),
                subtitle: node.project.isNotEmpty || node.area.isNotEmpty
                    ? Text(
                        '${node.project.isNotEmpty ? 'Project: ${node.project}' : ''}${node.project.isNotEmpty && node.area.isNotEmpty ? ' | ' : ''}${node.area.isNotEmpty ? 'Area: ${node.area}' : ''}',
                        style: const TextStyle(fontSize: 10),
                      )
                    : null,
                onTap: () => _insertAutocomplete(node.title),
              ),
            if (query.isNotEmpty &&
                !suggestions.any((n) => n.title.trim().toLowerCase() == query))
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.add,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
                title: Text(
                  'Create node "$_autocompleteQuery"',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                onTap: () => _insertAutocomplete(_autocompleteQuery!.trim()),
              ),
          ],
        ],
      ),
    );
  }

  void _save() async {
    final title = _titleController.text.trim();
    setState(() {
      _titleError = null;
      _dateError = null;
      _progressError = null;
    });
    if (title.isEmpty) {
      setState(() => _titleError = 'Title is required');
      return;
    }

    // Validate date format
    if (_hasDueDate && _dueDateController.text.trim().isNotEmpty) {
      final parsed = _parseDate(_dueDateController.text);
      if (parsed == null) {
        setState(() => _dateError = 'Invalid date format. Use YYYY-MM-DD');
        return;
      }
    }

    // Validate progress
    if (_hasProgress && _progressController.text.trim().isNotEmpty) {
      final progressVal = double.tryParse(_progressController.text);
      if (progressVal == null || progressVal < 0 || progressVal > 100) {
        setState(() => _progressError = 'Enter a number between 0 and 100');
        return;
      }
    }

    final dueDate = _hasDueDate ? _parseDate(_dueDateController.text) : null;
    final progress = _hasProgress
        ? (double.tryParse(_progressController.text) ?? 0) / 100
        : 0.0;

    final body = _bodyController.text.trim();
    final allNodes = ref.read(allMindmapNodesProvider).valueOrNull ?? [];
    final repository = ref.read(mindmapRepositoryProvider);

    // 1. Parse referenced titles [[NodeTitle]]
    final matches = RegExp(r'\[\[(.*?)\]\]').allMatches(body);
    final referencedTitles = matches
        .map((m) => m.group(1)!.trim())
        .where((t) => t.isNotEmpty)
        .toSet();

    final parsedLinkIds = <String>{};
    for (final refTitle in referencedTitles) {
      final matchingNode = allNodes.firstWhereOrNull(
        (n) => n.title.trim().toLowerCase() == refTitle.toLowerCase(),
      );

      if (matchingNode == null) {
        final newId =
            'node-${DateTime.now().millisecondsSinceEpoch}-${refTitle.hashCode}';
        final placeholder = MindmapNode(
          id: newId,
          type: NodeType.note,
          title: refTitle,
          day: _draft.day,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          body: 'Created automatically via bidirectional link from [[$title]].',
          position: CanvasPosition(
            _draft.position.dx + 120,
            _draft.position.dy + 120,
          ),
        );
        await repository.saveNode(placeholder);
        parsedLinkIds.add(placeholder.id);
      } else {
        parsedLinkIds.add(matchingNode.id);
      }
    }

    // 2. Sync relatedNodeIds
    final finalRelatedNodeIds = <String>{...parsedLinkIds};
    for (final id in _draft.relatedNodeIds) {
      final node = allNodes.firstWhereOrNull((n) => n.id == id);
      if (node != null) {
        final oldMatches = RegExp(r'\[\[(.*?)\]\]').allMatches(_draft.body);
        final oldReferencedTitles = oldMatches
            .map((m) => m.group(1)!.trim().toLowerCase())
            .toSet();

        final wasTextLink = oldReferencedTitles.contains(
          node.title.trim().toLowerCase(),
        );
        if (!wasTextLink) {
          finalRelatedNodeIds.add(id);
        }
      } else {
        finalRelatedNodeIds.add(id);
      }
    }

    final updatedData = <String, Object?>{..._draft.data};

    if (_hasKanban) {
      final existingByTitle = {
        for (final card in KanbanBoard.fromNodeData(_draft.data).cards)
          card.title.trim().toLowerCase(): card,
      };
      final lines = _parseLines(_kanbanCardsController.text);
      updatedData['kanban'] = KanbanBoard(
        cards: [
          for (var index = 0; index < lines.length; index++)
            existingByTitle[lines[index].toLowerCase()]?.copyWith(
                  title: lines[index],
                ) ??
                KanbanCard(id: 'card-${index + 1}', title: lines[index]),
        ],
      ).toJson();
    } else {
      updatedData.remove('kanban');
    }

    if (_hasHabit) {
      updatedData['habit'] = {
        'recurrence': _habitRecurrence,
        'target': _habitTargetController.text.trim(),
        'completions': _parseLines(_habitCompletionsController.text),
      };
    } else {
      updatedData.remove('habit');
    }

    if (_hasGoal) {
      updatedData['goal'] = {
        'milestones': _parseLines(_goalMilestonesController.text),
        'completedMilestones': _parseLines(
          _goalCompletedMilestonesController.text,
        ),
      };
    } else {
      updatedData.remove('goal');
    }

    if (_hasPlan) {
      updatedData['plan'] = {
        'steps': _parseLines(_planStepsController.text),
        'completedSteps': _parseLines(_planCompletedStepsController.text),
      };
    } else {
      updatedData.remove('plan');
    }

    if (_hasNote) {
      updatedData['note'] = {'source': _noteSourceController.text.trim()};
    } else {
      updatedData.remove('note');
    }

    if (_hasLink) {
      updatedData['link'] = {'url': _noteSourceController.text.trim()};
    } else {
      updatedData.remove('link');
    }

    if (_hasJournal) {
      updatedData['journal'] = {
        'mood': _journalMoodController.text.isNotEmpty
            ? int.tryParse(_journalMoodController.text)
            : null,
        'energy': _journalEnergyController.text.isNotEmpty
            ? int.tryParse(_journalEnergyController.text)
            : null,
        'prompt': _journalPromptController.text.trim(),
        'gratitude': _parseLines(_journalGratitudeController.text),
        'isWeeklyReview': _journalWeeklyReview,
        if (_journalMonthlyReview) 'isMonthlyReview': true,
      };
    } else {
      updatedData.remove('journal');
    }

    if (_hasTimeBlock) {
      updatedData['time_block'] = {
        'startTime': _timeBlockStartController.text.trim(),
        'endTime': _timeBlockEndController.text.trim(),
      };
    } else {
      updatedData.remove('time_block');
    }

    if (_hasCalendarPayload) {
      updatedData.addAll(_buildCalendarPayloadData());
    } else {
      updatedData.remove('calendar_kind');
      updatedData.remove('calendarKind');
    }

    final savedNode = MindmapNode(
      id: _draft.id,
      type: _draft.type,
      title: title,
      day: _draft.day,
      createdAt: _draft.createdAt,
      updatedAt: DateTime.now(),
      body: body,
      position: _draft.position,
      isDone: _draft.isDone,
      status: _draft.status,
      priority: _draft.priority,
      project: _hasContext ? _projectController.text.trim() : '',
      area: _hasContext ? _areaController.text.trim() : '',
      tags: _hasTags
          ? _parseLines(_tagsController.text.replaceAll(',', '\n'))
          : const [],
      dueDate: dueDate,
      progress: progress,
      isPinned: _draft.isPinned,
      isArchived: _draft.isArchived,
      checklist: _hasChecklist ? _parseChecklist() : const [],
      relatedNodeIds: finalRelatedNodeIds.toList(),
      data: updatedData,
    );

    widget.onSave(savedNode);
  }

  Map<String, Object?> _buildCalendarPayloadData() {
    if (!_hasCalendarPayload || _calendarKind == null) return {};
    final payload = CalendarNodePayload(
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
    );
    return payload.toJson();
  }

  List<String> _parseLines(String text) {
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  DateTime? _parseDate(String text) {
    return DateTime.tryParse(text.trim());
  }

  List<TaskChecklistItem> _parseChecklist() {
    final existingByTitle = {
      for (final item in _draft.checklist)
        item.title.trim().toLowerCase(): item,
    };
    final lines = _parseLines(_checklistController.text);
    return [
      for (var index = 0; index < lines.length; index++)
        existingByTitle[lines[index].toLowerCase()]?.copyWith(
              title: lines[index],
            ) ??
            TaskChecklistItem(id: 'item-${index + 1}', title: lines[index]),
    ];
  }

  Widget _buildFeatureMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Add Feature',
      icon: const Icon(Icons.add_circle_outline),
      onSelected: (feature) {
        setState(() {
          switch (feature) {
            case 'checklist':
              _hasChecklist = true;
            case 'dueDate':
              _hasDueDate = true;
            case 'tags':
              _hasTags = true;
            case 'context':
              _hasContext = true;
            case 'progress':
              _hasProgress = true;
            case 'kanban':
              _hasKanban = true;
            case 'habit':
              _hasHabit = true;
            case 'goal':
              _hasGoal = true;
            case 'plan':
              _hasPlan = true;
            case 'journal':
              _hasJournal = true;
            case 'note':
              _hasNote = true;
            case 'link':
              _hasLink = true;
            case 'timeBlock':
              _hasTimeBlock = true;
            case 'calendarPayload':
              _hasCalendarPayload = true;
              _calendarKind ??= CalendarNodeKind.event;
          }
        });
      },
      itemBuilder: (context) => [
        if (!_hasChecklist)
          const PopupMenuItem(value: 'checklist', child: Text('Checklist')),
        if (!_hasDueDate)
          const PopupMenuItem(value: 'dueDate', child: Text('Due Date')),
        if (!_hasTags) const PopupMenuItem(value: 'tags', child: Text('Tags')),
        if (!_hasContext)
          const PopupMenuItem(value: 'context', child: Text('Project/Area')),
        if (!_hasProgress)
          const PopupMenuItem(value: 'progress', child: Text('Progress')),
        if (!_hasKanban)
          const PopupMenuItem(value: 'kanban', child: Text('Kanban Board')),
        if (!_hasHabit)
          const PopupMenuItem(value: 'habit', child: Text('Habit Tracker')),
        if (!_hasGoal)
          const PopupMenuItem(value: 'goal', child: Text('Goal Milestones')),
        if (!_hasPlan)
          const PopupMenuItem(value: 'plan', child: Text('Plan Steps')),
        if (!_hasJournal)
          const PopupMenuItem(value: 'journal', child: Text('Journal Entry')),
        if (!_hasNote)
          const PopupMenuItem(value: 'note', child: Text('Note Source')),
        if (!_hasLink)
          const PopupMenuItem(value: 'link', child: Text('Link URL')),
        if (!_hasTimeBlock)
          const PopupMenuItem(value: 'timeBlock', child: Text('Time Block')),
        if (!_hasCalendarPayload)
          const PopupMenuItem(
            value: 'calendarPayload',
            child: Text('Calendar'),
          ),
      ],
    );
  }

  Widget _buildFeatureField({
    required String title,
    required Widget child,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                tooltip: 'Remove $title',
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildCalendarPayloadSection() {
    final payloadKind = _calendarKind ?? CalendarNodeKind.event;
    return _buildFeatureField(
      title: 'Calendar: ${payloadKind.label}',
      onRemove: () => setState(() {
        _hasCalendarPayload = false;
        _calendarKind = null;
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<CalendarNodeKind>(
            initialValue: payloadKind,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: CalendarNodeKind.values.map((k) {
              return DropdownMenuItem(value: k, child: Text(k.label));
            }).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _calendarKind = v);
            },
          ),
          const SizedBox(height: 8),
          if (payloadKind == CalendarNodeKind.metric) ...[
            TextField(
              controller: _calValueController,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calUnitController,
              decoration: const InputDecoration(
                labelText: 'Unit',
                hintText: 'e.g. h, kg',
              ),
            ),
          ],
          if (payloadKind == CalendarNodeKind.event) ...[
            TextField(
              controller: _calValueController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            TextField(
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
          if (payloadKind == CalendarNodeKind.reminder) ...[
            TextField(
              controller: _calRemindAtController,
              decoration: const InputDecoration(
                labelText: 'Remind At',
                hintText: 'e.g. 14:00 or tomorrow 09:00',
              ),
            ),
          ],
          if (payloadKind == CalendarNodeKind.meeting) ...[
            TextField(
              controller: _calAgendaController,
              decoration: const InputDecoration(labelText: 'Agenda'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calAttendeesController,
              decoration: const InputDecoration(
                labelText: 'Attendees (one per line)',
              ),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calDecisionsController,
              decoration: const InputDecoration(labelText: 'Decisions'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calActionsController,
              decoration: const InputDecoration(labelText: 'Action Items'),
              minLines: 2,
              maxLines: 5,
            ),
          ],
          if (payloadKind == CalendarNodeKind.decision) ...[
            TextField(
              controller: _calOptionsController,
              decoration: const InputDecoration(
                labelText: 'Options (one per line)',
              ),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calSelectedOptionController,
              decoration: const InputDecoration(labelText: 'Selected Option'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calReasonController,
              decoration: const InputDecoration(labelText: 'Reason'),
              minLines: 2,
              maxLines: 5,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(nodeIcon(_draft.type), color: nodeColor(_draft.type)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Edit Node', style: theme.textTheme.titleMedium),
              ),
              _buildFeatureMenu(),
              IconButton(
                key: const ValueKey('delete-node'),
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.error,
                tooltip: 'Delete',
                onPressed: widget.onDelete,
              ),
              if (widget.onCollapse != null)
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Collapse',
                  onPressed: widget.onCollapse,
                ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<NodeType>(
                  key: const ValueKey('node-editor-type-dropdown'),
                  initialValue: _draft.type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: NodeType.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.label));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _draft = MindmapNode(
                          id: _draft.id,
                          type: v,
                          title: _draft.title,
                          day: _draft.day,
                          createdAt: _draft.createdAt,
                          updatedAt: _draft.updatedAt,
                          body: _draft.body,
                          position: _draft.position,
                          isDone: _draft.isDone,
                          status: _draft.status,
                          priority: _draft.priority,
                          project: _draft.project,
                          area: _draft.area,
                          tags: _draft.tags,
                          dueDate: _draft.dueDate,
                          progress: _draft.progress,
                          isPinned: _draft.isPinned,
                          isArchived: _draft.isArchived,
                          checklist: _draft.checklist,
                          relatedNodeIds: _draft.relatedNodeIds,
                          data: _draft.data,
                        );
                        if (v == NodeType.kanban) _hasKanban = true;
                        if (v == NodeType.habit) _hasHabit = true;
                        if (v == NodeType.goal) _hasGoal = true;
                        if (v == NodeType.plan) _hasPlan = true;
                        if (v == NodeType.journal) _hasJournal = true;
                        if (v == NodeType.note) _hasNote = true;
                        if (v == NodeType.link) _hasLink = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('node-editor-title-field'),
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    errorText: _titleError,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('node-editor-body-field'),
                  controller: _bodyController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 3,
                  maxLines: 8,
                ),
                _buildAutocompleteSuggestions(),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<NodeStatus>(
                        key: const ValueKey('node-editor-status-dropdown'),
                        initialValue: _draft.status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: NodeStatus.values
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(
                              () => _draft = MindmapNode(
                                id: _draft.id,
                                type: _draft.type,
                                title: _draft.title,
                                day: _draft.day,
                                createdAt: _draft.createdAt,
                                updatedAt: _draft.updatedAt,
                                body: _draft.body,
                                position: _draft.position,
                                isDone: _draft.isDone,
                                status: v,
                                priority: _draft.priority,
                                project: _draft.project,
                                area: _draft.area,
                                tags: _draft.tags,
                                dueDate: _draft.dueDate,
                                progress: _draft.progress,
                                isPinned: _draft.isPinned,
                                isArchived: _draft.isArchived,
                                checklist: _draft.checklist,
                                relatedNodeIds: _draft.relatedNodeIds,
                                data: _draft.data,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<NodePriority>(
                        key: const ValueKey('node-editor-priority-dropdown'),
                        initialValue: _draft.priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                        ),
                        items: NodePriority.values
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(
                              () => _draft = MindmapNode(
                                id: _draft.id,
                                type: _draft.type,
                                title: _draft.title,
                                day: _draft.day,
                                createdAt: _draft.createdAt,
                                updatedAt: _draft.updatedAt,
                                body: _draft.body,
                                position: _draft.position,
                                isDone: _draft.isDone,
                                status: _draft.status,
                                priority: v,
                                project: _draft.project,
                                area: _draft.area,
                                tags: _draft.tags,
                                dueDate: _draft.dueDate,
                                progress: _draft.progress,
                                isPinned: _draft.isPinned,
                                isArchived: _draft.isArchived,
                                checklist: _draft.checklist,
                                relatedNodeIds: _draft.relatedNodeIds,
                                data: _draft.data,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (_hasChecklist ||
                    _hasDueDate ||
                    _hasTags ||
                    _hasContext ||
                    _hasProgress ||
                    _hasKanban ||
                    _hasHabit ||
                    _hasGoal ||
                    _hasPlan ||
                    _hasJournal ||
                    _hasNote ||
                    _hasLink ||
                    _hasTimeBlock ||
                    _hasCalendarPayload) ...[
                  Text('Active Features', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                ],

                if (_hasChecklist)
                  _buildFeatureField(
                    title: 'Checklist',
                    onRemove: () => setState(() => _hasChecklist = false),
                    child: TextField(
                      key: const ValueKey('node-editor-checklist-field'),
                      controller: _checklistController,
                      decoration: const InputDecoration(
                        hintText: 'One item per line',
                      ),
                      minLines: 2,
                      maxLines: 5,
                    ),
                  ),

                if (_hasDueDate)
                  _buildFeatureField(
                    title: 'Due Date',
                    onRemove: () => setState(() => _hasDueDate = false),
                    child: TextField(
                      key: const ValueKey('node-editor-due-date-field'),
                      controller: _dueDateController,
                      decoration: InputDecoration(
                        hintText: 'YYYY-MM-DD',
                        errorText: _dateError,
                      ),
                    ),
                  ),

                if (_hasTags)
                  _buildFeatureField(
                    title: 'Tags',
                    onRemove: () => setState(() => _hasTags = false),
                    child: TextField(
                      key: const ValueKey('node-editor-tags-field'),
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        hintText: 'Comma separated',
                      ),
                    ),
                  ),

                if (_hasContext)
                  _buildFeatureField(
                    title: 'Project / Area',
                    onRemove: () => setState(() => _hasContext = false),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('node-editor-project-field'),
                            controller: _projectController,
                            decoration: const InputDecoration(
                              labelText: 'Project',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const ValueKey('node-editor-area-field'),
                            controller: _areaController,
                            decoration: const InputDecoration(
                              labelText: 'Area',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_hasProgress)
                  _buildFeatureField(
                    title: 'Progress (%)',
                    onRemove: () => setState(() => _hasProgress = false),
                    child: TextField(
                      key: const ValueKey('node-editor-progress-field'),
                      controller: _progressController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '0-100',
                        errorText: _progressError,
                      ),
                    ),
                  ),

                if (_hasKanban)
                  _buildFeatureField(
                    title: 'Kanban Board',
                    onRemove: () => setState(() => _hasKanban = false),
                    child: TextField(
                      key: const ValueKey('node-editor-kanban-cards-field'),
                      controller: _kanbanCardsController,
                      decoration: const InputDecoration(
                        hintText: 'One card per line',
                      ),
                      minLines: 3,
                      maxLines: 5,
                    ),
                  ),

                if (_hasHabit)
                  _buildFeatureField(
                    title: 'Habit Tracker',
                    onRemove: () => setState(() => _hasHabit = false),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _habitRecurrence,
                          decoration: const InputDecoration(
                            labelText: 'Recurrence',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'weekly',
                              child: Text('Weekly'),
                            ),
                            DropdownMenuItem(
                              value: 'monthly',
                              child: Text('Monthly'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _habitRecurrence = v ?? 'daily'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _habitTargetController,
                          decoration: const InputDecoration(
                            labelText: 'Target (e.g. 30 mins)',
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_hasGoal)
                  _buildFeatureField(
                    title: 'Goal Milestones',
                    onRemove: () => setState(() => _hasGoal = false),
                    child: TextField(
                      key: const ValueKey('node-editor-goal-milestones-field'),
                      controller: _goalMilestonesController,
                      decoration: const InputDecoration(
                        hintText: 'One milestone per line',
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ),

                if (_hasPlan)
                  _buildFeatureField(
                    title: 'Plan Steps',
                    onRemove: () => setState(() => _hasPlan = false),
                    child: TextField(
                      key: const ValueKey('node-editor-plan-steps-field'),
                      controller: _planStepsController,
                      decoration: const InputDecoration(
                        hintText: 'One step per line',
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ),

                if (_hasJournal)
                  _buildFeatureField(
                    title: 'Journal Entry',
                    onRemove: () => setState(() => _hasJournal = false),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _journalMoodController,
                                decoration: const InputDecoration(
                                  labelText: 'Mood (1-10)',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _journalEnergyController,
                                decoration: const InputDecoration(
                                  labelText: 'Energy (1-10)',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _journalPromptController,
                          decoration: const InputDecoration(
                            labelText: 'Prompt',
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_hasNote || _hasLink)
                  _buildFeatureField(
                    title: _hasLink ? 'Link URL' : 'Source',
                    onRemove: () => setState(() {
                      _hasNote = false;
                      _hasLink = false;
                    }),
                    child: TextField(
                      controller: _noteSourceController,
                      decoration: InputDecoration(
                        hintText: _hasLink
                            ? 'https://...'
                            : 'Book, Video, etc.',
                      ),
                    ),
                  ),

                if (_hasTimeBlock)
                  _buildFeatureField(
                    title: 'Time Block',
                    onRemove: () => setState(() => _hasTimeBlock = false),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 9,
                                  minute: 0,
                                ),
                              );
                              if (time != null) {
                                final hh = time.hour.toString().padLeft(2, '0');
                                final mm = time.minute.toString().padLeft(
                                  2,
                                  '0',
                                );
                                _timeBlockStartController.text = '$hh:$mm';
                              }
                            },
                            child: IgnorePointer(
                              child: TextField(
                                controller: _timeBlockStartController,
                                decoration: const InputDecoration(
                                  labelText: 'Start Time',
                                  hintText: 'e.g. 09:00',
                                  prefixIcon: Icon(Icons.access_time),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 10,
                                  minute: 0,
                                ),
                              );
                              if (time != null) {
                                final hh = time.hour.toString().padLeft(2, '0');
                                final mm = time.minute.toString().padLeft(
                                  2,
                                  '0',
                                );
                                _timeBlockEndController.text = '$hh:$mm';
                              }
                            },
                            child: IgnorePointer(
                              child: TextField(
                                controller: _timeBlockEndController,
                                decoration: const InputDecoration(
                                  labelText: 'End Time',
                                  hintText: 'e.g. 10:00',
                                  prefixIcon: Icon(Icons.access_time),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_hasCalendarPayload) _buildCalendarPayloadSection(),
        // Footer (Save button)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('save-node'),
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
            ),
          ),
        ),
      ],
    );
  }
}
