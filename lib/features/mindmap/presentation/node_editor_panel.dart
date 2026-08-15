import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../application/collaboration_controller.dart';
import '../application/mindmap_providers.dart';
import '../domain/automation_rule.dart';
import '../domain/canvas_position.dart';
import '../domain/custom_node_template_codec.dart';
import '../domain/kanban_board.dart';
import '../domain/markdown_checklist_parser.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_knowledge_index.dart';
import '../domain/node_presentation.dart';
import '../domain/node_template.dart';
import '../domain/recurring_routine.dart';
import 'inline_node_workspace.dart';
import 'mindmap_canvas.dart' show compatibleNodeTypeLabel, compatibleNodeTypes;
import 'node_type_inline_editor.dart';
import 'task_decomposition_dialog.dart';

const String _defaultRelationLabel = 'relates to';
const int _defaultBodyMaxWords = 1200;
const List<String> _relationLabelPresets = [
  'relates to',
  'depends on',
  'blocks',
  'supports',
  'part of',
  'references',
  'next action for',
];

class NodeEditorPanel extends ConsumerStatefulWidget {
  const NodeEditorPanel({
    super.key,
    required this.node,
    required this.onSave,
    required this.onClose,
    required this.onDelete,
    this.onCollapse,
    this.onOpenNode,
    this.initialTab = 0,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onSave;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback? onCollapse;
  final ValueChanged<MindmapNode>? onOpenNode;
  final int initialTab;

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
  final _contextTagsController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _progressController = TextEditingController();
  final _relatedNodeIdsController = TextEditingController();
  final _attachmentsController = TextEditingController();

  // Feature controllers
  final _checklistController = TextEditingController();
  final _quickChecklistItemController = TextEditingController();
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
  final _contactRoleController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactCompanyController = TextEditingController();
  final _metricValueController = TextEditingController();
  final _metricUnitController = TextEditingController();
  final _metricTrendController = TextEditingController();
  final _metricTargetController = TextEditingController();
  final _expenseAmountController = TextEditingController();
  final _expenseCategoryController = TextEditingController();
  final _expensePaymentController = TextEditingController();
  final _expenseMerchantController = TextEditingController();

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

  // New node controllers
  final _quoteAuthorController = TextEditingController();
  final _timerSecondsController = TextEditingController();
  final _audioPathController = TextEditingController();
  final _audioDurationController = TextEditingController();
  final _audioTranscriptController = TextEditingController();
  final _weatherTempController = TextEditingController();
  final _weatherConditionController = TextEditingController();
  final _fitStepsController = TextEditingController();
  final _fitWaterController = TextEditingController();
  final _fitWorkoutController = TextEditingController();
  final _fitStepTargetController = TextEditingController();
  final _fitWaterTargetController = TextEditingController();

  String _moodEmoji = '😊';
  double _moodEnergy = 3.0;

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
  String? _slashCommandQuery;
  bool _hasUnsavedChanges = false;
  late _EditorPanelTab _panelTab;
  bool _isHydratingDraft = false;
  bool _isEnforcingBodyLimit = false;
  bool _isSaving = false;
  DateTime? _lastSavedAt;

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
    final initialTabIndex = widget.initialTab.clamp(
      0,
      _EditorPanelTab.values.length - 1,
    );
    _panelTab = _EditorPanelTab.values[initialTabIndex];
    _initDraft(widget.node);
    for (final controller in _dirtyControllers) {
      controller.addListener(_markDirty);
    }
    _bodyController.addListener(_onBodyChanged);

    // Broadcast editing status to remote collaborators
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(collaborationProvider.notifier)
            .updateLocalSelection(widget.node.id, isEditing: true);
      }
    });
  }

  List<TextEditingController> get _dirtyControllers => [
    _titleController,
    _bodyController,
    _projectController,
    _areaController,
    _tagsController,
    _contextTagsController,
    _dueDateController,
    _progressController,
    _relatedNodeIdsController,
    _attachmentsController,
    _checklistController,
    _quickChecklistItemController,
    _kanbanCardsController,
    _habitTargetController,
    _habitCompletionsController,
    _goalMilestonesController,
    _goalCompletedMilestonesController,
    _planStepsController,
    _planCompletedStepsController,
    _noteSourceController,
    _journalMoodController,
    _journalEnergyController,
    _journalPromptController,
    _journalGratitudeController,
    _timeBlockStartController,
    _timeBlockEndController,
    _contactRoleController,
    _contactEmailController,
    _contactPhoneController,
    _contactCompanyController,
    _metricValueController,
    _metricUnitController,
    _metricTrendController,
    _metricTargetController,
    _expenseAmountController,
    _expenseCategoryController,
    _expensePaymentController,
    _expenseMerchantController,
    _calValueController,
    _calUnitController,
    _calLocationController,
    _calParticipantsController,
    _calAttendeesController,
    _calAgendaController,
    _calDecisionsController,
    _calActionsController,
    _calOptionsController,
    _calSelectedOptionController,
    _calReasonController,
    _calRemindAtController,
    _quoteAuthorController,
    _timerSecondsController,
    _audioPathController,
    _audioDurationController,
    _audioTranscriptController,
    _weatherTempController,
    _weatherConditionController,
    _fitStepsController,
    _fitWaterController,
    _fitWorkoutController,
    _fitStepTargetController,
    _fitWaterTargetController,
  ];

  void _markDirty() {
    if (_isHydratingDraft || _hasUnsavedChanges || !mounted) return;
    setState(() => _hasUnsavedChanges = true);
  }

  @override
  void didUpdateWidget(NodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        (!_hasUnsavedChanges && oldWidget.node != widget.node)) {
      _initDraft(widget.node);
    }
  }

  void _initDraft(MindmapNode node) {
    _isHydratingDraft = true;
    _draft = node;
    _titleController.text = node.title;
    _bodyController.text = node.body;
    _projectController.text = node.project;
    _areaController.text = node.area;
    _tagsController.text = node.tags.join(', ');
    _contextTagsController.text = node.contextTags.join(', ');
    _dueDateController.text = node.dueDate == null ? '' : dayKey(node.dueDate!);
    _progressController.text = node.progress == 0
        ? ''
        : (node.progress * 100).round().toString();
    _relatedNodeIdsController.text = node.relatedNodeIds.join(', ');
    _attachmentsController.text = _attachmentsTextFromData(node.data);

    _hasChecklist = node.checklist.isNotEmpty;
    _hasDueDate = node.dueDate != null;
    _hasTags = node.tags.isNotEmpty || node.contextTags.isNotEmpty;
    _hasContext = node.project.isNotEmpty || node.area.isNotEmpty;
    _hasProgress = node.progress > 0;

    final data = node.data;
    _hasKanban = data.containsKey('kanban') || node.type == NodeType.kanban;
    _hasHabit = data.containsKey('habit') || node.type == NodeType.habit;
    _hasGoal = data.containsKey('goal') || node.type == NodeType.goal;
    _hasPlan = data.containsKey('plan') || node.type == NodeType.plan;
    _hasJournal = data.containsKey('journal') || node.type == NodeType.journal;
    _hasNote =
        data.containsKey('note') ||
        node.type == NodeType.note ||
        node.type == NodeType.resource;
    _hasLink =
        data.containsKey('link') ||
        node.type == NodeType.link ||
        node.type == NodeType.bookmark;
    _hasChecklist =
        _hasChecklist ||
        node.type == NodeType.task ||
        node.type == NodeType.routine ||
        node.type == NodeType.question;
    _hasProgress =
        _hasProgress ||
        node.type == NodeType.goal ||
        node.type == NodeType.metric;
    _hasTimeBlock = data.containsKey('time_block');

    _moodEmoji = node.data['mood'] as String? ?? '😊';
    _moodEnergy = (node.data['energy'] as num?)?.toDouble() ?? 3.0;

    _loadStructuredTypeFields(node);

    final payload = calendarNodePayloadFromData(data);
    _hasCalendarPayload =
        payload != null ||
        node.type == NodeType.event ||
        node.type == NodeType.decision;
    _calendarKind = payload?.kind ?? _defaultCalendarKindForType(node.type);
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
    _hasUnsavedChanges = false;
    _isHydratingDraft = false;
  }

  void _loadTypeSpecificData(Map<String, Object?> data) {
    if (data['kanban'] is Map) {
      final board = KanbanBoard.fromJson(
        data['kanban'] as Map<String, Object?>,
      );
      _kanbanCardsController.text = board.cards
          .map((card) => '${card.column.name}: ${card.title}')
          .join('\n');
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

  void _loadStructuredTypeFields(MindmapNode node) {
    final bodyFields = _bodyKeyValues(node.body);
    final data = node.data;
    _contactRoleController.text = _stringFromData(data, 'role', bodyFields);
    _contactEmailController.text = _stringFromData(data, 'email', bodyFields);
    _contactPhoneController.text = _stringFromData(data, 'phone', bodyFields);
    _contactCompanyController.text = _stringFromData(
      data,
      'company',
      bodyFields,
    );
    _metricValueController.text = _stringFromData(data, 'value', bodyFields);
    _metricUnitController.text = _stringFromData(data, 'unit', bodyFields);
    _metricTrendController.text = _stringFromData(data, 'trend', bodyFields);
    _metricTargetController.text = _stringFromData(data, 'target', bodyFields);
    _expenseAmountController.text = _stringFromData(data, 'amount', bodyFields);
    _expenseCategoryController.text = _stringFromData(
      data,
      'category',
      bodyFields,
    );
    _expensePaymentController.text = _stringFromData(
      data,
      'payment',
      bodyFields,
    );
    _expenseMerchantController.text = _stringFromData(
      data,
      'merchant',
      bodyFields,
    );
    _quoteAuthorController.text = _stringFromData(data, 'author', bodyFields);
    _timerSecondsController.text = _stringFromData(
      data,
      'timerSeconds',
      bodyFields,
    );
    _audioPathController.text = _stringFromData(data, 'audioPath', bodyFields);
    _audioDurationController.text = _stringFromData(
      data,
      'audioDuration',
      bodyFields,
    );
    _audioTranscriptController.text = _stringFromData(
      data,
      'audioTranscript',
      bodyFields,
    );
    _weatherTempController.text = _stringFromData(data, 'temp', bodyFields);
    _weatherConditionController.text = _stringFromData(
      data,
      'weather',
      bodyFields,
    );
    _fitStepsController.text = _stringFromData(data, 'steps', bodyFields);
    _fitWaterController.text = _stringFromData(data, 'water', bodyFields);
    _fitWorkoutController.text = _stringFromData(data, 'workout', bodyFields);
    _fitStepTargetController.text = _stringFromData(
      data,
      'stepTarget',
      bodyFields,
    );
    _fitWaterTargetController.text = _stringFromData(
      data,
      'waterTarget',
      bodyFields,
    );
  }

  String _stringFromData(
    Map<String, Object?> data,
    String key,
    Map<String, String> fallback,
  ) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
    return fallback[key] ?? '';
  }

  Map<String, String> _bodyKeyValues(String body) {
    final result = <String, String>{};
    for (final line in body.split('\n')) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) result[key] = value;
    }
    return result;
  }

  @override
  void dispose() {
    // Reset remote collaboration editing state
    try {
      ref
          .read(collaborationProvider.notifier)
          .updateLocalSelection(null, isEditing: false);
    } catch (_) {}

    for (final controller in _dirtyControllers) {
      controller.removeListener(_markDirty);
    }
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _projectController.dispose();
    _areaController.dispose();
    _contextTagsController.dispose();
    _timeBlockStartController.dispose();
    _timeBlockEndController.dispose();
    _contactRoleController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactCompanyController.dispose();
    _metricValueController.dispose();
    _metricUnitController.dispose();
    _metricTrendController.dispose();
    _metricTargetController.dispose();
    _expenseAmountController.dispose();
    _expenseCategoryController.dispose();
    _expensePaymentController.dispose();
    _expenseMerchantController.dispose();
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
    _attachmentsController.dispose();
    _checklistController.dispose();
    _quickChecklistItemController.dispose();
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
    _quoteAuthorController.dispose();
    _timerSecondsController.dispose();
    _audioPathController.dispose();
    _audioDurationController.dispose();
    _audioTranscriptController.dispose();
    _weatherTempController.dispose();
    _weatherConditionController.dispose();
    _fitStepsController.dispose();
    _fitWaterController.dispose();
    _fitWorkoutController.dispose();
    _fitStepTargetController.dispose();
    _fitWaterTargetController.dispose();
    super.dispose();
  }

  void _onBodyChanged() {
    _enforceBodyWordLimit();
    final query = _getAutocompleteQuery(_bodyController);
    final slashQuery = _getSlashCommandQuery(_bodyController);
    if (query != _autocompleteQuery || slashQuery != _slashCommandQuery) {
      setState(() {
        _autocompleteQuery = query;
        _slashCommandQuery = slashQuery;
      });
    }
  }

  void _enforceBodyWordLimit() {
    if (_isHydratingDraft || _isEnforcingBodyLimit) return;
    final maxWords = _bodyMaxWordsForType(_draft.type);
    final words = _bodyWords(_bodyController.text);
    if (words.length <= maxWords) return;
    _isEnforcingBodyLimit = true;
    final trimmed = words.take(maxWords).join(' ');
    _bodyController.text = trimmed;
    _bodyController.selection = TextSelection.collapsed(offset: trimmed.length);
    _isEnforcingBodyLimit = false;
  }

  int _bodyMaxWordsForType(NodeType type) {
    return switch (type) {
      NodeType.note ||
      NodeType.journal ||
      NodeType.resource ||
      NodeType.idea => 2000,
      NodeType.plan || NodeType.goal || NodeType.decision => 1500,
      NodeType.task || NodeType.habit || NodeType.routine => 900,
      NodeType.link || NodeType.bookmark => 700,
      _ => _defaultBodyMaxWords,
    };
  }

  List<String> _bodyWords(String value) {
    return RegExp(r'\S+').allMatches(value).map((m) => m.group(0)!).toList();
  }

  String _bodyWordCountLabel() {
    return '${_bodyWords(_bodyController.text).length}/${_bodyMaxWordsForType(_draft.type)} words';
  }

  String? _getSlashCommandQuery(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    if (!selection.isValid || selection.baseOffset != selection.extentOffset) {
      return null;
    }
    final cursor = selection.baseOffset;
    final prefix = text.substring(0, cursor);
    final tokenStart = prefix.lastIndexOf(RegExp(r'\s')) + 1;
    final token = prefix.substring(tokenStart);
    if (!token.startsWith('/') || token.length > 24) return null;
    return token.substring(1).toLowerCase();
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

  void _insertBodySnippet(
    String before,
    String after, {
    String placeholder = '',
  }) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = start == end ? placeholder : text.substring(start, end);
    final snippet = '$before$selected$after';
    _bodyController.text = text.replaceRange(start, end, snippet);
    final cursor = start + before.length + selected.length;
    _bodyController.selection = TextSelection.collapsed(offset: cursor);
    _onBodyChanged();
  }

  List<String> _bodyActionLines() {
    return _bodyController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^[-*]\s+'), '')
              .replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '')
              .replaceFirst(RegExp(r'^\d+[.)]\s+'), '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _convertBodyToChecklist() {
    final lines = _bodyActionLines();
    if (lines.isEmpty) return;
    setState(() {
      _hasChecklist = true;
      final existing = _checklistController.text.trim();
      _checklistController.text = [
        if (existing.isNotEmpty) existing,
        ...lines,
      ].join('\n');
      _hasUnsavedChanges = true;
    });
  }

  void _convertBodyToPlan() {
    final lines = _bodyActionLines();
    if (lines.isEmpty) return;
    setState(() {
      _hasPlan = true;
      final existing = _planStepsController.text.trim();
      _planStepsController.text = [
        if (existing.isNotEmpty) existing,
        ...lines,
      ].join('\n');
      _hasUnsavedChanges = true;
    });
  }

  void _applyTemplate(_NodeEditorTemplate template) {
    setState(() {
      _bodyController.text = template.body;
      _bodyController.selection = TextSelection.collapsed(
        offset: _bodyController.text.length,
      );
      if (template.checklist != null) {
        _hasChecklist = true;
        _checklistController.text = template.checklist!;
      }
      if (template.tags.isNotEmpty) {
        _hasTags = true;
        _tagsController.text = template.tags.join(', ');
      }
      _hasUnsavedChanges = true;
    });
  }

  void _applyProfessionalTemplate() {
    setState(() {
      switch (_draft.type) {
        case NodeType.event:
          _hasCalendarPayload = true;
          _calendarKind = CalendarNodeKind.event;
          _fillEmpty(_bodyController, '## Agenda\n- \n\n## Outcome\n');
          _fillEmpty(_calAgendaController, 'Context, decisions, next actions');
        case NodeType.decision:
          _hasCalendarPayload = true;
          _calendarKind = CalendarNodeKind.decision;
          _fillEmpty(_bodyController, 'Options:\nDecision:\nReason:\nRisk:');
          _fillEmpty(_calOptionsController, 'Option A\nOption B');
        case NodeType.contact:
          _fillEmpty(_bodyController, 'Notes:\nLast touch:\nNext follow-up:');
          _fillEmpty(_contactRoleController, 'Role');
          _fillEmpty(_contactCompanyController, 'Company');
        case NodeType.metric:
          _hasProgress = true;
          _fillEmpty(_bodyController, 'Cadence:\nSource:\nNotes:');
          _fillEmpty(_metricTrendController, 'stable');
          _fillEmpty(_metricTargetController, 'Target');
        case NodeType.expense:
          _fillEmpty(_bodyController, 'Notes:\nReceipt:\nReimbursable: no');
          _fillEmpty(_expenseCategoryController, 'General');
          _fillEmpty(_expensePaymentController, 'Cash/Card');
        case NodeType.bookmark:
          _hasLink = true;
          _fillEmpty(
            _bodyController,
            'Why saved:\nKey takeaway:\nNext action:',
          );
        case NodeType.question:
          _hasChecklist = true;
          _fillEmpty(_bodyController, 'Question:\nContext:\nPossible answers:');
          _fillEmpty(_checklistController, 'Research\nDecide next step');
        case NodeType.routine:
          _hasChecklist = true;
          _fillEmpty(_bodyController, 'Trigger:\nCadence:\nReward:');
          _fillEmpty(_checklistController, 'Prepare\nExecute\nReview');
        case NodeType.resource:
          _hasNote = true;
          _fillEmpty(_bodyController, 'Summary:\nUseful for:\nKey points:');
        case NodeType.idea:
          _fillEmpty(
            _bodyController,
            'Spark:\nWhy it matters:\nNext experiment:',
          );
        case NodeType.mood:
          _fillEmpty(
            _bodyController,
            'Mood: 😊\nEnergy: 3/5\nTrigger:\nNotes:',
          );
        case NodeType.timer:
          _fillEmpty(
            _bodyController,
            'Focus: \nDistraction log:\n- \nDone: false',
          );
          _fillEmpty(_timerSecondsController, '1500');
        case NodeType.quote:
          _fillEmpty(_bodyController, '“Quote text here.”');
          _fillEmpty(_quoteAuthorController, 'Unknown');
        case NodeType.audio:
          _fillEmpty(
            _bodyController,
            '## Voice Recording\n\nNotes/Transcript:\n- ',
          );
          _fillEmpty(_audioPathController, '/voice-notes/memo.mp3');
          _fillEmpty(_audioDurationController, '0:00');
          _fillEmpty(_audioTranscriptController, '');
        case NodeType.checklist:
          _hasChecklist = true;
          _fillEmpty(_bodyController, '## Checklist');
          _fillEmpty(_checklistController, 'Task 1\nTask 2\nTask 3');
        case NodeType.canvas:
          _fillEmpty(_bodyController, '## Sketchpad\n\nDrawings & sketches.');
        case NodeType.weather:
          _fillEmpty(_bodyController, 'Mood impact: ');
          _fillEmpty(_weatherTempController, '25°C');
          _fillEmpty(_weatherConditionController, 'Sunny');
        case NodeType.fit:
          _fillEmpty(_bodyController, 'Workout: None\nSteps: 0\nWater: 0');
          _fillEmpty(_fitStepsController, '0');
          _fillEmpty(_fitWaterController, '0');
          _fillEmpty(_fitStepTargetController, '10000');
          _fillEmpty(_fitWaterTargetController, '8');
        default:
          _fillEmpty(_bodyController, 'Summary:\nNext action:\nNotes:');
      }
      _hasUnsavedChanges = true;
    });
  }

  void _fillEmpty(TextEditingController controller, String value) {
    if (controller.text.trim().isEmpty) controller.text = value;
  }

  Widget _buildTemplateButton() {
    final templates = _templatesFor(_draft.type);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('node-editor-apply-template'),
          onPressed: _applyProfessionalTemplate,
          icon: const Icon(Icons.auto_fix_high, size: 16),
          label: const Text('Smart template'),
        ),
        MenuAnchor(
          builder: (context, controller, child) {
            return OutlinedButton.icon(
              key: const ValueKey('node-editor-template-library'),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 16),
              label: const Text('Template library'),
            );
          },
          menuChildren: [
            for (final template in templates)
              MenuItemButton(
                leadingIcon: Icon(template.icon),
                onPressed: () => _applyTemplate(template),
                child: Text(template.title),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBodyToolbar() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _BodyToolButton(
            label: 'B',
            tooltip: 'Bold',
            onPressed: () =>
                _insertBodySnippet('**', '**', placeholder: 'text'),
          ),
          _BodyToolButton(
            label: 'H2',
            tooltip: 'Heading',
            onPressed: () => _insertBodySnippet('## ', ''),
          ),
          _BodyToolButton(
            label: 'I',
            tooltip: 'Italic',
            onPressed: () => _insertBodySnippet('_', '_', placeholder: 'text'),
          ),
          _BodyToolButton(
            icon: Icons.format_quote_rounded,
            tooltip: 'Quote',
            onPressed: () => _insertBodySnippet('> ', ''),
          ),
          _BodyToolButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'Bullet list',
            onPressed: () => _insertBodySnippet('- ', ''),
          ),
          _BodyToolButton(
            icon: Icons.check_box_outlined,
            tooltip: 'Checklist item',
            onPressed: () => _insertBodySnippet('- [ ] ', ''),
          ),
          _BodyToolButton(
            icon: Icons.link,
            tooltip: 'Link',
            onPressed: () =>
                _insertBodySnippet('[', '](https://)', placeholder: 'title'),
          ),
          _BodyToolButton(
            label: '[[',
            tooltip: 'Node link',
            onPressed: () => _insertBodySnippet('[[', ''),
          ),
          _BodyToolButton(
            icon: Icons.playlist_add_check_rounded,
            tooltip: 'Convert body lines to checklist',
            onPressed: _convertBodyToChecklist,
          ),
          _BodyToolButton(
            icon: Icons.route_outlined,
            tooltip: 'Convert body lines to plan steps',
            onPressed: _convertBodyToPlan,
          ),
        ],
      ),
    );
  }

  void _runSlashCommand(_SlashCommand command) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final prefix = text.substring(0, cursor);
    final tokenStart = prefix.lastIndexOf(RegExp(r'\s')) + 1;
    final newText = text.replaceRange(tokenStart, cursor, command.insertText);
    setState(() {
      command.apply?.call();
      _bodyController.text = newText;
      _bodyController.selection = TextSelection.collapsed(
        offset: tokenStart + command.insertText.length,
      );
      _slashCommandQuery = null;
      _hasUnsavedChanges = true;
    });
  }

  Widget _buildSlashCommandSuggestions() {
    final query = _slashCommandQuery;
    if (query == null) return const SizedBox.shrink();
    final commands = _slashCommands
        .where((command) => command.name.contains(query))
        .take(8)
        .toList();
    if (commands.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.88,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final command in commands)
            ListTile(
              dense: true,
              leading: Icon(command.icon, size: 18),
              title: Text('/${command.name}'),
              subtitle: Text(command.description),
              onTap: () => _runSlashCommand(command),
            ),
        ],
      ),
    );
  }

  List<_SlashCommand> get _slashCommands => [
    _SlashCommand(
      name: 'task',
      description: 'Insert task checklist block',
      icon: Icons.check_box_outlined,
      insertText: '- [ ] Task\n',
      apply: () => _hasChecklist = true,
    ),
    _SlashCommand(
      name: 'goal',
      description: 'Insert goal/metric block',
      icon: Icons.flag_outlined,
      insertText: 'Objective:\nKey results:\nMilestones:\n',
      apply: () => _hasGoal = true,
    ),
    _SlashCommand(
      name: 'plan',
      description: 'Insert plan steps',
      icon: Icons.route_outlined,
      insertText: 'Outcome:\nSteps:\n- \nRisks:\n',
      apply: () => _hasPlan = true,
    ),
    const _SlashCommand(
      name: 'meeting',
      description: 'Insert meeting note structure',
      icon: Icons.groups_2_outlined,
      insertText: 'Agenda:\nDecisions:\nActions:\n',
    ),
    const _SlashCommand(
      name: 'link',
      description: 'Insert node backlink syntax',
      icon: Icons.hub_outlined,
      insertText: '[[',
    ),
    const _SlashCommand(
      name: 'today',
      description: 'Insert daily review prompts',
      icon: Icons.today_outlined,
      insertText: 'Top priorities:\nLog:\nReflection:\nTomorrow:\n',
    ),
  ];

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
      child: Material(
        type: MaterialType.transparency,
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
                key: ValueKey(
                  'node-editor-create-link-${_autocompleteQuery!.trim()}',
                ),
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
                InkWell(
                  key: ValueKey('node-editor-link-suggestion-${node.id}'),
                  onTap: () => _insertAutocomplete(node.title),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      NodeVisuals.icon(node.type),
                      size: 18,
                      color: NodeVisuals.color(context, node.type),
                    ),
                    title: Text(node.title),
                    subtitle: node.project.isNotEmpty || node.area.isNotEmpty
                        ? Text(
                            '${node.project.isNotEmpty ? 'Project: ${node.project}' : ''}${node.project.isNotEmpty && node.area.isNotEmpty ? ' | ' : ''}${node.area.isNotEmpty ? 'Area: ${node.area}' : ''}',
                            style: const TextStyle(fontSize: 10),
                          )
                        : null,
                  ),
                ),
              if (query.isNotEmpty &&
                  !suggestions.any(
                    (n) => n.title.trim().toLowerCase() == query,
                  ))
                ListTile(
                  key: ValueKey(
                    'node-editor-create-link-${_autocompleteQuery!.trim()}',
                  ),
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
      ),
    );
  }

  void _save() async {
    if (_isSaving) return;
    final title = _titleController.text.trim();
    setState(() {
      _isSaving = true;
      _titleError = null;
      _dateError = null;
      _progressError = null;
    });
    if (title.isEmpty) {
      setState(() {
        _isSaving = false;
        _titleError = 'Title is required';
      });
      return;
    }

    // Validate date format
    if (_hasDueDate && _dueDateController.text.trim().isNotEmpty) {
      final parsed = _parseDate(_dueDateController.text);
      if (parsed == null) {
        setState(() {
          _isSaving = false;
          _dateError = 'Invalid date format. Use YYYY-MM-DD';
        });
        return;
      }
    }

    // Validate progress
    if (_hasProgress && _progressController.text.trim().isNotEmpty) {
      final progressVal = double.tryParse(_progressController.text);
      if (progressVal == null || progressVal < 0 || progressVal > 100) {
        setState(() {
          _isSaving = false;
          _progressError = 'Enter a number between 0 and 100';
        });
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
      updatedData['kanban'] = _parseKanbanBoard().toJson();
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

    updatedData['relations'] = _relationDataForIds(finalRelatedNodeIds);
    final attachments = _parseAttachments();
    if (attachments.isEmpty) {
      updatedData.remove('attachments');
    } else {
      updatedData['attachments'] = attachments;
    }
    _applyStructuredTypeData(updatedData);

    final markdownChecklist = parseMarkdownChecklist(body);
    final checklist = _hasChecklist
        ? _parseChecklist()
        : markdownChecklist.isNotEmpty
        ? markdownChecklist
        : const <TaskChecklistItem>[];
    final effectiveProgress = !_hasProgress && checklist.isNotEmpty
        ? checklist.where((item) => item.isDone).length / checklist.length
        : progress;

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
      effort: _draft.effort,
      reviewState: _draft.reviewState,
      project: _hasContext ? _projectController.text.trim() : '',
      area: _hasContext ? _areaController.text.trim() : '',
      tags: _hasTags
          ? _parseLines(_tagsController.text.replaceAll(',', '\n'))
          : const [],
      contextTags: _hasTags
          ? _parseLines(_contextTagsController.text.replaceAll(',', '\n'))
          : const [],
      dueDate: dueDate,
      progress: effectiveProgress,
      isPinned: _draft.isPinned,
      isArchived: _draft.isArchived,
      checklist: checklist,
      relatedNodeIds: finalRelatedNodeIds.toList(),
      data: updatedData,
    );

    widget.onSave(savedNode);
    if (!mounted) return;
    setState(() {
      _draft = savedNode;
      _isSaving = false;
      _hasUnsavedChanges = false;
      _lastSavedAt = DateTime.now();
    });
  }

  void _applyStructuredTypeData(Map<String, Object?> data) {
    switch (_draft.type) {
      case NodeType.contact:
        data.addAll({
          'role': _contactRoleController.text.trim(),
          'email': _contactEmailController.text.trim(),
          'phone': _contactPhoneController.text.trim(),
          'company': _contactCompanyController.text.trim(),
        });
      case NodeType.metric:
        data.addAll({
          'value': _metricValueController.text.trim(),
          'unit': _metricUnitController.text.trim(),
          'trend': _metricTrendController.text.trim(),
          'target': _metricTargetController.text.trim(),
        });
      case NodeType.expense:
        data.addAll({
          'amount': _expenseAmountController.text.trim(),
          'category': _expenseCategoryController.text.trim(),
          'payment': _expensePaymentController.text.trim(),
          'merchant': _expenseMerchantController.text.trim(),
        });
      case NodeType.resource:
        data['source'] = _noteSourceController.text.trim();
      case NodeType.bookmark:
        data['url'] = _noteSourceController.text.trim();
      case NodeType.mood:
        data.addAll({'mood': _moodEmoji, 'energy': _moodEnergy.round()});
      case NodeType.quote:
        data['author'] = _quoteAuthorController.text.trim();
      case NodeType.timer:
        final seconds =
            int.tryParse(_timerSecondsController.text.trim()) ?? 1500;
        data
          ..['timerSeconds'] = seconds
          ..['timerInitialSeconds'] = seconds;
      case NodeType.audio:
        data.addAll({
          'audioPath': _audioPathController.text.trim(),
          'audioDuration': _audioDurationController.text.trim(),
          'audioTranscript': _audioTranscriptController.text.trim(),
        });
      case NodeType.weather:
        data.addAll({
          'temp': _weatherTempController.text.trim(),
          'weather': _weatherConditionController.text.trim(),
        });
      case NodeType.fit:
        data.addAll({
          'steps': int.tryParse(_fitStepsController.text.trim()) ?? 0,
          'water': int.tryParse(_fitWaterController.text.trim()) ?? 0,
          'workout': _fitWorkoutController.text.trim(),
          'stepTarget':
              int.tryParse(_fitStepTargetController.text.trim()) ?? 10000,
          'waterTarget':
              int.tryParse(_fitWaterTargetController.text.trim()) ?? 8,
        });
      default:
        break;
    }
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

  KanbanBoard _parseKanbanBoard() {
    final existingByTitle = {
      for (final card in KanbanBoard.fromNodeData(_draft.data).cards)
        card.title.trim().toLowerCase(): card,
    };
    final cards = <KanbanCard>[];
    var index = 0;
    for (final rawLine in _kanbanCardsController.text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(':');
      final prefix = separator > 0 ? line.substring(0, separator).trim() : '';
      final column = KanbanColumn.fromName(prefix);
      final title = separator > 0 ? line.substring(separator + 1).trim() : line;
      if (title.isEmpty) continue;
      cards.add(
        existingByTitle[title.toLowerCase()]?.copyWith(
              title: title,
              column: column,
            ) ??
            KanbanCard(id: 'card-${++index}', title: title, column: column),
      );
    }
    return KanbanBoard(cards: cards);
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

  CalendarNodeKind? _defaultCalendarKindForType(NodeType type) {
    return switch (type) {
      NodeType.event => CalendarNodeKind.event,
      NodeType.decision => CalendarNodeKind.decision,
      _ => null,
    };
  }

  void _applyTypeDefaults(NodeType type) {
    _hasKanban |= type == NodeType.kanban;
    _hasHabit |= type == NodeType.habit;
    _hasGoal |= type == NodeType.goal;
    _hasPlan |= type == NodeType.plan;
    _hasJournal |= type == NodeType.journal;
    _hasNote |= type == NodeType.note || type == NodeType.resource;
    _hasLink |= type == NodeType.link || type == NodeType.bookmark;
    _hasChecklist |=
        type == NodeType.task ||
        type == NodeType.routine ||
        type == NodeType.question;
    _hasProgress |= type == NodeType.goal || type == NodeType.metric;
    final calendarKind = _defaultCalendarKindForType(type);
    if (calendarKind != null) {
      _hasCalendarPayload = true;
      _calendarKind = calendarKind;
    }
  }

  Widget _buildFeatureMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Add field',
      icon: const Icon(Icons.tune_rounded),
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
              _calendarKind ??=
                  _defaultCalendarKindForType(_draft.type) ??
                  CalendarNodeKind.event;
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

  PopupMenuItem<VoidCallback> _headerActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return PopupMenuItem<VoidCallback>(
      value: onPressed,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Widget _buildObjectPropertiesPanel() {
    final theme = Theme.of(context);
    final title = _titleController.text.trim().isEmpty
        ? _draft.title.trim()
        : _titleController.text.trim();
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final properties = <({IconData icon, String label, String value})>[
      (
        icon: NodeVisuals.icon(_draft.type),
        label: 'Type',
        value: _draft.type.label,
      ),
      (icon: Icons.flag_outlined, label: 'Status', value: _draft.status.label),
      (
        icon: Icons.priority_high_rounded,
        label: 'Priority',
        value: _draft.priority.label,
      ),
      (icon: Icons.today_outlined, label: 'Day', value: dayKey(_draft.day)),
      if (_projectController.text.trim().isNotEmpty)
        (
          icon: Icons.workspaces_outline,
          label: 'Project',
          value: _projectController.text.trim(),
        ),
      if (_areaController.text.trim().isNotEmpty)
        (
          icon: Icons.map_outlined,
          label: 'Area',
          value: _areaController.text.trim(),
        ),
      if (_dueDateController.text.trim().isNotEmpty)
        (
          icon: Icons.event_available_outlined,
          label: 'Due',
          value: _dueDateController.text.trim(),
        ),
      if (_draft.relatedNodeIds.isNotEmpty)
        (
          icon: Icons.hub_outlined,
          label: 'Links',
          value: '${_draft.relatedNodeIds.length}',
        ),
    ];

    final tokens = AppDesignTokens.of(context);
    return Container(
      key: const ValueKey('node-object-properties-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Icon(Icons.dataset_linked_outlined, size: 18),
              Text('Object properties', style: theme.textTheme.titleSmall),
              TextButton.icon(
                key: const ValueKey('copy-node-wikilink'),
                onPressed: title.isEmpty
                    ? null
                    : () => unawaited(_copyNodeWikiLink(title)),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy [[link]]'),
              ),
              TextButton.icon(
                key: const ValueKey('ai-auto-decompose-button'),
                onPressed: () async {
                  final added = await showTaskDecompositionDialog(
                    context,
                    node: _draft,
                  );
                  if (added != null && added.isNotEmpty) {
                    final currentChecklist = _checklistController.text.trim();
                    final newItems = added.join('\n');
                    _checklistController.text = currentChecklist.isEmpty
                        ? newItems
                        : '$currentChecklist\n$newItems';
                    _markDirty();
                  }
                },
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI Break down'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final property in properties)
                Chip(
                  key: ValueKey(
                    'node-property-${property.label.toLowerCase()}',
                  ),
                  avatar: Icon(property.icon, size: 14),
                  label: Text('${property.label}: ${property.value}'),
                  visualDensity: VisualDensity.compact,
                ),
              for (final tag in tags)
                Chip(
                  key: ValueKey('node-property-tag-$tag'),
                  avatar: const Icon(Icons.sell_outlined, size: 14),
                  label: Text('#$tag'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyNodeWikiLink(String title) async {
    await Clipboard.setData(ClipboardData(text: '[[$title]]'));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied [[$title]]')));
  }

  Widget _buildBacklinksSection() {
    final theme = Theme.of(context);
    final allNodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? [];
    final draftNodes = [
      for (final node in allNodes)
        if (node.id == _draft.id) _draft else node,
      if (!allNodes.any((node) => node.id == _draft.id)) _draft,
    ];
    final links = NodeKnowledgeIndex(draftNodes).linksFor(_draft.id);
    final backlinks = links.backlinks.take(12).toList();
    final unlinkedMentions = links.unlinkedMentions.take(8).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.22,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.keyboard_return_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Backlinks', style: theme.textTheme.titleSmall),
              ),
              Text(
                '${backlinks.length} / ${unlinkedMentions.length}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (backlinks.isEmpty)
            Text(
              'No incoming references yet. Use [[${_draft.title}]] or drag-connect from another node.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final backlink in backlinks)
                  ActionChip(
                    key: ValueKey('backlink-preview-${backlink.node.id}'),
                    avatar: Icon(
                      NodeVisuals.icon(backlink.node.type),
                      color: NodeVisuals.color(context, backlink.node.type),
                      size: 14,
                    ),
                    label: Text(
                      '${backlink.node.title} - ${backlink.reasonLabel}',
                    ),
                    onPressed: () => _showNodePreview(backlink.node),
                  ),
              ],
            ),
          if (unlinkedMentions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Possible links',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _linkAllMentionsFromDraft(unlinkedMentions),
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: const Text('Link all'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final node in unlinkedMentions)
                  ActionChip(
                    avatar: Icon(
                      NodeVisuals.icon(node.type),
                      color: NodeVisuals.color(context, node.type),
                      size: 14,
                    ),
                    label: Text('Link ${node.title}'),
                    onPressed: () => _linkMentionFromDraft(node),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showNodePreview(MindmapNode node) async {
    final theme = Theme.of(context);
    final body = node.body.trim();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              NodeVisuals.icon(node.type),
              color: NodeVisuals.color(context, node.type),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(node.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(node.type.label)),
                if (node.status != NodeStatus.open)
                  Chip(label: Text(node.status.label)),
                if (node.project.isNotEmpty) Chip(label: Text(node.project)),
                if (node.area.isNotEmpty) Chip(label: Text(node.area)),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                body.length > 240 ? '${body.substring(0, 240)}?' : body,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
        actions: [
          if (widget.onOpenNode != null)
            FilledButton(
              key: ValueKey('open-node-preview-${node.id}'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenNode?.call(node);
              },
              child: const Text('Open'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _linkMentionFromDraft(MindmapNode target) {
    final linkedBody = _bodyWithLinkedTitle(_bodyController.text, target.title);
    setState(() {
      _bodyController.text = linkedBody;
      _bodyController.selection = TextSelection.collapsed(
        offset: linkedBody.length,
      );
      _draft = _draft.copyWith(body: linkedBody);
      _hasUnsavedChanges = true;
    });
    _addRelatedNodeWithLabel(target.id, _defaultRelationLabel);
  }

  void _linkAllMentionsFromDraft(List<MindmapNode> targets) {
    var body = _bodyController.text;
    for (final target in targets) {
      body = _bodyWithLinkedTitle(body, target.title);
    }
    setState(() {
      _bodyController.text = body;
      _bodyController.selection = TextSelection.collapsed(offset: body.length);
      _draft = _draft.copyWith(body: body);
      _hasUnsavedChanges = true;
    });
    for (final target in targets) {
      _addRelatedNodeWithLabel(target.id, _defaultRelationLabel);
    }
  }

  String _bodyWithLinkedTitle(String body, String title) {
    return bodyWithLinkedTitle(body, title);
  }

  Widget _buildSmartActionsSection() {
    final theme = Theme.of(context);
    final today = DateTime.now().dateOnly;
    final isTask = _draft.type == NodeType.task;
    final isGoal = _draft.type == NodeType.goal;
    final isOverdue =
        _draft.dueDate != null &&
        _draft.dueDate!.dateOnly.isBefore(today) &&
        !_draft.isDone;
    final hasBodyLinks = RegExp(
      r'https?:\/\/[^\s)\]]+',
    ).hasMatch(_bodyController.text);
    final routineTemplateId = _routineTemplateIdFor(_draft.type);
    final allNodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? [];
    final duplicateNode = _suggestDuplicateNode(allNodes);
    final linkNode = _suggestLinkNode(allNodes);
    final actions = <Widget>[
      ActionChip(
        avatar: const Icon(Icons.content_copy_rounded, size: 16),
        label: const Text('Duplicate node'),
        onPressed: _duplicateDraftNode,
      ),
      ActionChip(
        avatar: const Icon(Icons.dashboard_customize_outlined, size: 16),
        label: const Text('Save as template'),
        onPressed: () => unawaited(_saveDraftAsTemplate()),
      ),
      ..._buildConversionActions(),
      ..._buildFocusTimerActions(),
      if (isTask && !_draft.isDone)
        ActionChip(
          avatar: const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Complete task'),
          onPressed: _markDraftDone,
        ),
      if (isOverdue)
        ActionChip(
          avatar: const Icon(Icons.event_repeat, size: 16),
          label: const Text('Reschedule tomorrow'),
          onPressed: _rescheduleDraftTomorrow,
        ),
      if (isGoal && !_draft.isPinned)
        ActionChip(
          avatar: const Icon(Icons.push_pin_outlined, size: 16),
          label: const Text('Pin goal'),
          onPressed: _pinDraft,
        ),
      if (duplicateNode != null)
        ActionChip(
          avatar: const Icon(Icons.merge_type_rounded, size: 16),
          label: Text('Mark duplicate: ${duplicateNode.title}'),
          onPressed: () =>
              _addRelatedNodeWithLabel(duplicateNode.id, 'possible duplicate'),
        ),
      if (linkNode != null)
        ActionChip(
          avatar: const Icon(Icons.hub_outlined, size: 16),
          label: Text('Link: ${linkNode.title}'),
          onPressed: () => _addRelatedNodeWithLabel(linkNode.id, 'related'),
        ),
      if (hasBodyLinks)
        ActionChip(
          avatar: const Icon(Icons.attach_file_rounded, size: 16),
          label: const Text('Extract links'),
          onPressed: _extractBodyLinksToAttachments,
        ),
      if (routineTemplateId != null)
        ActionChip(
          avatar: const Icon(Icons.repeat_rounded, size: 16),
          label: const Text('Make weekly routine'),
          onPressed: () => _createRoutineRule(routineTemplateId),
        ),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              Text('Smart actions', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: actions),
        ],
      ),
    );
  }

  List<Widget> _buildFocusTimerActions() {
    final timer = _focusTimerData();
    final status = timer['status'] as String?;
    if (status == 'running') {
      return [
        ActionChip(
          key: const ValueKey('pause-focus-timer'),
          avatar: const Icon(Icons.pause_circle_outline, size: 16),
          label: const Text('Pause focus'),
          onPressed: () => _setFocusTimerStatus('paused'),
        ),
        ActionChip(
          key: const ValueKey('reset-focus-timer'),
          avatar: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('Reset focus'),
          onPressed: _resetFocusTimer,
        ),
      ];
    }
    return [
      ActionChip(
        key: const ValueKey('start-focus-timer'),
        avatar: const Icon(Icons.timer_outlined, size: 16),
        label: Text(status == 'paused' ? 'Resume focus' : 'Start focus'),
        onPressed: () => _setFocusTimerStatus('running'),
      ),
      if (status == 'paused')
        ActionChip(
          key: const ValueKey('reset-focus-timer'),
          avatar: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('Reset focus'),
          onPressed: _resetFocusTimer,
        ),
    ];
  }

  Map<String, Object?> _focusTimerData() {
    final timer = _draft.data['focusTimer'];
    if (timer is Map) return timer.cast<String, Object?>();
    return const {};
  }

  void _setFocusTimerStatus(String status) {
    final action = status == 'running' ? 'focus_started' : 'focus_paused';
    final label = status == 'running'
        ? 'Started focus timer'
        : 'Paused focus timer';
    setState(() {
      final timer = {
        ..._focusTimerData(),
        'status': status,
        'elapsedMinutes': _focusTimerData()['elapsedMinutes'] ?? 0,
      };
      final data = <String, Object?>{..._draft.data, 'focusTimer': timer};
      _draft = _draft.copyWith(
        data: _appendActivityLog(data, action: action, label: label),
      );
      _hasUnsavedChanges = true;
    });
    Navigator.of(context).maybePop();
  }

  void _resetFocusTimer() {
    setState(() {
      final data = <String, Object?>{..._draft.data}..remove('focusTimer');
      _draft = _draft.copyWith(
        data: _appendActivityLog(
          data,
          action: 'focus_reset',
          label: 'Reset focus timer',
        ),
      );
      _hasUnsavedChanges = true;
    });
  }

  List<Widget> _buildConversionActions() {
    final conversions = <_NodeConversion>[
      if (_draft.type == NodeType.idea)
        const _NodeConversion(
          key: 'convert-node-to-task',
          icon: Icons.task_alt_outlined,
          label: 'Convert to task',
          type: NodeType.task,
          status: NodeStatus.open,
          effort: NodeEffort.fifteenMinutes,
          contextTags: ['quick win'],
        ),
      if (_draft.type == NodeType.question)
        const _NodeConversion(
          key: 'convert-node-to-decision',
          icon: Icons.rule_outlined,
          label: 'Convert to decision',
          type: NodeType.decision,
          reviewState: NodeReviewState.needsReview,
        ),
      if (_draft.type == NodeType.note)
        const _NodeConversion(
          key: 'convert-node-to-resource',
          icon: Icons.inventory_2_outlined,
          label: 'Convert to resource',
          type: NodeType.resource,
        ),
      if (_draft.type == NodeType.task)
        const _NodeConversion(
          key: 'convert-node-to-event',
          icon: Icons.event_available_outlined,
          label: 'Convert to event',
          type: NodeType.event,
        ),
    ];
    return [
      for (final conversion in conversions)
        ActionChip(
          key: ValueKey(conversion.key),
          avatar: Icon(conversion.icon, size: 16),
          label: Text(conversion.label),
          onPressed: () => _convertDraft(conversion),
        ),
    ];
  }

  void _convertDraft(_NodeConversion conversion) {
    setState(() {
      final contextTags = {
        ..._draft.contextTags,
        ...conversion.contextTags,
      }.toList();
      _draft = _draft.copyWith(
        type: conversion.type,
        status: conversion.status,
        effort: conversion.effort,
        reviewState: conversion.reviewState,
        contextTags: contextTags,
        data: _appendActivityLog(
          _draft.data,
          action: 'converted',
          label:
              'Converted ${_draft.type.label.toLowerCase()} to ${conversion.type.label.toLowerCase()}',
        ),
      );
      _contextTagsController.text = contextTags.join(', ');
      _applyTypeDefaults(conversion.type);
      _hasTags |= contextTags.isNotEmpty;
      _hasUnsavedChanges = true;
    });
    Navigator.of(context).maybePop();
  }

  Map<String, Object?> _appendActivityLog(
    Map<String, Object?> data, {
    required String action,
    required String label,
  }) {
    final existing = data['activityLog'];
    final log = <Map<String, Object?>>[
      if (existing is List)
        for (final entry in existing)
          if (entry is Map) entry.cast<String, Object?>(),
    ];
    return {
      ...data,
      'activityLog': [
        {'action': action, 'label': label},
        ...log,
      ].take(10).toList(),
    };
  }

  Future<void> _duplicateDraftNode() async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final duplicate = _draft.copyWith(
      id: 'node-${now.microsecondsSinceEpoch}',
      title: '${_draft.title} copy',
      createdAt: now,
      updatedAt: now,
      position: CanvasPosition(
        _draft.position.dx + 32,
        _draft.position.dy + 32,
      ),
    );
    await repository.saveNode(duplicate);
    invalidateMindmapState(ref, day: duplicate.day);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Duplicated ${_draft.title}')));
    }
  }

  Future<void> _saveDraftAsTemplate() async {
    final preferences = SharedPreferencesAsync();
    final raw = await preferences.getString(customNodeTemplatesPreferenceKey);
    final existing = _decodeTemplates(raw);
    final template = NodeTemplate(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      label: _titleController.text.trim().isEmpty
          ? _draft.title
          : _titleController.text.trim(),
      type: _draft.type,
      title: _titleController.text.trim().isEmpty
          ? _draft.title
          : _titleController.text.trim(),
      body: _bodyController.text,
      status: _draft.status,
      priority: _draft.priority,
      project: _projectController.text.trim(),
      area: _areaController.text.trim(),
      tags: _draft.tags,
      progress: _draft.progress,
      checklist: [for (final item in _draft.checklist) item.title],
      data: _draft.data,
    );
    await preferences.setString(
      customNodeTemplatesPreferenceKey,
      jsonEncode([
        for (final item in [...existing, template]) nodeTemplateToJson(item),
      ]),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved template ${template.label}')));
  }

  List<NodeTemplate> _decodeTemplates(String? raw) {
    try {
      return nodeTemplatesFromJsonList(raw == null ? null : jsonDecode(raw));
    } on FormatException {
      return const [];
    }
  }

  String? _routineTemplateIdFor(NodeType type) {
    return switch (type) {
      NodeType.plan => 'daily-plan',
      NodeType.journal => 'weekly-review',
      NodeType.habit => 'workout-habit',
      NodeType.goal => 'goal-tracker',
      NodeType.kanban => 'sprint-board',
      NodeType.note || NodeType.resource || NodeType.idea => 'research-note',
      NodeType.link || NodeType.bookmark => 'link-inbox',
      NodeType.task || NodeType.event => 'reminder',
      NodeType.decision => 'decision-log',
      NodeType.metric => 'metric-tracker',
      NodeType.question ||
      NodeType.contact ||
      NodeType.expense ||
      NodeType.routine ||
      NodeType.empty => null,
      _ => null,
    };
  }

  Future<void> _createRoutineRule(String templateId) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final label = '${_titleController.text.trim()} routine'.trim();
    final ruleNode = createAutomationRuleNode(
      id: 'node-routine-${_draft.id}-${now.microsecondsSinceEpoch}',
      label: label.isEmpty ? 'Node routine' : label,
      templateId: templateId,
      rule: RecurringRule.weekly(weekday: _draft.day.weekday),
      day: _draft.day,
      now: now,
    );
    await repository.saveNode(ruleNode);
    invalidateMindmapState(ref, day: _draft.day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Automation routine created for ${_draft.title}')),
    );
  }

  void _markDraftDone() {
    setState(() {
      _draft = _draft.copyWith(
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        data: _appendActivityLog(
          _draft.data,
          action: 'completed',
          label: 'Completed task',
        ),
      );
      _progressController.text = '100';
      _hasProgress = true;
      _hasUnsavedChanges = true;
    });
  }

  void _rescheduleDraftTomorrow() {
    final tomorrow = DateTime.now().dateOnly.addDays(1);
    setState(() {
      _draft = _draft.copyWith(
        dueDate: tomorrow,
        data: _appendActivityLog(
          _draft.data,
          action: 'rescheduled',
          label: 'Rescheduled to tomorrow',
        ),
      );
      _dueDateController.text = dayKey(tomorrow);
      _hasDueDate = true;
      _hasUnsavedChanges = true;
    });
  }

  void _pinDraft() {
    setState(() {
      _draft = _draft.copyWith(
        isPinned: true,
        data: _appendActivityLog(
          _draft.data,
          action: 'pinned',
          label: 'Pinned node',
        ),
      );
      _hasUnsavedChanges = true;
    });
  }

  Widget _buildAttachmentsSection() {
    final theme = Theme.of(context);
    final attachments = _parseAttachments();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              const Icon(Icons.attach_file_rounded, size: 18),
              Text('Attachments', style: theme.textTheme.titleSmall),
              Text('${attachments.length}', style: theme.textTheme.labelSmall),
              TextButton.icon(
                onPressed: _extractBodyLinksToAttachments,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Extract'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _attachmentsController,
            decoration: const InputDecoration(
              labelText: 'Files / links',
              helperText: 'One per line: Title | https://example.com/file.pdf',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            minLines: 2,
            maxLines: 5,
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attachment in attachments)
                  InputChip(
                    avatar: Icon(_attachmentIcon(attachment), size: 14),
                    label: Text(_attachmentLabel(attachment)),
                    onPressed: () => _openAttachment(attachment),
                    onDeleted: () => _copyAttachmentUrl(attachment),
                    deleteIcon: const Icon(Icons.copy_rounded, size: 16),
                    deleteButtonTooltipMessage: 'Copy URL',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, String>> _parseAttachments() {
    final lines = _attachmentsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return [
      for (final line in lines)
        () {
          final parts = line.split('|').map((part) => part.trim()).toList();
          if (parts.length >= 2) {
            return {'title': parts.first, 'url': parts.sublist(1).join('|')};
          }
          return {'title': line, 'url': line};
        }(),
    ];
  }

  void _extractBodyLinksToAttachments() {
    final urls = RegExp(
      r'https?:\/\/[^\s)\]]+',
    ).allMatches(_bodyController.text).map((match) => match.group(0)!).toSet();
    if (urls.isEmpty) return;
    final existing = _parseAttachments();
    final existingUrls = existing.map((item) => item['url']).toSet();
    final merged = [
      ...existing,
      for (final url in urls)
        if (!existingUrls.contains(url)) {'title': _hostLabel(url), 'url': url},
    ];
    setState(() {
      _attachmentsController.text = merged
          .map((item) => '${item['title']} | ${item['url']}')
          .join('\n');
      _hasUnsavedChanges = true;
    });
  }

  IconData _attachmentIcon(Map<String, String> attachment) {
    final url = attachment['url'] ?? '';
    if (url.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (RegExp(
      r'\.(png|jpe?g|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(url)) {
      return Icons.image_outlined;
    }
    if (url.startsWith('http')) return Icons.public_rounded;
    return Icons.insert_drive_file_outlined;
  }

  String _attachmentLabel(Map<String, String> attachment) {
    final title = attachment['title'] ?? '';
    final url = attachment['url'] ?? '';
    if (title.isNotEmpty && title != url) return title;
    return _hostLabel(url.isEmpty ? title : url);
  }

  String _hostLabel(String value) {
    final uri = Uri.tryParse(value);
    final host = uri?.host ?? '';
    if (host.isNotEmpty) return host.replaceFirst('www.', '');
    return value;
  }

  Future<void> _openAttachment(Map<String, String> attachment) async {
    final url = attachment['url'] ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      await _copyAttachmentUrl(attachment);
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) await _copyAttachmentUrl(attachment);
  }

  Future<void> _copyAttachmentUrl(Map<String, String> attachment) async {
    final url = attachment['url'] ?? attachment['title'] ?? '';
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attachment URL copied')));
  }

  String _attachmentsTextFromData(Map<String, Object?> data) {
    final raw = data['attachments'];
    if (raw is! List<Object?>) return '';
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((item) {
          final title = item['title'] as String? ?? '';
          final url = item['url'] as String? ?? '';
          if (title.isEmpty) return url;
          if (url.isEmpty || url == title) return title;
          return '$title | $url';
        })
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
  }

  Widget _buildConnectionSection() {
    final theme = Theme.of(context);
    final allNodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? [];
    final nodesById = {for (final node in allNodes) node.id: node};
    final linkedNodes = _draft.relatedNodeIds
        .map((id) => nodesById[id])
        .whereType<MindmapNode>()
        .toList();
    final brokenRelatedIds = [
      for (final id in _draft.relatedNodeIds)
        if (!nodesById.containsKey(id)) id,
    ];
    final suggestedTypes = compatibleNodeTypes(_draft.type).take(6).toList();
    final suggestedNodes = allNodes
        .where(
          (node) =>
              node.id != _draft.id &&
              !node.isArchived &&
              !_draft.relatedNodeIds.contains(node.id) &&
              suggestedTypes.contains(node.type),
        )
        .take(6)
        .toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.hub_outlined,
                color: NodeVisuals.color(context, _draft.type),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Connections', style: theme.textTheme.titleSmall),
              ),
              Text(
                '${_draft.relatedNodeIds.length} linked',
                style: theme.textTheme.labelSmall,
              ),
              IconButton(
                key: const ValueKey('add-connected-node'),
                tooltip: 'Add connected node',
                icon: const Icon(Icons.add_link_rounded, size: 18),
                onPressed: () => unawaited(_showAddConnectedNodeDialog()),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Best connects to: ${compatibleNodeTypeLabel(_draft.type)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in suggestedTypes)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    NodeVisuals.icon(type),
                    color: NodeVisuals.color(context, type),
                    size: 14,
                  ),
                  label: Text(type.label),
                ),
            ],
          ),
          if (linkedNodes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final node in linkedNodes)
                  _RelatedNodeChip(
                    node: node,
                    label: _relationLabelFor(node.id),
                    onPreview: () => _showNodePreview(node),
                    onEditLabel: () => _showRelationLabelEditor(node.id),
                    onRemove: () => _removeRelatedNode(node.id),
                  ),
              ],
            ),
          ],
          if (brokenRelatedIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_off_rounded,
                    color: theme.colorScheme.onErrorContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Broken links: ${brokenRelatedIds.join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('remove-broken-related-links'),
                    onPressed: () => _removeRelatedNodes(brokenRelatedIds),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
          ],
          if (suggestedNodes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Suggested nodes', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final node in suggestedNodes)
                  ActionChip(
                    avatar: Icon(
                      NodeVisuals.icon(node.type),
                      color: NodeVisuals.color(context, node.type),
                      size: 14,
                    ),
                    label: Text(node.title),
                    onPressed: () => _addRelatedNode(node.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _relatedNodeIdsController,
            decoration: const InputDecoration(
              labelText: 'Link by node ID',
              helperText:
                  'Comma-separated IDs. [[Title]] links in body sync too.',
              prefixIcon: Icon(Icons.cable_rounded),
            ),
            minLines: 1,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  void _addRelatedNode(String id) {
    _addRelatedNodeWithLabel(id, _defaultRelationLabel);
  }

  void _addRelatedNodeWithLabel(String id, String label) {
    final ids = {..._draft.relatedNodeIds, id}.toList();
    final labels = {..._relationLabelMap(), id: label};
    final relations = [
      for (final nodeId in ids)
        {'targetId': nodeId, 'label': labels[nodeId] ?? _defaultRelationLabel},
    ];
    setState(() {
      _draft = _draft.copyWith(
        relatedNodeIds: ids,
        data: {..._draft.data, 'relations': relations},
      );
      _relatedNodeIdsController.text = ids.join(', ');
      _hasUnsavedChanges = true;
    });
  }

  void _removeRelatedNode(String id) {
    _removeRelatedNodes([id]);
  }

  void _removeRelatedNodes(Iterable<String> idsToRemove) {
    final removeSet = idsToRemove.toSet();
    final ids = _draft.relatedNodeIds
        .where((nodeId) => !removeSet.contains(nodeId))
        .toList();
    setState(() {
      _draft = _draft.copyWith(
        relatedNodeIds: ids,
        data: {..._draft.data, 'relations': _relationDataForIds(ids)},
      );
      _relatedNodeIdsController.text = ids.join(', ');
      _hasUnsavedChanges = true;
    });
  }

  MindmapNode? _suggestDuplicateNode(List<MindmapNode> nodes) {
    final title = _normalizedTitle(_titleController.text);
    if (title.length < 4) return null;
    return nodes.firstWhereOrNull(
      (node) =>
          node.id != _draft.id &&
          !node.isArchived &&
          !_draft.relatedNodeIds.contains(node.id) &&
          _normalizedTitle(node.title) == title,
    );
  }

  MindmapNode? _suggestLinkNode(List<MindmapNode> nodes) {
    final title = _normalizedTitle(_titleController.text);
    if (title.length < 4) return null;
    final draftTokens = _titleTokens(title);
    if (draftTokens.isEmpty) return null;
    return nodes.firstWhereOrNull((node) {
      if (node.id == _draft.id ||
          node.isArchived ||
          _draft.relatedNodeIds.contains(node.id)) {
        return false;
      }
      final nodeTitle = _normalizedTitle(node.title);
      if (nodeTitle == title) return false;
      final nodeTokens = _titleTokens(nodeTitle);
      final overlap = draftTokens.intersection(nodeTokens).length;
      return overlap >= 2 ||
          (draftTokens.length == 1 && nodeTokens.contains(draftTokens.single));
    });
  }

  String _normalizedTitle(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Set<String> _titleTokens(String value) {
    return value.split(' ').where((token) => token.length >= 4).toSet();
  }

  List<Map<String, Object?>> _relationDataForIds(Iterable<String> ids) {
    final existing = _relationLabelMap();
    return [
      for (final id in ids)
        {'targetId': id, 'label': existing[id] ?? _defaultRelationLabel},
    ];
  }

  Map<String, String> _relationLabelMap() {
    final raw = _draft.data['relations'];
    if (raw is! List<Object?>) return const {};
    return {
      for (final item in raw)
        if (item is Map<Object?, Object?> && item['targetId'] is String)
          item['targetId']! as String:
              item['label'] is String && (item['label']! as String).isNotEmpty
              ? item['label']! as String
              : _defaultRelationLabel,
    };
  }

  String _relationLabelFor(String id) {
    return _relationLabelMap()[id] ?? _defaultRelationLabel;
  }

  Future<void> _showRelationLabelEditor(String id) async {
    final controller = TextEditingController(text: _relationLabelFor(id));
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relation label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'supports / blocks / references',
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _relationLabelPresets)
                  ActionChip(
                    key: ValueKey('relation-label-preset-$preset'),
                    label: Text(preset),
                    onPressed: () => Navigator.of(context).pop(preset),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (label == null) return;
    _setRelationLabel(id, label.trim().isEmpty ? _defaultRelationLabel : label);
  }

  void _setRelationLabel(String id, String label) {
    final labels = {..._relationLabelMap(), id: label};
    final relations = [
      for (final nodeId in _draft.relatedNodeIds)
        {'targetId': nodeId, 'label': labels[nodeId] ?? _defaultRelationLabel},
    ];
    setState(() {
      _draft = _draft.copyWith(data: {..._draft.data, 'relations': relations});
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _showAddConnectedNodeDialog() async {
    final titleController = TextEditingController();
    final labelController = TextEditingController(text: _defaultRelationLabel);
    var selectedType = NodeType.note;
    final result =
        await showDialog<({String title, NodeType type, String label})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Add connected node'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('connected-node-title-field'),
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<NodeType>(
                    key: const ValueKey('connected-node-type-dropdown'),
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: NodeType.values
                        .where((type) => type != NodeType.empty)
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(),
                    onChanged: (type) {
                      if (type != null) {
                        setDialogState(() => selectedType = type);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('connected-node-relation-field'),
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Relation'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('connected-node-create'),
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;
                    Navigator.of(context).pop((
                      title: title,
                      type: selectedType,
                      label: labelController.text.trim(),
                    ));
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        );
    if (result == null) return;
    await _createConnectedNode(result.title, result.type, result.label);
  }

  Future<void> _createConnectedNode(
    String title,
    NodeType type,
    String label,
  ) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final node = MindmapNode.create(
      id: 'node-${now.microsecondsSinceEpoch}-${title.hashCode}',
      type: type,
      title: title,
      day: _draft.day,
      project: _draft.project,
      area: _draft.area,
      tags: _draft.tags,
      position: CanvasPosition(_draft.position.dx + 140, _draft.position.dy),
      now: now,
    );
    await repository.saveNode(node);
    _addRelatedNodeWithLabel(
      node.id,
      label.trim().isEmpty ? _defaultRelationLabel : label.trim(),
    );
    invalidateMindmapState(ref, day: _draft.day);
  }

  Widget _buildReviewNudgesSection() {
    final nudges = _draft.reviewNudges(DateTime.now());
    if (nudges.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('node-review-nudges-section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                size: 18,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text('Suggestions', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          for (final nudge in nudges)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodySmall),
                  Expanded(
                    child: Text(nudge, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActivityLogSection() {
    final existing = _draft.data['activityLog'];
    final entries = <Map<String, Object?>>[
      if (existing is List)
        for (final entry in existing)
          if (entry is Map) entry.cast<String, Object?>(),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('node-activity-log-section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text('Activity', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                (entry['label'] as String?) ??
                    (entry['action'] as String?) ??
                    'Updated node',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  NodeEditContext _sharedTypeEditContext() => NodeEditContext(
    node: _draft,
    typedDraft: nodeTypeInlineDraftFor(_draft),
    effectivePreset: NodePresentationSpec.forType(_draft.type).defaultPreset,
    validationErrors: <String>[?_titleError, ?_dateError, ?_progressError],
    onTitleChanged: (String value) {
      _titleController.text = value;
      setState(() {
        _draft = _draft.copyWith(title: value);
        _hasUnsavedChanges = true;
      });
    },
    onBodyChanged: (String value) {
      _bodyController.text = value;
      setState(() {
        _draft = _draft.copyWith(body: value);
        _hasUnsavedChanges = true;
      });
    },
    onDraftChanged: _applySharedTypeDraft,
    onNodeDraftChanged: _applySharedNodeDraft,
  );

  void _applySharedTypeDraft(Object value) {
    _applySharedNodeDraft(applyNodeTypeInlineDraft(_draft, value));
  }

  void _applySharedNodeDraft(MindmapNode value) {
    setState(() {
      _draft = value;
      if (_titleController.text != value.title) {
        _titleController.text = value.title;
      }
      if (_bodyController.text != value.body) {
        _bodyController.text = value.body;
      }
      _loadTypeSpecificData(value.data);
      _loadStructuredTypeFields(value);
      _hasUnsavedChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final expanded = constraints.maxWidth >= 1024;
        final content = InlineNodeWorkspaceSurface(
          header: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: ShapeDecoration(
                        color: NodeVisuals.color(
                          context,
                          _draft.type,
                        ).withValues(alpha: 0.16),
                        shape: CircleBorder(
                          side: BorderSide(
                            color: NodeVisuals.color(
                              context,
                              _draft.type,
                            ).withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      child: Icon(
                        NodeVisuals.icon(_draft.type),
                        size: 18,
                        color: NodeVisuals.color(context, _draft.type),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit Node',
                            key: const ValueKey('node-editor-title'),
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            _draft.type.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) _buildFeatureMenu(),
                    PopupMenuButton<VoidCallback>(
                      key: const ValueKey('node-editor-overflow-menu'),
                      tooltip: 'More node actions',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (action) => action(),
                      itemBuilder: (context) => [
                        _headerActionItem(
                          icon: Icons.delete_outline,
                          label: 'Delete node',
                          color: theme.colorScheme.error,
                          onPressed: widget.onDelete,
                        ),
                      ],
                    ),
                    if (widget.onCollapse != null)
                      IconButton(
                        constraints: BoxConstraints.tightFor(
                          width: tokens.minimumTarget,
                          height: tokens.minimumTarget,
                        ),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Collapse editor',
                        onPressed: widget.onCollapse,
                      ),
                    IconButton(
                      constraints: BoxConstraints.tightFor(
                        width: tokens.minimumTarget,
                        height: tokens.minimumTarget,
                      ),
                      icon: const Icon(Icons.close),
                      tooltip: 'Close editor',
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              _EditorPanelTabs(
                compact: compact,
                selected: _panelTab,
                onSelected: (tab) => setState(() => _panelTab = tab),
              ),
            ],
          ),
          bodyPadding: EdgeInsetsDirectional.all(compact ? 12 : 16),
          bodyOwnsScroll: _panelTab == _EditorPanelTab.type,
          body: _panelTab == _EditorPanelTab.type
              ? buildNodeTypeInlineEditor(_sharedTypeEditContext())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_panelTab == _EditorPanelTab.edit) ...[
                      DropdownButtonFormField<NodeType>(
                        key: const ValueKey('node-editor-type-dropdown'),
                        isExpanded: true,
                        initialValue: _draft.type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: NodeType.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(t.label),
                          );
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
                                effort: _draft.effort,
                                reviewState: _draft.reviewState,
                                project: _draft.project,
                                area: _draft.area,
                                tags: _draft.tags,
                                contextTags: _draft.contextTags,
                                dueDate: _draft.dueDate,
                                progress: _draft.progress,
                                isPinned: _draft.isPinned,
                                isArchived: _draft.isArchived,
                                checklist: _draft.checklist,
                                relatedNodeIds: _draft.relatedNodeIds,
                                data: _draft.data,
                              );
                              _applyTypeDefaults(v);
                              _hasUnsavedChanges = true;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: TextField(
                          key: const ValueKey('node-editor-title-field'),
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'Title',
                            errorText: _titleError,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildObjectPropertiesPanel(),
                      const SizedBox(height: 16),
                      const _EditorSectionHeader(title: 'Core'),
                      const SizedBox(height: 8),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: TextField(
                          key: const ValueKey('node-editor-body-field'),
                          controller: _bodyController,
                          decoration: InputDecoration(
                            labelText: 'Rich description',
                            helperText:
                                'Markdown supported. Type [[ to link another node.',
                            counterText: _bodyWordCountLabel(),
                          ),
                          minLines: 6,
                          maxLines: 14,
                          onChanged: (_) {},
                        ),
                      ),
                      _buildBodyToolbar(),
                      _buildSlashCommandSuggestions(),
                      const SizedBox(height: 8),
                      _buildAutocompleteSuggestions(),
                      const SizedBox(height: 16),
                      _buildTemplateButton(),
                      const SizedBox(height: 12),
                      _buildSmartActionsSection(),
                      const SizedBox(height: 12),
                      _buildReviewNudgesSection(),
                      const SizedBox(height: 12),
                      _buildActivityLogSection(),
                      const SizedBox(height: 12),
                      _buildAttachmentsSection(),
                    ],
                    if (_panelTab == _EditorPanelTab.links) ...[
                      _buildConnectionSection(),
                      const SizedBox(height: 12),
                      _buildBacklinksSection(),
                    ],
                    if (_panelTab == _EditorPanelTab.edit) ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<NodeStatus>(
                              key: const ValueKey(
                                'node-editor-status-dropdown',
                              ),
                              isExpanded: true,
                              initialValue: _draft.status,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                              ),
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
                                      effort: _draft.effort,
                                      reviewState: _draft.reviewState,
                                      project: _draft.project,
                                      area: _draft.area,
                                      tags: _draft.tags,
                                      contextTags: _draft.contextTags,
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
                              key: const ValueKey(
                                'node-editor-priority-dropdown',
                              ),
                              isExpanded: true,
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
                                      effort: _draft.effort,
                                      reviewState: _draft.reviewState,
                                      project: _draft.project,
                                      area: _draft.area,
                                      tags: _draft.tags,
                                      contextTags: _draft.contextTags,
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<NodeEffort>(
                              key: const ValueKey(
                                'node-editor-effort-dropdown',
                              ),
                              initialValue: _draft.effort,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Effort',
                              ),
                              items: NodeEffort.values
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(
                                    () => _draft = _draft.copyWith(effort: v),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<NodeReviewState>(
                              key: const ValueKey(
                                'node-editor-review-state-dropdown',
                              ),
                              initialValue: _draft.reviewState,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Review state',
                              ),
                              items: NodeReviewState.values
                                  .map(
                                    (state) => DropdownMenuItem(
                                      value: state,
                                      child: Text(state.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(
                                    () => _draft = _draft.copyWith(
                                      reviewState: v,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('node-editor-context-tags-field'),
                        controller: _contextTagsController,
                        decoration: const InputDecoration(
                          labelText: 'Context tags',
                          hintText: 'deep work, quick win, offline, waiting',
                          prefixIcon: Icon(Icons.psychology_outlined),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => setState(() => _hasTags = true),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
          // Fixed footer: intentionally outside the scrollable editor body.
          footer: SafeArea(
            top: false,
            child: Container(
              key: const ValueKey('node-editor-fixed-footer'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (!compact)
                    Expanded(
                      child: _EditorSaveStatus(
                        hasUnsavedChanges: _hasUnsavedChanges,
                        isSaving: _isSaving,
                        lastSavedAt: _lastSavedAt,
                      ),
                    ),
                  if (!compact) const SizedBox(width: 8),
                  if (!compact)
                    IconButton.outlined(
                      tooltip: 'Reset changes',
                      onPressed: _hasUnsavedChanges && !_isSaving
                          ? () => setState(() => _initDraft(widget.node))
                          : null,
                      icon: const Icon(Icons.undo_rounded),
                    ),
                  if (!compact) const SizedBox(width: 8),
                  Expanded(
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: TextButton(
                        key: const ValueKey('cancel-node-editor'),
                        onPressed: widget.onClose,
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: FilledButton.icon(
                        key: const ValueKey('save-node'),
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(_isSaving ? 'Saving…' : 'Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: expanded ? constraints.maxWidth : 840,
              ),
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NodeConversion {
  const _NodeConversion({
    required this.key,
    required this.icon,
    required this.label,
    required this.type,
    this.status,
    this.effort,
    this.reviewState,
    this.contextTags = const [],
  });

  final String key;
  final IconData icon;
  final String label;
  final NodeType type;
  final NodeStatus? status;
  final NodeEffort? effort;
  final NodeReviewState? reviewState;
  final List<String> contextTags;
}

enum _EditorPanelTab { edit, type, links }

class _EditorPanelTabs extends StatelessWidget {
  const _EditorPanelTabs({
    required this.compact,
    required this.selected,
    required this.onSelected,
  });

  final bool compact;
  final _EditorPanelTab selected;
  final ValueChanged<_EditorPanelTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: const ValueKey('node-editor-tabs'),
      constraints: BoxConstraints(
        minHeight: AppDesignTokens.of(context).minimumTarget,
      ),
      child: Row(
        children: [
          for (final tab in _EditorPanelTab.values)
            Expanded(
              child: Semantics(
                key: ValueKey('node-editor-tab-${tab.name}'),
                button: true,
                selected: selected == tab,
                child: InkWell(
                  onTap: () => onSelected(tab),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: selected == tab
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        switch (tab) {
                          _EditorPanelTab.edit => 'Edit',
                          _EditorPanelTab.type => 'Type',
                          _EditorPanelTab.links => 'Links',
                        },
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: selected == tab
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected == tab
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KanbanWipSummary extends StatefulWidget {
  const _KanbanWipSummary({required this.controller});

  final TextEditingController controller;

  @override
  State<_KanbanWipSummary> createState() => _KanbanWipSummaryState();
}

class _KanbanWipSummaryState extends State<_KanbanWipSummary> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(covariant _KanbanWipSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleChanged);
    widget.controller.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final counts = _kanbanColumnCounts(widget.controller.text);
    final todo = counts[KanbanColumn.todo] ?? 0;
    final doing = counts[KanbanColumn.doing] ?? 0;
    final done = counts[KanbanColumn.done] ?? 0;
    final total = todo + doing + done;
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: const Icon(Icons.view_kanban_outlined, size: 16),
          label: Text('Cards $total'),
          visualDensity: VisualDensity.compact,
        ),
        Chip(label: Text('Todo $todo'), visualDensity: VisualDensity.compact),
        Chip(label: Text('Doing $doing'), visualDensity: VisualDensity.compact),
        Chip(label: Text('Done $done'), visualDensity: VisualDensity.compact),
        Text(
          'WIP $doing',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

Map<KanbanColumn, int> _kanbanColumnCounts(String text) {
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

class _EditorSaveStatus extends StatelessWidget {
  const _EditorSaveStatus({
    required this.hasUnsavedChanges,
    required this.isSaving,
    required this.lastSavedAt,
  });

  final bool hasUnsavedChanges;
  final bool isSaving;
  final DateTime? lastSavedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSaving
        ? theme.colorScheme.primary
        : hasUnsavedChanges
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    final icon = isSaving
        ? Icons.sync
        : hasUnsavedChanges
        ? Icons.edit_note
        : Icons.check_circle_outline;
    final label = isSaving
        ? 'Saving changes…'
        : hasUnsavedChanges
        ? 'Unsaved changes'
        : lastSavedAt == null
        ? 'No changes yet'
        : 'Saved ${TimeOfDay.fromDateTime(lastSavedAt!).format(context)}';

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _SlashCommand {
  const _SlashCommand({
    required this.name,
    required this.description,
    required this.icon,
    required this.insertText,
    this.apply,
  });

  final String name;
  final String description;
  final IconData icon;
  final String insertText;
  final VoidCallback? apply;
}

class _NodeEditorTemplate {
  const _NodeEditorTemplate({
    required this.title,
    required this.icon,
    required this.body,
    this.checklist,
    this.tags = const [],
  });

  final String title;
  final IconData icon;
  final String body;
  final String? checklist;
  final List<String> tags;
}

List<_NodeEditorTemplate> _templatesFor(NodeType type) {
  final common = [
    const _NodeEditorTemplate(
      title: 'Daily plan',
      icon: Icons.today_outlined,
      body: 'Top priorities:\n- \n\nSchedule:\n\nNotes:\n\nEnd-of-day review:',
      checklist: 'Pick top 3\nSchedule focus block\nReview day',
      tags: ['daily'],
    ),
    const _NodeEditorTemplate(
      title: 'Meeting notes',
      icon: Icons.groups_2_outlined,
      body:
          'Agenda:\n- \n\nDecisions:\n- \n\nAction items:\n- [ ] \n\nFollow-up:',
      checklist: 'Send recap\nCreate follow-up tasks',
      tags: ['meeting'],
    ),
    const _NodeEditorTemplate(
      title: 'Project brief',
      icon: Icons.account_tree_outlined,
      body: 'Outcome:\n\nScope:\n\nConstraints:\n\nMilestones:\n- \n\nRisks:',
      checklist: 'Define outcome\nMap milestones\nIdentify risks',
      tags: ['project'],
    ),
    const _NodeEditorTemplate(
      title: 'Weekly review',
      icon: Icons.insights_outlined,
      body: 'Wins:\n- \n\nStuck:\n- \n\nLessons:\n- \n\nNext week focus:',
      checklist: 'Review goals\nReview habits\nPlan next week',
      tags: ['review'],
    ),
  ];
  final specific = switch (type) {
    NodeType.goal => [
      const _NodeEditorTemplate(
        title: 'OKR goal',
        icon: Icons.flag_outlined,
        body:
            'Objective:\n\nKey results:\n- KR1:\n- KR2:\n\nMilestones:\n- \n\nReview cadence:',
        checklist: 'Define KR1\nDefine KR2\nSet review cadence',
        tags: ['okr'],
      ),
    ],
    NodeType.habit => [
      const _NodeEditorTemplate(
        title: 'Habit design',
        icon: Icons.repeat_rounded,
        body:
            'Trigger:\n\nRoutine:\n\nReward:\n\nMinimum viable version:\n\nRecovery plan:',
        checklist: 'Pick trigger\nDefine minimum version\nSet recovery rule',
        tags: ['habit'],
      ),
    ],
    NodeType.resource || NodeType.bookmark => [
      const _NodeEditorTemplate(
        title: 'Reading notes',
        icon: Icons.menu_book_outlined,
        body:
            'Source:\n\nSummary:\n\nKey ideas:\n- \n\nQuotes:\n- \n\nNext action:',
        checklist: 'Capture source\nExtract key ideas\nLink related nodes',
        tags: ['resource'],
      ),
    ],
    _ => const <_NodeEditorTemplate>[],
  };
  return [...specific, ...common];
}

class _RelatedNodeChip extends StatelessWidget {
  const _RelatedNodeChip({
    required this.node,
    required this.label,
    required this.onPreview,
    required this.onEditLabel,
    required this.onRemove,
  });

  final MindmapNode node;
  final String label;
  final VoidCallback onPreview;
  final VoidCallback onEditLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InputChip(
          key: ValueKey('related-node-preview-${node.id}'),
          avatar: Icon(
            NodeVisuals.icon(node.type),
            color: NodeVisuals.color(context, node.type),
            size: 14,
          ),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              '${node.title} · $label',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          onPressed: onPreview,
          onDeleted: onRemove,
        ),
        PopupMenuButton<String>(
          key: ValueKey('related-node-menu-${node.id}'),
          tooltip: 'Node actions',
          icon: const Icon(Icons.more_horiz_rounded, size: 18),
          onSelected: (action) {
            switch (action) {
              case 'preview':
                onPreview();
              case 'label':
                onEditLabel();
              case 'remove':
                onRemove();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'preview', child: Text('Open preview')),
            PopupMenuItem(value: 'label', child: Text('Edit label')),
            PopupMenuItem(value: 'remove', child: Text('Remove link')),
          ],
        ),
      ],
    );
  }
}

class _EditorSectionHeader extends StatelessWidget {
  const _EditorSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _BodyToolButton extends StatelessWidget {
  const _BodyToolButton({
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = icon == null ? Text(label ?? '') : Icon(icon, size: 18);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        child: child,
      ),
    );
  }
}
