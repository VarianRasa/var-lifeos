/// Global command palette for searching, filtering, jumping, and quick create.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../mindmap/application/mindmap_mutation_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/node_template.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/smart_node_view.dart';
import '../mindmap/domain/workspace_context.dart';
import 'domain/command_date_parser.dart';
import 'domain/command_node_query.dart';
import 'domain/command_palette_entry.dart';
import 'domain/quick_create_command_parser.dart';

typedef CommandNodeCallback = void Function(MindmapNode node);
typedef CommandDateCallback = void Function(DateTime date);

Future<void> showGlobalCommandPalette(
  BuildContext context, {
  DateTime? initialDate,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        insetPadding: const EdgeInsets.all(20),
        contentPadding: const EdgeInsets.all(14),
        content: GlobalCommandPalette(
          initialDate: initialDate ?? DateTime.now().dateOnly,
          onOpenNode: (node) {
            Navigator.of(dialogContext).pop();
            if (context.mounted) {
              goToDay(context, node.day, highlightNodeId: node.id);
            }
          },
          onJumpToDate: (date) {
            Navigator.of(dialogContext).pop();
            if (context.mounted) goToDay(context, date);
          },
        ),
      );
    },
  );
}

class GlobalCommandPalette extends ConsumerStatefulWidget {
  const GlobalCommandPalette({
    required this.initialDate,
    required this.onOpenNode,
    required this.onJumpToDate,
    super.key,
  });

  final DateTime initialDate;
  final CommandNodeCallback onOpenNode;
  final CommandDateCallback onJumpToDate;

  @override
  ConsumerState<GlobalCommandPalette> createState() =>
      _GlobalCommandPaletteState();
}

class _GlobalCommandPaletteState extends ConsumerState<GlobalCommandPalette> {
  final _searchController = TextEditingController();
  final _dateFilterController = TextEditingController();
  final _createTitleController = TextEditingController();
  final _createDateController = TextEditingController();

  NodeType? _typeFilter;
  NodeStatus? _statusFilter;
  SmartNodeViewType? _smartViewFilter;
  String? _tagFilter;
  String? _projectFilter;
  String? _areaFilter;
  NodeType _createType = NodeType.task;
  String? _selectedTemplateId;
  RecurringRoutinePlan? _routinePlan;
  Set<String> _selectedRoutineIds = const {};
  String _query = '';
  String? _dateFilterError;
  String? _createTitleError;
  String? _createDateError;

  @override
  void initState() {
    super.initState();
    _createDateController.text = dayKey(widget.initialDate);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dateFilterController.dispose();
    _createTitleController.dispose();
    _createDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(allMindmapNodesProvider);
    final viewport = MediaQuery.sizeOf(context);

    return SizedBox(
      width: math.min(viewport.width - 40, 760),
      height: math.min(viewport.height - 80, 640),
      child: nodes.when(
        data: _buildLoaded,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(child: Text('Unable to load index')),
      ),
    );
  }

