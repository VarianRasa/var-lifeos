import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../calendar/domain/calendar_node_payload.dart';
import '../application/mindmap_providers.dart';
import '../domain/automation_rule.dart';
import '../domain/canvas_position.dart';
import '../domain/custom_node_template_codec.dart';
import '../domain/kanban_board.dart';
import '../domain/markdown_checklist_parser.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_knowledge_index.dart';
import '../domain/node_template.dart';
import '../domain/recurring_routine.dart';
import 'mindmap_canvas.dart'; // for nodeIcon, nodeColor

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
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onSave;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback? onCollapse;
  final ValueChanged<MindmapNode>? onOpenNode;

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
    _initDraft(widget.node);
    for (final controller in _dirtyControllers) {
      controller.addListener(_markDirty);
    }
    _bodyController.addListener(_onBodyChanged);
  }

  List<TextEditingController> get _dirtyControllers => [
    _titleController,
    _bodyController,
    _projectController,
    _areaController,
    _tagsController,
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
    _dueDateController.text = node.dueDate == null ? '' : dayKey(node.dueDate!);
    _progressController.text = node.progress == 0
        ? ''
        : (node.progress * 100).round().toString();
    _relatedNodeIdsController.text = node.relatedNodeIds.join(', ');
    _attachmentsController.text = _attachmentsTextFromData(node.data);

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
    for (final controller in _dirtyControllers) {
      controller.removeListener(_markDirty);
    }
    _bodyController.removeListener(_onBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    _projectController.dispose();
    _areaController.dispose();
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

  void _addQuickChecklistItem() {
    final item = _quickChecklistItemController.text.trim();
    if (item.isEmpty) return;
    final existing = _checklistController.text.trimRight();
    _checklistController.text = existing.isEmpty ? item : '$existing\n$item';
    _checklistController.selection = TextSelection.collapsed(
      offset: _checklistController.text.length,
    );
    _quickChecklistItemController.clear();
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

  void _addTag(String tag) {
    final tags = _parseLines(_tagsController.text.replaceAll(',', '\n'));
    if (tags.any((existing) => existing.toLowerCase() == tag.toLowerCase())) {
      return;
    }
    tags.add(tag);
    _tagsController.text = tags.join(', ');
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
                ),
              ),
            if (query.isNotEmpty &&
                !suggestions.any((n) => n.title.trim().toLowerCase() == query))
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
      project: _hasContext ? _projectController.text.trim() : '',
      area: _hasContext ? _areaController.text.trim() : '',
      tags: _hasTags
          ? _parseLines(_tagsController.text.replaceAll(',', '\n'))
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
      (icon: nodeIcon(_draft.type), label: 'Type', value: _draft.type.label),
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

    return Container(
      key: const ValueKey('node-object-properties-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dataset_linked_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Object properties',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('copy-node-wikilink'),
                onPressed: title.isEmpty
                    ? null
                    : () => unawaited(_copyNodeWikiLink(title)),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy [[link]]'),
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

  Widget _buildStructuredTypeSection() {
    final type = _draft.type;
    if (!{
      NodeType.contact,
      NodeType.metric,
      NodeType.expense,
      NodeType.resource,
      NodeType.bookmark,
    }.contains(type)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _buildFeatureField(
        title: '${type.label} Details',
        child: switch (type) {
          NodeType.contact => Column(
            children: [
              _editorRow(
                TextField(
                  controller: _contactRoleController,
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                TextField(
                  controller: _contactCompanyController,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
              ),
              const SizedBox(height: 8),
              _editorRow(
                TextField(
                  controller: _contactEmailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextField(
                  controller: _contactPhoneController,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          NodeType.metric => Column(
            children: [
              _editorRow(
                TextField(
                  controller: _metricValueController,
                  decoration: const InputDecoration(labelText: 'Value'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _metricUnitController,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
              const SizedBox(height: 8),
              _editorRow(
                TextField(
                  controller: _metricTrendController,
                  decoration: const InputDecoration(labelText: 'Trend'),
                ),
                TextField(
                  controller: _metricTargetController,
                  decoration: const InputDecoration(labelText: 'Target'),
                ),
              ),
            ],
          ),
          NodeType.expense => Column(
            children: [
              _editorRow(
                TextField(
                  controller: _expenseAmountController,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _expenseCategoryController,
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
              ),
              const SizedBox(height: 8),
              _editorRow(
                TextField(
                  controller: _expenseMerchantController,
                  decoration: const InputDecoration(labelText: 'Merchant'),
                ),
                TextField(
                  controller: _expensePaymentController,
                  decoration: const InputDecoration(labelText: 'Payment'),
                ),
              ),
            ],
          ),
          NodeType.resource => TextField(
            controller: _noteSourceController,
            decoration: const InputDecoration(
              labelText: 'Source',
              hintText: 'URL, book, paper, file, doc, etc.',
            ),
          ),
          NodeType.bookmark => TextField(
            controller: _noteSourceController,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://...',
            ),
            keyboardType: TextInputType.url,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
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
                      nodeIcon(backlink.node.type),
                      color: nodeColor(backlink.node.type),
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
                      nodeIcon(node.type),
                      color: nodeColor(node.type),
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
            Icon(nodeIcon(node.type), color: nodeColor(node.type)),
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
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text('Smart actions', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: actions),
        ],
      ),
    );
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
      );
      _progressController.text = '100';
      _hasProgress = true;
      _hasUnsavedChanges = true;
    });
  }

  void _rescheduleDraftTomorrow() {
    final tomorrow = DateTime.now().dateOnly.addDays(1);
    setState(() {
      _draft = _draft.copyWith(dueDate: tomorrow);
      _dueDateController.text = dayKey(tomorrow);
      _hasDueDate = true;
      _hasUnsavedChanges = true;
    });
  }

  void _pinDraft() {
    setState(() {
      _draft = _draft.copyWith(isPinned: true);
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
          Row(
            children: [
              const Icon(Icons.attach_file_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Attachments', style: theme.textTheme.titleSmall),
              ),
              Text('${attachments.length}', style: theme.textTheme.labelSmall),
              const SizedBox(width: 8),
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
              Icon(Icons.hub_outlined, color: nodeColor(_draft.type), size: 18),
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
                    nodeIcon(type),
                    color: nodeColor(type),
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
                      nodeIcon(node.type),
                      color: nodeColor(node.type),
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

  Widget _editorRow(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildFeatureField({
    required String title,
    required Widget child,
    VoidCallback? onRemove,
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

  Future<void> _showNodeToolsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.38,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 28,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Node tools',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close tools',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildTemplateButton(),
                      const SizedBox(height: 12),
                      _buildSmartActionsSection(),
                      const SizedBox(height: 12),
                      _buildConnectionSection(),
                      const SizedBox(height: 12),
                      _buildBacklinksSection(),
                      const SizedBox(height: 12),
                      _buildAttachmentsSection(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: ShapeDecoration(
                  color: nodeColor(_draft.type).withValues(alpha: 0.16),
                  shape: CircleBorder(
                    side: BorderSide(
                      color: nodeColor(_draft.type).withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: Icon(
                  nodeIcon(_draft.type),
                  size: 18,
                  color: nodeColor(_draft.type),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit Node', style: theme.textTheme.titleMedium),
                    Text(
                      _draft.type.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _buildFeatureMenu(),
              PopupMenuButton<VoidCallback>(
                key: const ValueKey('node-editor-overflow-menu'),
                tooltip: 'More node actions',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  _headerActionItem(
                    icon: Icons.open_in_full_rounded,
                    label: 'Open node page',
                    onPressed: () => context.go(
                      '/calendar/${dayKey(_draft.day)}/node/${_draft.id}',
                    ),
                  ),
                  _headerActionItem(
                    icon: Icons.build_circle_outlined,
                    label: 'Node tools',
                    onPressed: () => unawaited(_showNodeToolsSheet()),
                  ),
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
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
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
                        _applyTypeDefaults(v);
                        _hasUnsavedChanges = true;
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
                _buildObjectPropertiesPanel(),
                const SizedBox(height: 16),
                const _EditorSectionHeader(title: 'Core'),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('node-editor-body-field'),
                  controller: _bodyController,
                  decoration: InputDecoration(
                    labelText: 'Rich description',
                    helperText:
                        'Markdown supported: headings, bold, italic, quotes, lists, links.',
                    counterText: _bodyWordCountLabel(),
                  ),
                  minLines: 6,
                  maxLines: 14,
                ),
                _buildBodyToolbar(),
                _buildSlashCommandSuggestions(),
                const SizedBox(height: 8),
                _buildAutocompleteSuggestions(),
                const SizedBox(height: 16),
                _buildConnectionSection(),
                const SizedBox(height: 12),
                _buildBacklinksSection(),
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

                _buildStructuredTypeSection(),

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _quickChecklistItemController,
                                decoration: const InputDecoration(
                                  hintText: 'Quick add item',
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _addQuickChecklistItem(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.add),
                              tooltip: 'Add checklist item',
                              onPressed: _addQuickChecklistItem,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: const ValueKey('node-editor-checklist-field'),
                          controller: _checklistController,
                          decoration: const InputDecoration(
                            hintText: 'One item per line',
                          ),
                          minLines: 2,
                          maxLines: 5,
                        ),
                      ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const ValueKey('node-editor-tags-field'),
                          controller: _tagsController,
                          decoration: const InputDecoration(
                            hintText: 'Comma separated',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in [
                              'work',
                              'personal',
                              'urgent',
                              'idea',
                              'follow-up',
                            ])
                              ActionChip(
                                label: Text(tag),
                                onPressed: () => _addTag(tag),
                              ),
                          ],
                        ),
                      ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _KanbanWipSummary(controller: _kanbanCardsController),
                        const SizedBox(height: 8),
                        TextField(
                          key: const ValueKey('node-editor-kanban-cards-field'),
                          controller: _kanbanCardsController,
                          decoration: const InputDecoration(
                            hintText: 'todo: Scope\ndoing: Build\ndone: Review',
                            helperText:
                                'Use todo:/doing:/done: prefixes. Delete a line to delete a card.',
                          ),
                          minLines: 3,
                          maxLines: 6,
                        ),
                      ],
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

                if ((_hasNote || _hasLink) &&
                    _draft.type != NodeType.resource &&
                    _draft.type != NodeType.bookmark)
                  _buildFeatureField(
                    title: _hasLink
                        ? _draft.type == NodeType.bookmark
                              ? 'Bookmark URL'
                              : 'Link URL'
                        : _draft.type == NodeType.resource
                        ? 'Resource Source'
                        : 'Source',
                    onRemove: () => setState(() {
                      _hasNote = false;
                      _hasLink = false;
                    }),
                    child: TextField(
                      controller: _noteSourceController,
                      decoration: InputDecoration(
                        hintText: _hasLink
                            ? 'https://...'
                            : _draft.type == NodeType.resource
                            ? 'URL, book, paper, file, doc, etc.'
                            : 'Book, Video, etc.',
                      ),
                    ),
                  ),

                if (_hasCalendarPayload) _buildCalendarPayloadSection(),

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
        // Footer (Save button)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _EditorSaveStatus(
                  hasUnsavedChanges: _hasUnsavedChanges,
                  isSaving: _isSaving,
                  lastSavedAt: _lastSavedAt,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Reset changes',
                onPressed: _hasUnsavedChanges && !_isSaving
                    ? () => setState(() => _initDraft(widget.node))
                    : null,
                icon: const Icon(Icons.undo_rounded),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('save-node'),
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isSaving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ],
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
            nodeIcon(node.type),
            color: nodeColor(node.type),
            size: 14,
          ),
          label: Text('${node.title} ? $label'),
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