  Widget _buildLoaded(List<MindmapNode> nodes) {
    final theme = Theme.of(context);
    final today = ref.watch(currentDateProvider);
    final smartViews = SmartNodeViews.fromNodes(today: today, nodes: nodes);
    final filteredNodes = _filterNodes(nodes, smartViews);
    final commandEntries = commandPaletteEntriesFromQuery(
      query: _query,
      today: today,
      defaultDay: widget.initialDate,
      filteredNodes: filteredNodes,
    );
    final tags = _availableTags(nodes);
    final workspaceContexts = WorkspaceContexts.fromNodes(nodes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.manage_search, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Command', style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('global-command-search-field'),
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Search all nodes',
            hintText: 'title, tag, type, status, date',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _QuickCreatePanel(
                  titleController: _createTitleController,
                  dateController: _createDateController,
                  selectedType: _createType,
                  titleError: _createTitleError,
                  dateError: _createDateError,
                  selectedTemplateId: _selectedTemplateId,
                  routinePlan: _routinePlan,
                  selectedRoutineIds: _selectedRoutineIds,
                  onTypeChanged: _changeCreateType,
                  onTemplateChanged: _applyCreateTemplate,
                  onCreate: _quickCreate,
                  onPreviewRoutines: _previewRoutines,
                  onRoutineSelectionChanged: _toggleRoutineSelection,
                  onApplySelectedRoutines: _applySelectedRoutines,
                  onDateChanged: _handleCreateDateChanged,
                ),
                const Divider(height: 18),
                _FilterPanel(
                  smartViewFilter: _smartViewFilter,
                  typeFilter: _typeFilter,
                  statusFilter: _statusFilter,
                  tagFilter: _tagFilter,
                  projectFilter: _projectFilter,
                  areaFilter: _areaFilter,
                  smartViews: smartViews.views,
                  tags: tags,
                  projects: workspaceContexts.projects,
                  areas: workspaceContexts.areas,
                  dateFilterController: _dateFilterController,
                  dateFilterError: _dateFilterError,
                  onTypeChanged: (type) {
                    setState(() {
                      _typeFilter = _typeFilter == type ? null : type;
                    });
                  },
                  onSmartViewChanged: (view) {
                    setState(() {
                      _smartViewFilter = _smartViewFilter == view ? null : view;
                    });
                  },
                  onStatusChanged: (status) {
                    setState(() {
                      _statusFilter = _statusFilter == status ? null : status;
                    });
                  },
                  onTagChanged: (tag) {
                    setState(() => _tagFilter = _tagFilter == tag ? null : tag);
                  },
                  onProjectChanged: (project) {
                    setState(() {
                      _projectFilter = _projectFilter == project
                          ? null
                          : project;
                      if (_projectFilter != null) _areaFilter = null;
                    });
                  },
                  onAreaChanged: (area) {
                    setState(() {
                      _areaFilter = _areaFilter == area ? null : area;
                      if (_areaFilter != null) _projectFilter = null;
                    });
                  },
                  onDateChanged: (_) => setState(() => _dateFilterError = null),
                  onJumpToDate: _jumpToDate,
                ),
                const SizedBox(height: 10),
                if (commandEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No matching commands')),
                  )
                else
                  Column(
                    children: [
                      for (
                        var index = 0;
                        index < commandEntries.length;
                        index++
                      )
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == commandEntries.length - 1 ? 0 : 8,
                          ),
                          child: _buildCommandEntryTile(commandEntries[index]),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommandEntryTile(CommandPaletteEntry entry) {
    return switch (entry.kind) {
      CommandPaletteEntryKind.quickCreate => _QuickCreateCommandTile(
        command: entry.quickCreateCommand!,
        onTap: () => _createFromCommand(entry.quickCreateCommand!),
      ),
      CommandPaletteEntryKind.jumpDate => _JumpDateCommandTile(
        command: entry.dateCommand!,
        onTap: () => widget.onJumpToDate(entry.dateCommand!.date),
      ),
      CommandPaletteEntryKind.node => _CommandResultTile(
        node: entry.node!,
        onTap: () => widget.onOpenNode(entry.node!),
      ),
    };
  }

  List<MindmapNode> _filterNodes(
    List<MindmapNode> nodes,
    SmartNodeViews smartViews,
  ) {
    final commandQuery = _currentCommandQuery();
    final dateFilter = _dateFilterController.text.trim().isEmpty
        ? null
        : DateTime.tryParse(_dateFilterController.text.trim())?.dateOnly;

    final sourceNodes = _smartViewFilter == null
        ? nodes
        : smartViews.nodesFor(_smartViewFilter);

    final filtered = sourceNodes.where((node) {
      if (_typeFilter != null && node.type != _typeFilter) return false;
      if (_statusFilter != null && node.status != _statusFilter) return false;
      if (_tagFilter != null && !node.tags.contains(_tagFilter)) return false;
      if (_projectFilter != null && node.project != _projectFilter) {
        return false;
      }
      if (_areaFilter != null && node.area != _areaFilter) return false;
      if (dateFilter != null && !node.day.isSameDay(dateFilter)) return false;
      if (commandQuery.isEmpty) return true;
      return commandQuery.matches(node);
    }).toList();

    filtered.sort(_compareCommandNodes);
    return filtered;
  }

  List<String> _availableTags(List<MindmapNode> nodes) {
    final tags = <String>{};
    for (final node in nodes) {
      tags.addAll(node.tags);
    }
    return tags.toList()..sort();
  }

  void _jumpToDate() {
    final rawDate = _dateFilterController.text.trim();
    final date = DateTime.tryParse(rawDate)?.dateOnly;
    if (date == null) {
      setState(() => _dateFilterError = 'Use YYYY-MM-DD');
      return;
    }
    widget.onJumpToDate(date);
  }

  Future<void> _quickCreate() async {
    final title = _createTitleController.text.trim();
    final enteredDate = DateTime.tryParse(
      _createDateController.text.trim(),
    )?.dateOnly;
    final commandQuery = _currentCommandQuery();
    final date = commandQuery.day ?? enteredDate;

    setState(() {
      _createTitleError = title.isEmpty ? 'Title is required' : null;
      _createDateError = enteredDate == null && commandQuery.day == null
          ? 'Use YYYY-MM-DD'
          : null;
    });
    if (title.isEmpty || date == null) return;
    final template = _selectedTemplate();

    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: _quickCreateType(template, commandQuery),
      title: title,
      body: template?.body ?? '',
      day: date,
      status: _quickCreateStatus(template, commandQuery),
      priority: _quickCreatePriority(template, commandQuery),
      project: _quickCreateProject(template, commandQuery),
      area: _quickCreateArea(template, commandQuery),
      tags: _quickCreateTags(template, commandQuery),
      dueDate: _quickCreateDueDate(date, commandQuery),
      progress: template?.progress ?? 0,
      isPinned: _quickCreatePinned(),
      isArchived: _quickCreateArchived(),
      checklist: _quickCreateChecklist(template),
      relatedNodeIds: commandQuery.relatedNodeIds,
      data: template?.data ?? const {},
      now: DateTime.now(),
    );

    final saved = await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(node);
    widget.onOpenNode(saved);
  }

  Future<void> _createFromCommand(QuickCreateCommand command) async {
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: command.type,
      title: command.title,
      body: command.body,
      day: command.day,
      status: command.status,
      priority: command.priority,
      project: command.project,
      area: command.area,
      tags: command.tags,
      dueDate: command.dueDate,
      progress: command.progress,
      isPinned: command.isPinned,
      isArchived: command.isArchived,
      checklist: _checklistFromCommand(command),
      relatedNodeIds: command.relatedNodeIds,
      data: command.data,
      now: DateTime.now(),
    );

    final saved = await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(node);
    widget.onOpenNode(saved);
  }

  Future<void> _previewRoutines() async {
    final date = DateTime.tryParse(_createDateController.text.trim())?.dateOnly;

    setState(() {
      _createDateError = date == null ? 'Use YYYY-MM-DD' : null;
    });
    if (date == null) return;

    final repository = ref.read(mindmapRepositoryProvider);
    final plan = await previewRecurringRoutines(
      repository: repository,
      day: date,
      now: DateTime.now(),
    );
    if (!mounted) return;

    setState(() {
      _routinePlan = plan;
      _selectedRoutineIds = {
        for (final item in plan.items)
          if (item.willCreate) item.routine.id,
      };
    });
  }

  void _toggleRoutineSelection(String routineId) {
    setState(() {
      final nextIds = {..._selectedRoutineIds};
      if (!nextIds.remove(routineId)) nextIds.add(routineId);
      _selectedRoutineIds = nextIds;
    });
  }

  Future<void> _applySelectedRoutines() async {
    final date = DateTime.tryParse(_createDateController.text.trim())?.dateOnly;

    setState(() {
      _createDateError = date == null ? 'Use YYYY-MM-DD' : null;
    });
    if (date == null || _selectedRoutineIds.isEmpty) return;

    final routines = [
      for (final routine in defaultRecurringRoutines)
        if (_selectedRoutineIds.contains(routine.id)) routine,
    ];
    final repository = ref.read(mindmapRepositoryProvider);
    final createdNodes = await applyRecurringRoutines(
      repository: repository,
      day: date,
      routines: routines,
      now: DateTime.now(),
    );
    final nextPlan = await previewRecurringRoutines(
      repository: repository,
      day: date,
      now: DateTime.now(),
    );
    if (!mounted) return;

    setState(() {
      _routinePlan = nextPlan;
      _selectedRoutineIds = {
        for (final item in nextPlan.items)
          if (item.willCreate) item.routine.id,
      };
    });

    invalidateMindmapState(ref, day: date);
    if (createdNodes.isNotEmpty) {
      widget.onOpenNode(createdNodes.first);
    }
  }

  void _handleCreateDateChanged(String value) {
    setState(() {
      _createDateError = null;
      _routinePlan = null;
      _selectedRoutineIds = const {};
    });
  }

  void _changeCreateType(NodeType type) {
    setState(() {
      _createType = type;
      _selectedTemplateId = null;
    });
  }

  void _applyCreateTemplate(NodeTemplate template) {
    setState(() {
      _selectedTemplateId = _selectedTemplateId == template.id
          ? null
          : template.id;
      if (_selectedTemplateId == null) return;
      _createType = template.type;
      _createTitleController.text = template.title;
      _createTitleError = null;
    });
  }

  NodeTemplate? _selectedTemplate() {
    final selectedTemplateId = _selectedTemplateId;
    if (selectedTemplateId == null) return null;
    for (final template in defaultNodeTemplates) {
      if (template.id == selectedTemplateId) return template;
    }
    return null;
  }

  CommandNodeQuery _currentCommandQuery() {
    return commandNodeQueryFromText(
      _query,
      today: ref.read(currentDateProvider),
    );
  }

  NodeType _quickCreateType(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    if (template != null) return template.type;
    if (commandQuery.type != null) return commandQuery.type!;
    return switch (_smartViewFilter) {
      SmartNodeViewType.activeGoals => NodeType.goal,
      SmartNodeViewType.reviews => NodeType.journal,
      _ => _createType,
    };
  }

  NodeStatus _quickCreateStatus(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    if (_statusFilter != null) return _statusFilter!;
    if (commandQuery.status != null) return commandQuery.status!;
    if (_smartViewFilter == SmartNodeViewType.waiting) {
      return NodeStatus.waiting;
    }
    return template?.status ?? NodeStatus.open;
  }

  NodePriority _quickCreatePriority(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    if (_smartViewFilter == SmartNodeViewType.highPriority) {
      return NodePriority.high;
    }
    if (commandQuery.priority != null) return commandQuery.priority!;
    return template?.priority ?? NodePriority.none;
  }

  String _quickCreateProject(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    if (_projectFilter != null) return _projectFilter!;
    if (commandQuery.project.isNotEmpty) return commandQuery.project;
    return template?.project ?? '';
  }

  String _quickCreateArea(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    if (_areaFilter != null) return _areaFilter!;
    if (commandQuery.area.isNotEmpty) return commandQuery.area;
    return template?.area ?? '';
  }

  List<String> _quickCreateTags(
    NodeTemplate? template,
    CommandNodeQuery commandQuery,
  ) {
    return [
      ...?template?.tags,
      if (_tagFilter != null && !(template?.tags.contains(_tagFilter) ?? false))
        _tagFilter!,
      for (final tag in commandQuery.tags)
        if (!(template?.tags.contains(tag) ?? false) && tag != _tagFilter) tag,
      if (_smartViewFilter == SmartNodeViewType.routines) 'routine',
      if (_smartViewFilter == SmartNodeViewType.reviews) 'review',
    ];
  }

  DateTime? _quickCreateDueDate(DateTime date, CommandNodeQuery commandQuery) {
    if (commandQuery.dueDate != null) return commandQuery.dueDate;
    if (_smartViewFilter == SmartNodeViewType.dueSoon) return date;
    return null;
  }

  List<TaskChecklistItem> _quickCreateChecklist(NodeTemplate? template) {
    if (template == null) return const [];
    return [
      for (var index = 0; index < template.checklist.length; index++)
        TaskChecklistItem(
          id: 'template-${template.id}-item-${index + 1}',
          title: template.checklist[index],
        ),
    ];
  }

  bool _quickCreatePinned() {
    return _smartViewFilter == SmartNodeViewType.pinned;
  }

  bool _quickCreateArchived() {
    return _smartViewFilter == SmartNodeViewType.archived;
  }

  List<TaskChecklistItem> _checklistFromCommand(QuickCreateCommand command) {
    return [
      for (var index = 0; index < command.checklistTitles.length; index++)
        TaskChecklistItem(
          id: 'command-checklist-${index + 1}',
          title: command.checklistTitles[index],
        ),
    ];
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.smartViewFilter,
    required this.typeFilter,
    required this.statusFilter,
    required this.tagFilter,
    required this.projectFilter,
    required this.areaFilter,
    required this.smartViews,
    required this.tags,
    required this.projects,
    required this.areas,
    required this.dateFilterController,
    required this.dateFilterError,
    required this.onTypeChanged,
    required this.onSmartViewChanged,
    required this.onStatusChanged,
    required this.onTagChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onDateChanged,
    required this.onJumpToDate,
  });

  final SmartNodeViewType? smartViewFilter;
  final NodeType? typeFilter;
  final NodeStatus? statusFilter;
  final String? tagFilter;
  final String? projectFilter;
  final String? areaFilter;
  final List<SmartNodeView> smartViews;
  final List<String> tags;
  final List<WorkspaceContext> projects;
  final List<WorkspaceContext> areas;
  final TextEditingController dateFilterController;
  final String? dateFilterError;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<SmartNodeViewType> onSmartViewChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<String> onDateChanged;
  final VoidCallback onJumpToDate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final project in projects) ...[
                    FilterChip(
                      key: ValueKey(
                        'global-command-project-${workspaceContextKey(project.name)}',
                      ),
                      label: Text('Project ${project.name}'),
                      selected: projectFilter == project.name,
                      onSelected: (_) => onProjectChanged(project.name),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final area in areas) ...[
                    FilterChip(
                      key: ValueKey(
                        'global-command-area-${workspaceContextKey(area.name)}',
                      ),
                      label: Text('Area ${area.name}'),
                      selected: areaFilter == area.name,
                      onSelected: (_) => onAreaChanged(area.name),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final tag in tags) ...[
                    FilterChip(
                      key: ValueKey('global-command-tag-$tag'),
                      label: Text('#$tag'),
                      selected: tagFilter == tag,
                      onSelected: (_) => onTagChanged(tag),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final type in NodeType.values) ...[
                    FilterChip(
                      key: ValueKey('global-command-type-${type.name}'),
                      label: Text(type.label),
                      selected: typeFilter == type,
                      onSelected: (_) => onTypeChanged(type),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final status in NodeStatus.values) ...[
                    FilterChip(
                      key: ValueKey('global-command-status-${status.name}'),
                      label: Text(status.label),
                      selected: statusFilter == status,
                      onSelected: (_) => onStatusChanged(status),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final view in smartViews) ...[
                    FilterChip(
                      key: ValueKey('global-command-view-${view.type.name}'),
                      label: Text(_smartViewChipLabel(view)),
                      selected: smartViewFilter == view.type,
                      onSelected: (_) => onSmartViewChanged(view.type),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('global-command-date-field'),
                    controller: dateFilterController,
                    decoration: InputDecoration(
                      labelText: 'Filter or jump date',
                      hintText: 'YYYY-MM-DD',
                      errorText: dateFilterError,
                    ),
                    onChanged: onDateChanged,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('global-command-jump-date-button'),
                  tooltip: 'Jump to date',
                  onPressed: onJumpToDate,
                  icon: const Icon(Icons.keyboard_return),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCreatePanel extends StatelessWidget {
  const _QuickCreatePanel({
    required this.titleController,
    required this.dateController,
    required this.selectedType,
    required this.titleError,
    required this.dateError,
    required this.selectedTemplateId,
    required this.routinePlan,
    required this.selectedRoutineIds,
    required this.onTypeChanged,
    required this.onTemplateChanged,
    required this.onCreate,
    required this.onPreviewRoutines,
    required this.onRoutineSelectionChanged,
    required this.onApplySelectedRoutines,
    required this.onDateChanged,
  });

  final TextEditingController titleController;
  final TextEditingController dateController;
  final NodeType selectedType;
  final String? titleError;
  final String? dateError;
  final String? selectedTemplateId;
  final RecurringRoutinePlan? routinePlan;
  final Set<String> selectedRoutineIds;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<NodeTemplate> onTemplateChanged;
  final VoidCallback onCreate;
  final VoidCallback onPreviewRoutines;
  final ValueChanged<String> onRoutineSelectionChanged;
  final VoidCallback onApplySelectedRoutines;
  final ValueChanged<String> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick create', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final type in NodeType.values) ...[
                ChoiceChip(
                  key: ValueKey('global-command-create-type-${type.name}'),
                  label: Text(type.label),
                  selected: selectedType == type,
                  onSelected: (_) => onTypeChanged(type),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final template in defaultNodeTemplates) ...[
                ChoiceChip(
                  key: ValueKey('global-command-template-${template.id}'),
                  label: Text(template.label),
                  selected: selectedTemplateId == template.id,
                  onSelected: (_) => onTemplateChanged(template),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                key: const ValueKey('global-command-create-title-field'),
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Title',
                  errorText: titleError,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('global-command-create-date-field'),
                controller: dateController,
                decoration: InputDecoration(
                  labelText: 'Date',
                  hintText: 'YYYY-MM-DD',
                  errorText: dateError,
                ),
                onChanged: onDateChanged,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('global-command-create-button'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('global-command-apply-routines-button'),
              onPressed: onPreviewRoutines,
              icon: const Icon(Icons.auto_awesome_motion_outlined),
              label: const Text('Routines'),
            ),
          ],
        ),
        if (routinePlan != null) ...[
          const SizedBox(height: 10),
          _CommandRoutinePlanner(
            plan: routinePlan!,
            selectedRoutineIds: selectedRoutineIds,
            onSelectionChanged: onRoutineSelectionChanged,
            onApplySelected: onApplySelectedRoutines,
          ),
        ],
      ],
    );
  }
}

class _CommandRoutinePlanner extends StatelessWidget {
  const _CommandRoutinePlanner({
    required this.plan,
    required this.selectedRoutineIds,
    required this.onSelectionChanged,
    required this.onApplySelected,
  });

  final RecurringRoutinePlan plan;
  final Set<String> selectedRoutineIds;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onApplySelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('global-command-routine-planner'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CommandRoutineChip(
                  icon: Icons.add_task_outlined,
                  label: 'Ready to create ${plan.readyCount}',
                ),
                _CommandRoutineChip(
                  icon: Icons.history_toggle_off_outlined,
                  label: 'Existing ${plan.skippedCount}',
                ),
                _CommandRoutineChip(
                  icon: Icons.event_busy_outlined,
                  label: 'Not due ${plan.notDueCount}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey(
                  'global-command-apply-selected-routines-button',
                ),
                onPressed: selectedRoutineIds.isEmpty ? null : onApplySelected,
                icon: const Icon(Icons.playlist_add_check_outlined),
                label: Text(
                  selectedRoutineIds.isEmpty
                      ? 'No routines selected'
                      : 'Apply selected ${selectedRoutineIds.length}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in plan.items)
                  _CommandRoutineRow(
                    item: item,
                    selected: selectedRoutineIds.contains(item.routine.id),
                    onChanged: item.willCreate
                        ? () => onSelectionChanged(item.routine.id)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandRoutineChip extends StatelessWidget {
  const _CommandRoutineChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Text(label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _CommandRoutineRow extends StatelessWidget {
  const _CommandRoutineRow({
    required this.item,
    required this.selected,
    required this.onChanged,
  });

  final RecurringRoutinePlanItem item;
  final bool selected;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _routineStatusColor(theme, item.status);

    return FilterChip(
      key: ValueKey('global-command-routine-select-${item.routine.id}'),
      selected: selected,
      showCheckmark: item.willCreate,
      onSelected: onChanged == null ? null : (_) => onChanged!(),
      tooltip: _routineRuleLabel(item.routine.rule),
      avatar: Icon(
        _routineStatusIcon(item.status),
        size: 16,
        color: statusColor,
      ),
      label: Text(
        '${item.routine.label} - ${item.statusLabel}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _CommandResultTile extends StatelessWidget {
  const _CommandResultTile({required this.node, required this.onTap});

  final MindmapNode node;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('global-command-result-${node.id}'),
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      leading: Icon(_nodeIcon(node.type)),
      title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          node.type.label,
          dayKey(node.day),
          if (node.project.isNotEmpty) 'Project ${node.project}',
          if (node.area.isNotEmpty) 'Area ${node.area}',
          if (node.tags.isNotEmpty) '#${node.tags.first}',
        ].join(' - '),
      ),
      trailing: const Icon(Icons.arrow_forward),
      onTap: onTap,
    );
  }
}

class _JumpDateCommandTile extends StatelessWidget {
  const _JumpDateCommandTile({required this.command, required this.onTap});

  final CommandDateResult command;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('global-command-jump-result-${dayKey(command.date)}'),
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      leading: const Icon(Icons.event_available_outlined),
      title: Text(command.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('Calendar day'),
      trailing: const Icon(Icons.keyboard_return),
      onTap: onTap,
    );
  }
}

class _QuickCreateCommandTile extends StatelessWidget {
  const _QuickCreateCommandTile({required this.command, required this.onTap});

  final QuickCreateCommand command;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('global-command-quick-create-result'),
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      leading: Icon(_nodeIcon(command.type)),
      title: Text(command.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          dayKey(command.day),
          if (command.calendarPayload != null)
            command.calendarPayload!.subtitle,
          if (command.timeBlock != null) command.timeBlock!.rangeLabel,
          if (command.dueDate != null) 'Due ${dayKey(command.dueDate!)}',
          if (command.status != NodeStatus.open) command.status.label,
          if (command.priority != NodePriority.none) command.priority.label,
          if (command.progress > 0)
            '${(command.progress * 100).round()}% progress',
          if (command.isPinned) 'Pinned',
          if (command.isArchived) 'Archived',
          if (command.checklistTitles.isNotEmpty)
            '${command.checklistTitles.length} checklist',
          if (command.relatedNodeIds.isNotEmpty)
            '${command.relatedNodeIds.length} links',
          if (command.project.isNotEmpty) 'Project ${command.project}',
          if (command.area.isNotEmpty) 'Area ${command.area}',
          for (final tag in command.tags.take(2)) '#$tag',
        ].join(' - '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.add_circle_outline),
      onTap: onTap,
    );
  }
}

int _compareCommandNodes(MindmapNode a, MindmapNode b) {
  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
  final day = b.day.compareTo(a.day);
  if (day != 0) return day;
  return a.title.compareTo(b.title);
}

IconData _nodeIcon(NodeType type) => switch (type) {
  NodeType.task => Icons.check_circle_outline,
  NodeType.kanban => Icons.view_kanban_outlined,
  NodeType.plan => Icons.route_outlined,
  NodeType.note => Icons.notes_outlined,
  NodeType.journal => Icons.book_outlined,
  NodeType.habit => Icons.repeat_outlined,
  NodeType.goal => Icons.flag_outlined,
  NodeType.link => Icons.link_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

String _smartViewChipLabel(SmartNodeView view) {
  final label = switch (view.type) {
    SmartNodeViewType.highPriority => 'High',
    _ => view.type.label,
  };
  return '$label ${view.nodes.length}';
}

Color _routineStatusColor(
  ThemeData theme,
  RecurringRoutinePlanItemStatus status,
) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => theme.colorScheme.primary,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      theme.colorScheme.tertiary,
    RecurringRoutinePlanItemStatus.skippedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.snoozedToday => theme.colorScheme.outline,
    RecurringRoutinePlanItemStatus.notDue => theme.colorScheme.outline,
  };
}

IconData _routineStatusIcon(RecurringRoutinePlanItemStatus status) {
  return switch (status) {
    RecurringRoutinePlanItemStatus.ready => Icons.add_task_outlined,
    RecurringRoutinePlanItemStatus.skippedExisting =>
      Icons.check_circle_outline,
    RecurringRoutinePlanItemStatus.skippedToday => Icons.block_outlined,
    RecurringRoutinePlanItemStatus.snoozedToday => Icons.snooze_outlined,
    RecurringRoutinePlanItemStatus.notDue => Icons.event_busy_outlined,
  };
}

String _routineRuleLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Every day',
    RecurringFrequency.weekly => 'Weekly on ${_weekdayName(rule.weekday)}',
    RecurringFrequency.monthly => 'Monthly on day ${rule.dayOfMonth}',
  };
}

String _weekdayName(int? weekday) {
  return switch (weekday) {
    DateTime.monday => 'Monday',
    DateTime.tuesday => 'Tuesday',
    DateTime.wednesday => 'Wednesday',
    DateTime.thursday => 'Thursday',
    DateTime.friday => 'Friday',
    DateTime.saturday => 'Saturday',
    DateTime.sunday => 'Sunday',
    _ => 'schedule',
  };
}
