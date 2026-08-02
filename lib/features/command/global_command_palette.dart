/// Global command palette for searching, filtering, jumping, and quick create.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/utils/date_utils.dart';
import '../mindmap/application/collaboration_controller.dart';
import '../mindmap/application/mindmap_mutation_controller.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/custom_node_template_codec.dart';
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

final List<_RecentCommand> _recentCommands = <_RecentCommand>[];

Widget _buildCollapsibleSection({
  required BuildContext context,
  required String title,
  required IconData icon,
  required bool isExpanded,
  required VoidCallback onToggle,
  required Widget child,
}) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
      if (isExpanded) ...[const SizedBox(height: 4), child],
    ],
  );
}

Future<void> showGlobalCommandPalette(
  BuildContext context, {
  DateTime? initialDate,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final isMobile = viewport.width <= LayoutConstants.mobileBreakpoint;
  return showDialog<void>(
    context: context,
    useSafeArea: !isMobile,
    builder: (dialogContext) {
      final palette = GlobalCommandPalette(
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
      );
      if (isMobile) {
        return Dialog.fullscreen(
          key: const ValueKey('global-command-mobile-dialog'),
          child: SafeArea(
            child: Padding(padding: const EdgeInsets.all(16), child: palette),
          ),
        );
      }
      return Dialog(
        key: const ValueKey('global-command-desktop-dialog'),
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(14), child: palette),
      );
    },
  );
}

class GlobalCommandPalette extends ConsumerStatefulWidget {
  const GlobalCommandPalette({
    required this.initialDate,
    required this.onOpenNode,
    required this.onJumpToDate,
    this.defaultExpanded = false,
    super.key,
  });

  final DateTime initialDate;
  final CommandNodeCallback onOpenNode;
  final CommandDateCallback onJumpToDate;
  final bool defaultExpanded;

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
  String? _createContextQuery;
  int _activeIndex = 0;
  String? _dateFilterError;
  String? _createTitleError;
  String? _createDateError;
  List<_CommandSavedSearch> _savedSearches = const [];
  List<_CommandSavedView> _customSavedViews = const [];
  List<_CommandGraphFilter> _graphFilters = const [];
  List<NodeTemplate> _customTemplates = const [];

  late bool _expandedSavedSearches =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));
  late bool _expandedSavedViews =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));
  late bool _expandedPowerActions =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));
  late bool _expandedNavigation =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));
  late bool _expandedQuickCreate =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));
  late bool _expandedFilters =
      widget.defaultExpanded ||
      (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST'));

  @override
  void initState() {
    super.initState();
    _createDateController.text = dayKey(widget.initialDate);
    _loadRecentCommands();
    _loadSavedSearches();
    _loadCustomSavedViews();
    _loadGraphFilters();
    _loadCustomTemplates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dateFilterController.dispose();
    _createTitleController.dispose();
    _createDateController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentCommands() async {
    final raw = await SharedPreferencesAsync().getString('recent_commands');
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return;
      _recentCommands
        ..clear()
        ..addAll(decoded.map(_RecentCommand.fromJson).nonNulls.take(5));
      if (mounted) setState(() {});
    } on FormatException {
      return;
    }
  }

  Future<void> _persistRecentCommands() async {
    await SharedPreferencesAsync().setString(
      'recent_commands',
      jsonEncode([for (final command in _recentCommands) command.toJson()]),
    );
  }

  Future<void> _loadSavedSearches() async {
    final raw = await SharedPreferencesAsync().getString(
      'command_saved_searches',
    );
    if (!mounted) return;
    setState(() => _savedSearches = _decodeCommandSavedSearches(raw));
  }

  Future<void> _persistSavedSearches(List<_CommandSavedSearch> searches) async {
    await SharedPreferencesAsync().setString(
      'command_saved_searches',
      jsonEncode([for (final search in searches) search.toJson()]),
    );
    if (mounted) setState(() => _savedSearches = searches);
  }

  Future<void> _saveCurrentSearch() async {
    final labelController = TextEditingController(
      text: _query.trim().isEmpty ? 'Saved search' : _query.trim(),
    );
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save search'),
        content: TextField(
          controller: labelController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Search name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(labelController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    labelController.dispose();
    if (label == null || label.isEmpty) return;
    await _persistSavedSearches([
      ..._savedSearches,
      _CommandSavedSearch(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: label,
        query: _query,
        typeFilter: _typeFilter,
        statusFilter: _statusFilter,
        smartViewFilter: _smartViewFilter,
        tagFilter: _tagFilter,
        projectFilter: _projectFilter,
        areaFilter: _areaFilter,
        dateFilter: _dateFilterController.text.trim(),
      ),
    ]);
  }

  void _applySavedSearch(_CommandSavedSearch search) {
    _searchController.text = search.query;
    _dateFilterController.text = search.dateFilter;
    setState(() {
      _query = search.query;
      _activeIndex = 0;
      _typeFilter = search.typeFilter;
      _statusFilter = search.statusFilter;
      _smartViewFilter = search.smartViewFilter;
      _tagFilter = search.tagFilter;
      _projectFilter = search.projectFilter;
      _areaFilter = search.areaFilter;
      _dateFilterError = null;
    });
  }

  Future<void> _deleteSavedSearch(String id) async {
    await _persistSavedSearches([
      for (final search in _savedSearches)
        if (search.id != id) search,
    ]);
  }

  Future<void> _loadCustomSavedViews() async {
    final raw = await SharedPreferencesAsync().getString('custom_saved_views');
    if (!mounted) return;
    setState(() => _customSavedViews = _decodeCommandSavedViews(raw));
  }

  Future<void> _loadGraphFilters() async {
    final raw = await SharedPreferencesAsync().getString('graph_saved_filters');
    if (!mounted) return;
    setState(() => _graphFilters = _decodeCommandGraphFilters(raw));
  }

  Future<void> _loadCustomTemplates() async {
    final raw = await SharedPreferencesAsync().getString(
      customNodeTemplatesPreferenceKey,
    );
    if (!mounted) return;
    setState(() {
      try {
        _customTemplates = nodeTemplatesFromJsonList(
          raw == null ? null : jsonDecode(raw),
        );
      } on FormatException {
        _customTemplates = const [];
      }
    });
  }

  void _rememberCommand({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    _recentCommands.removeWhere((command) => command.title == title);
    _recentCommands.insert(
      0,
      _RecentCommand(icon: icon, title: title, subtitle: subtitle),
    );
    if (_recentCommands.length > 5) {
      _recentCommands.removeRange(5, _recentCommands.length);
    }
    unawaited(_persistRecentCommands());
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
    final collabState = ref.watch(collaborationProvider);
    final commandEntries = commandPaletteEntriesFromQuery(
      query: _query,
      today: today,
      defaultDay: widget.initialDate,
      filteredNodes: filteredNodes,
      roomHistory: collabState.roomHistory,
    );
    final tags = _availableTags(nodes);
    final workspaceContexts = WorkspaceContexts.fromNodes(nodes);
    final mutator = _CommandMutator.fromQuery(_query, nodes);

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
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (commandEntries.isNotEmpty) {
                  setState(() {
                    _activeIndex = (_activeIndex + 1) % commandEntries.length;
                  });
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (commandEntries.isNotEmpty) {
                  setState(() {
                    _activeIndex =
                        (_activeIndex - 1 + commandEntries.length) %
                        commandEntries.length;
                  });
                }
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                if (commandEntries.isNotEmpty &&
                    _activeIndex < commandEntries.length) {
                  _executeCommandPaletteEntry(commandEntries[_activeIndex]);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (_query.isNotEmpty) {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _activeIndex = 0;
                  });
                } else {
                  Navigator.of(context).pop();
                }
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey('global-command-search-field'),
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search all nodes',
              hintText: 'title, tag, type, status, date',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              setState(() {
                _query = value;
                if (_looksLikeCommandContext(value)) {
                  _createContextQuery = value;
                }
                _activeIndex = 0;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mutator != null) ...[
                  _CommandMutatorPanel(
                    mutator: mutator,
                    onRun: () => _runCommandMutator(mutator),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_query.trim().isNotEmpty) ...[
                  _QuickCreatePanel(
                    titleController: _createTitleController,
                    dateController: _createDateController,
                    selectedType: _createType,
                    titleError: _createTitleError,
                    dateError: _createDateError,
                    templates: [...defaultNodeTemplates, ..._customTemplates],
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
                        _smartViewFilter = _smartViewFilter == view
                            ? null
                            : view;
                      });
                    },
                    onStatusChanged: (status) {
                      setState(() {
                        _statusFilter = _statusFilter == status ? null : status;
                      });
                    },
                    onTagChanged: (tag) {
                      setState(
                        () => _tagFilter = _tagFilter == tag ? null : tag,
                      );
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
                    onDateChanged: (_) =>
                        setState(() => _dateFilterError = null),
                    onJumpToDate: _jumpToDate,
                  ),
                  const Divider(height: 18),
                  if (commandEntries.isEmpty)
                    _CommandEmptyState(
                      query: _query,
                      onClear: () {
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _activeIndex = 0;
                        });
                      },
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
                              bottom: index == commandEntries.length - 1
                                  ? 0
                                  : 8,
                            ),
                            child: _buildCommandEntryTile(
                              commandEntries[index],
                              isActive: index == _activeIndex,
                            ),
                          ),
                      ],
                    ),
                ] else ...[
                  if (MediaQuery.sizeOf(context).height >= 700 &&
                      _createTitleController.text.trim().isEmpty &&
                      _routinePlan == null &&
                      _recentCommands.isNotEmpty) ...[
                    _RecentCommandPanel(
                      commands: _recentCommands,
                      onSelected: (command) {
                        _searchController.text = command.title;
                        setState(() {
                          _query = command.title;
                          _activeIndex = 0;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Saved searches',
                    icon: Icons.saved_search_outlined,
                    isExpanded: _expandedSavedSearches,
                    onToggle: () => setState(() {
                      _expandedSavedSearches = !_expandedSavedSearches;
                    }),
                    child: _CommandSavedSearchesPanel(
                      searches: _savedSearches,
                      onSave: _saveCurrentSearch,
                      onApply: _applySavedSearch,
                      onDelete: _deleteSavedSearch,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Saved views & presets',
                    icon: Icons.view_quilt_outlined,
                    isExpanded: _expandedSavedViews,
                    onToggle: () => setState(() {
                      _expandedSavedViews = !_expandedSavedViews;
                    }),
                    child: _CommandSavedViewsPanel(
                      customViews: _customSavedViews,
                      graphFilters: _graphFilters,
                      onApply: _applySavedViewPreset,
                      onApplyGraphFilter: _applyGraphFilter,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Power actions',
                    icon: Icons.bolt_outlined,
                    isExpanded: _expandedPowerActions,
                    onToggle: () => setState(() {
                      _expandedPowerActions = !_expandedPowerActions;
                    }),
                    child: _CommandPowerActionsPanel(
                      nodes: nodes,
                      today: today,
                      onCompleteTask: _completeFirstOpenTask,
                      onRescheduleOverdue: _rescheduleOverdueTasks,
                      onCreateWeeklyReview: _createWeeklyReview,
                      onApplyRoutines: _applyReadyRoutinesForToday,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Navigation',
                    icon: Icons.explore_outlined,
                    isExpanded: _expandedNavigation,
                    onToggle: () => setState(() {
                      _expandedNavigation = !_expandedNavigation;
                    }),
                    child: _CommandNavigationPanel(
                      initialDate: widget.initialDate,
                      onNavigate: (route) {
                        _rememberCommand(
                          icon: route.icon,
                          title: route.label,
                          subtitle: 'Navigate',
                        );
                        Navigator.of(context).pop();
                        context.go(route.path);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Quick create',
                    icon: Icons.add_circle_outline,
                    isExpanded: _expandedQuickCreate,
                    onToggle: () => setState(() {
                      _expandedQuickCreate = !_expandedQuickCreate;
                    }),
                    child: _QuickCreatePanel(
                      titleController: _createTitleController,
                      dateController: _createDateController,
                      selectedType: _createType,
                      titleError: _createTitleError,
                      dateError: _createDateError,
                      templates: [...defaultNodeTemplates, ..._customTemplates],
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
                  ),
                  const Divider(height: 18),
                  _buildCollapsibleSection(
                    context: context,
                    title: 'Search filters',
                    icon: Icons.filter_alt_outlined,
                    isExpanded: _expandedFilters,
                    onToggle: () => setState(() {
                      _expandedFilters = !_expandedFilters;
                    }),
                    child: _FilterPanel(
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
                          _smartViewFilter = _smartViewFilter == view
                              ? null
                              : view;
                        });
                      },
                      onStatusChanged: (status) {
                        setState(() {
                          _statusFilter = _statusFilter == status
                              ? null
                              : status;
                        });
                      },
                      onTagChanged: (tag) {
                        setState(
                          () => _tagFilter = _tagFilter == tag ? null : tag,
                        );
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
                      onDateChanged: (_) =>
                          setState(() => _dateFilterError = null),
                      onJumpToDate: _jumpToDate,
                    ),
                  ),
                  if (commandEntries.isNotEmpty) ...[
                    const Divider(height: 18),
                    Column(
                      children: [
                        for (
                          var index = 0;
                          index < commandEntries.length;
                          index++
                        )
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == commandEntries.length - 1
                                  ? 0
                                  : 8,
                            ),
                            child: _buildCommandEntryTile(
                              commandEntries[index],
                              isActive: index == _activeIndex,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _executeCommandPaletteEntry(CommandPaletteEntry entry) {
    switch (entry.kind) {
      case CommandPaletteEntryKind.quickCreate:
        final command = entry.quickCreateCommand!;
        _rememberCommand(
          icon: Icons.add_circle_outline,
          title: command.label,
          subtitle: 'Quick create',
        );
        _createFromCommand(command);
      case CommandPaletteEntryKind.jumpDate:
        final command = entry.dateCommand!;
        _rememberCommand(
          icon: Icons.event_outlined,
          title: command.label,
          subtitle: 'Jump to date',
        );
        widget.onJumpToDate(command.date);
      case CommandPaletteEntryKind.node:
        final node = entry.node!;
        _rememberCommand(
          icon: NodeVisuals.icon(node.type),
          title: node.title,
          subtitle: '${node.type.name} • ${dayKey(node.day)}',
        );
        widget.onOpenNode(node);
      case CommandPaletteEntryKind.collab:
        final link = entry.collabLink!;
        _rememberCommand(
          icon: Icons.people_outline,
          title: 'Join Room',
          subtitle: link,
        );
        final messenger = ScaffoldMessenger.of(context);
        final semantic = AppSemanticColors.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Connecting to room...'),
            duration: Duration(seconds: 2),
          ),
        );
        ref.read(collaborationProvider.notifier).joinRoom(link).then((success) {
          messenger.hideCurrentSnackBar();
          if (success) {
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Successfully joined room!'),
                backgroundColor: semantic.success,
              ),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: const Text(
                  'Failed to join room. Check internet or platform support.',
                ),
                backgroundColor: semantic.danger,
              ),
            );
          }
        });
        Navigator.of(context).pop();
    }
  }

  Widget _buildCommandEntryTile(
    CommandPaletteEntry entry, {
    required bool isActive,
  }) {
    return switch (entry.kind) {
      CommandPaletteEntryKind.quickCreate => _QuickCreateCommandTile(
        command: entry.quickCreateCommand!,
        isActive: isActive,
        onTap: () => _executeCommandPaletteEntry(entry),
      ),
      CommandPaletteEntryKind.jumpDate => _JumpDateCommandTile(
        command: entry.dateCommand!,
        isActive: isActive,
        onTap: () => _executeCommandPaletteEntry(entry),
      ),
      CommandPaletteEntryKind.node => _CommandResultTile(
        node: entry.node!,
        query: _currentCommandQuery().searchText,
        isActive: isActive,
        onTap: () => _executeCommandPaletteEntry(entry),
      ),
      CommandPaletteEntryKind.collab => _CollabCommandTile(
        link: entry.collabLink!,
        isActive: isActive,
        onTap: () => _executeCommandPaletteEntry(entry),
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

    final searchText = commandQuery.searchText.trim().toLowerCase();
    filtered.sort((a, b) {
      if (searchText.isNotEmpty) {
        final scoreA = _relevanceScore(a, searchText);
        final scoreB = _relevanceScore(b, searchText);
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final day = b.day.compareTo(a.day);
      if (day != 0) return day;
      return a.title.compareTo(b.title);
    });
    return filtered;
  }

  int _relevanceScore(MindmapNode node, String query) {
    if (query.isEmpty) return 0;
    final titleLower = node.title.toLowerCase();
    var score = 0;
    if (titleLower == query) {
      score += 1000;
    } else if (titleLower.startsWith(query)) {
      score += 500;
    } else if (titleLower.contains(query)) {
      score += 200;
    }

    final bodyLower = node.body.toLowerCase();
    if (bodyLower.contains(query)) {
      score += 50;
    }

    for (final tag in node.tags) {
      final tagLower = tag.toLowerCase();
      if (tagLower == query) {
        score += 30;
      } else if (tagLower.contains(query)) {
        score += 10;
      }
    }
    return score;
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
    final title = _createTitleController.text.trim().isEmpty
        ? _query.trim()
        : _createTitleController.text.trim();
    final enteredDate = DateTime.tryParse(
      _createDateController.text.trim(),
    )?.dateOnly;
    final commandQuery = _currentCommandQuery(forCreate: true);
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

  Future<void> _applyGraphFilter(_CommandGraphFilter filter) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'graph_pending_filter',
      jsonEncode(filter.query),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    context.go('/graph');
  }

  Future<void> _applySavedViewPreset(
    String dayView,
    String tableView, [
    String? tableSort,
  ]) async {
    final preferences = SharedPreferencesAsync();
    await preferences.setString('day_view_mode', dayView);
    await preferences.setString('day_table_quick_view', tableView);
    if (tableSort != null) {
      await preferences.setString('day_table_sort_mode', tableSort);
    }
    widget.onJumpToDate(widget.initialDate);
  }

  Future<void> _runCommandMutator(_CommandMutator mutator) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final node = mutator.node;
    final target = mutator.targetNode;
    final updated = switch (mutator.type) {
      _CommandMutatorType.complete => node.copyWith(
        isDone: true,
        status: NodeStatus.done,
        progress: 1,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.archive => node.copyWith(
        isArchived: true,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.unarchive => node.copyWith(
        isArchived: false,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.pin => node.copyWith(
        isPinned: true,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.unpin => node.copyWith(
        isPinned: false,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.rescheduleTomorrow => node.copyWith(
        dueDate: DateTime.now().dateOnly.addDays(1),
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.link => _linkNode(node, target!),
      _CommandMutatorType.unlink => _unlinkNode(node, target!),
      _CommandMutatorType.tag => node.copyWith(
        tags: node.tags.contains(mutator.value)
            ? node.tags
            : [...node.tags, mutator.value!],
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.removeTag => node.copyWith(
        tags: [
          for (final tag in node.tags)
            if (tag.toLowerCase() != mutator.value!.toLowerCase()) tag,
        ],
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.priority => node.copyWith(
        priority: _priorityFromCommandValue(mutator.value!) ?? node.priority,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearPriority => node.copyWith(
        priority: NodePriority.none,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.status => node.copyWith(
        status: _statusFromCommandValue(mutator.value!) ?? node.status,
        isDone: mutator.value == NodeStatus.done.name,
        progress: mutator.value == NodeStatus.done.name
            ? 1
            : node.isDone
            ? 0
            : node.progress,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearStatus => node.copyWith(
        status: NodeStatus.open,
        isDone: false,
        progress: node.isDone ? 0 : node.progress,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.type => node.copyWith(
        type: _typeFromCommandValue(mutator.value!) ?? node.type,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.rename => node.copyWith(
        title: mutator.value!,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.append => node.copyWith(
        body: node.body.trim().isEmpty
            ? mutator.value!
            : '${node.body.trim()}\n${mutator.value!}',
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.prepend => node.copyWith(
        body: node.body.trim().isEmpty
            ? mutator.value!
            : '${mutator.value!}\n${node.body.trim()}',
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.replaceBody => node.copyWith(
        body: mutator.value!,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.project => node.copyWith(
        project: mutator.value!,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.area => node.copyWith(
        area: mutator.value!,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.due => node.copyWith(
        dueDate: _dateFromCommandValue(mutator.value!)!,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearDue => node.copyWith(
        clearDueDate: true,
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearProject => node.copyWith(
        project: '',
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearArea => node.copyWith(
        area: '',
        updatedAt: DateTime.now(),
      ),
      _CommandMutatorType.clearTags => node.copyWith(
        tags: const [],
        updatedAt: DateTime.now(),
      ),
    };
    await repository.saveNode(updated);
    invalidateMindmapState(
      ref,
      day: node.day,
      extraDay: target?.day ?? updated.day,
    );
    widget.onOpenNode(updated);
  }

  NodePriority? _priorityFromCommandValue(String value) {
    return NodePriority.values.firstWhereOrNull(
      (priority) => priority.name == value.toLowerCase(),
    );
  }

  NodeStatus? _statusFromCommandValue(String value) {
    return NodeStatus.values.firstWhereOrNull(
      (status) => status.name == value.toLowerCase(),
    );
  }

  NodeType? _typeFromCommandValue(String value) {
    return NodeType.values.firstWhereOrNull(
      (type) => type.name == value.toLowerCase(),
    );
  }

  DateTime? _dateFromCommandValue(String value) {
    final today = DateTime.now().dateOnly;
    return switch (value.toLowerCase()) {
      'today' => today,
      'tomorrow' => today.addDays(1),
      _ => _parseIsoDay(value),
    };
  }

  DateTime? _parseIsoDay(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day).dateOnly;
  }

  MindmapNode _linkNode(MindmapNode source, MindmapNode target) {
    final relatedNodeIds = <String>{
      ...source.relatedNodeIds,
      target.id,
    }.toList();
    final relations = [
      for (final relation
          in source.data['relations'] as List<Object?>? ?? const [])
        if (relation case final Map<Object?, Object?> map)
          <String, Object?>{
            'targetId': map['targetId']?.toString() ?? '',
            'label': map['label']?.toString() ?? 'related',
          },
    ];
    final hasRelation = relations.any(
      (relation) => relation['targetId'] == target.id,
    );
    if (!hasRelation) {
      relations.add(<String, Object?>{
        'targetId': target.id,
        'label': 'related',
      });
    }

    return source.copyWith(
      relatedNodeIds: relatedNodeIds,
      data: <String, Object?>{...source.data, 'relations': relations},
      updatedAt: DateTime.now(),
    );
  }

  MindmapNode _unlinkNode(MindmapNode source, MindmapNode target) {
    final relations = [
      for (final relation
          in source.data['relations'] as List<Object?>? ?? const [])
        if (relation case final Map<Object?, Object?> map)
          if (map['targetId']?.toString() != target.id)
            <String, Object?>{
              'targetId': map['targetId']?.toString() ?? '',
              'label': map['label']?.toString() ?? 'related',
            },
    ];
    return source.copyWith(
      relatedNodeIds: [
        for (final id in source.relatedNodeIds)
          if (id != target.id) id,
      ],
      data: <String, Object?>{...source.data, 'relations': relations},
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _completeFirstOpenTask(List<MindmapNode> nodes) async {
    final task = nodes.firstWhereOrNull(
      (node) =>
          node.type == NodeType.task &&
          !node.isArchived &&
          !node.isDone &&
          node.status != NodeStatus.done,
    );
    if (task == null) return;
    final updated = task.copyWith(
      isDone: true,
      status: NodeStatus.done,
      progress: 1,
      updatedAt: DateTime.now(),
    );
    final saved = await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(updated);
    widget.onOpenNode(saved);
  }

  Future<void> _rescheduleOverdueTasks(List<MindmapNode> nodes) async {
    final today = DateTime.now().dateOnly;
    final repository = ref.read(mindmapRepositoryProvider);
    final overdue = nodes.where(
      (node) =>
          node.type == NodeType.task &&
          !node.isArchived &&
          !node.isDone &&
          node.dueDate != null &&
          node.dueDate!.dateOnly.isBefore(today),
    );
    for (final node in overdue) {
      await repository.saveNode(
        node.copyWith(dueDate: today.addDays(1), updatedAt: DateTime.now()),
      );
    }
    invalidateMindmapState(ref, day: today, extraDay: today.addDays(1));
    widget.onJumpToDate(today.addDays(1));
  }

  Future<void> _createWeeklyReview() async {
    final today = DateTime.now().dateOnly;
    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: NodeType.journal,
      title: 'Weekly review',
      body: 'Wins\n- \n\nLessons\n- \n\nNext week focus\n- ',
      day: today,
      tags: const ['weekly-review'],
      data: const {
        'journal': {'isWeeklyReview': true},
      },
      now: DateTime.now(),
    );
    final saved = await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(node);
    widget.onOpenNode(saved);
  }

  Future<void> _applyReadyRoutinesForToday() async {
    final today = DateTime.now().dateOnly;
    final repository = ref.read(mindmapRepositoryProvider);
    await applyRecurringRoutines(
      repository: repository,
      day: today,
      now: DateTime.now(),
    );
    invalidateMindmapState(ref, day: today);
    widget.onJumpToDate(today);
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
    for (final template in [...defaultNodeTemplates, ..._customTemplates]) {
      if (template.id == selectedTemplateId) return template;
    }
    return null;
  }

  CommandNodeQuery _currentCommandQuery({bool forCreate = false}) {
    return commandNodeQueryFromText(
      forCreate ? (_createContextQuery ?? _query) : _query,
      today: ref.read(currentDateProvider),
    );
  }

  bool _looksLikeCommandContext(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .any((token) => token.startsWith('#') || token.contains(':'));
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

final class _RecentCommand {
  const _RecentCommand({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  Map<String, Object?> toJson() => {'title': title, 'subtitle': subtitle};

  static _RecentCommand? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final title = value['title']?.toString() ?? '';
    if (title.isEmpty) return null;
    return _RecentCommand(
      icon: Icons.history_rounded,
      title: title,
      subtitle: value['subtitle']?.toString() ?? 'Recent command',
    );
  }
}

class _CommandHintChip extends StatelessWidget {
  const _CommandHintChip({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.labelSmall,
            children: [
              TextSpan(
                text: label,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              TextSpan(text: '  $text'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandSavedSearchesPanel extends StatelessWidget {
  const _CommandSavedSearchesPanel({
    required this.searches,
    required this.onSave,
    required this.onApply,
    required this.onDelete,
  });

  final List<_CommandSavedSearch> searches;
  final VoidCallback onSave;
  final ValueChanged<_CommandSavedSearch> onApply;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.saved_search_outlined,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved searches',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Save current'),
                ),
              ],
            ),
            if (searches.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final search in searches)
                    InputChip(
                      avatar: const Icon(Icons.search, size: 16),
                      label: Text(search.label),
                      tooltip: search.summary,
                      onPressed: () => onApply(search),
                      onDeleted: () => unawaited(onDelete(search.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandSavedViewsPanel extends StatelessWidget {
  const _CommandSavedViewsPanel({
    required this.customViews,
    required this.graphFilters,
    required this.onApply,
    required this.onApplyGraphFilter,
  });

  final List<_CommandSavedView> customViews;
  final List<_CommandGraphFilter> graphFilters;
  final Future<void> Function(
    String dayView,
    String tableView, [
    String? tableSort,
  ])
  onApply;
  final Future<void> Function(_CommandGraphFilter filter) onApplyGraphFilter;

  @override
  Widget build(BuildContext context) {
    const presets = [
      ('Priority table', 'table', 'priority', 'priorityDesc'),
      ('Due table', 'table', 'due', 'dueAsc'),
      ('Archived table', 'table', 'archived', 'updatedDesc'),
      ('Title table', 'table', 'all', 'titleAsc'),
      ('Board', 'board', 'open', null),
      ('Canvas', 'canvas', 'all', null),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in presets)
          ActionChip(
            avatar: const Icon(Icons.view_quilt_outlined, size: 16),
            label: Text(preset.$1),
            onPressed: () => onApply(preset.$2, preset.$3, preset.$4),
          ),
        for (final view in customViews)
          ActionChip(
            avatar: const Icon(Icons.bookmark_border, size: 16),
            label: Text(view.label),
            onPressed: () =>
                onApply(view.dayView, view.tableView, view.tableSort),
          ),
        for (final filter in graphFilters)
          ActionChip(
            avatar: const Icon(Icons.account_tree_outlined, size: 16),
            label: Text(filter.label),
            onPressed: () => onApplyGraphFilter(filter),
          ),
      ],
    );
  }
}

final class _CommandGraphFilter {
  const _CommandGraphFilter({required this.label, required this.query});

  final String label;
  final Map<String, Object?> query;

  static _CommandGraphFilter? fromJson(Object? value) {
    if (value case final Map<String, Object?> map) {
      final label = map['label']?.toString() ?? '';
      if (label.isEmpty) return null;
      return _CommandGraphFilter(
        label: label,
        query: {
          for (final entry in map.entries)
            if (entry.key != 'id' && entry.key != 'label')
              entry.key: entry.value,
        },
      );
    }
    return null;
  }
}

List<_CommandGraphFilter> _decodeCommandGraphFilters(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return decoded
        .map(_CommandGraphFilter.fromJson)
        .nonNulls
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

final class _CommandSavedSearch {
  const _CommandSavedSearch({
    required this.id,
    required this.label,
    required this.query,
    this.typeFilter,
    this.statusFilter,
    this.smartViewFilter,
    this.tagFilter,
    this.projectFilter,
    this.areaFilter,
    this.dateFilter = '',
  });

  final String id;
  final String label;
  final String query;
  final NodeType? typeFilter;
  final NodeStatus? statusFilter;
  final SmartNodeViewType? smartViewFilter;
  final String? tagFilter;
  final String? projectFilter;
  final String? areaFilter;
  final String dateFilter;

  String get summary {
    return [
      if (query.trim().isNotEmpty) query,
      if (typeFilter != null) 'type:${typeFilter!.name}',
      if (statusFilter != null) 'status:${statusFilter!.name}',
      if (smartViewFilter != null) smartViewFilter!.label,
      if (tagFilter != null) '#$tagFilter',
      if (projectFilter != null) 'project:$projectFilter',
      if (areaFilter != null) 'area:$areaFilter',
      if (dateFilter.isNotEmpty) dateFilter,
    ].join(' • ');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'query': query,
    'typeFilter': typeFilter?.name,
    'statusFilter': statusFilter?.name,
    'smartViewFilter': smartViewFilter?.name,
    'tagFilter': tagFilter,
    'projectFilter': projectFilter,
    'areaFilter': areaFilter,
    'dateFilter': dateFilter,
  };

  static _CommandSavedSearch? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final id = value['id']?.toString() ?? '';
    final label = value['label']?.toString() ?? '';
    if (id.isEmpty || label.isEmpty) return null;
    return _CommandSavedSearch(
      id: id,
      label: label,
      query: value['query']?.toString() ?? '',
      typeFilter: _enumByName(NodeType.values, value['typeFilter']?.toString()),
      statusFilter: _enumByName(
        NodeStatus.values,
        value['statusFilter']?.toString(),
      ),
      smartViewFilter: _enumByName(
        SmartNodeViewType.values,
        value['smartViewFilter']?.toString(),
      ),
      tagFilter: value['tagFilter']?.toString(),
      projectFilter: value['projectFilter']?.toString(),
      areaFilter: value['areaFilter']?.toString(),
      dateFilter: value['dateFilter']?.toString() ?? '',
    );
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

List<_CommandSavedSearch> _decodeCommandSavedSearches(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return decoded
        .map(_CommandSavedSearch.fromJson)
        .nonNulls
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

final class _CommandSavedView {
  const _CommandSavedView({
    required this.label,
    required this.dayView,
    required this.tableView,
    this.tableSort,
  });

  final String label;
  final String dayView;
  final String tableView;
  final String? tableSort;

  static _CommandSavedView? fromJson(Object? value) {
    if (value case final Map<String, Object?> map) {
      final label = map['label']?.toString() ?? '';
      final dayView = map['dayView']?.toString() ?? '';
      final tableView = map['tableView']?.toString() ?? '';
      final tableSort = map['tableSort']?.toString();
      if (label.isEmpty || dayView.isEmpty || tableView.isEmpty) return null;
      return _CommandSavedView(
        label: label,
        dayView: dayView,
        tableView: tableView,
        tableSort: tableSort,
      );
    }
    return null;
  }
}

List<_CommandSavedView> _decodeCommandSavedViews(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];
    return decoded
        .map(_CommandSavedView.fromJson)
        .nonNulls
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

enum _CommandMutatorType {
  complete,
  archive,
  unarchive,
  pin,
  unpin,
  rescheduleTomorrow,
  link,
  unlink,
  tag,
  removeTag,
  priority,
  clearPriority,
  status,
  clearStatus,
  type,
  rename,
  append,
  prepend,
  replaceBody,
  project,
  area,
  due,
  clearDue,
  clearProject,
  clearArea,
  clearTags,
}

final class _CommandMutator {
  const _CommandMutator({
    required this.type,
    required this.node,
    this.targetNode,
    this.value,
  });

  final _CommandMutatorType type;
  final MindmapNode node;
  final MindmapNode? targetNode;
  final String? value;

  String get label => switch (type) {
    _CommandMutatorType.complete => 'Complete ${node.title}',
    _CommandMutatorType.archive => 'Archive ${node.title}',
    _CommandMutatorType.unarchive => 'Unarchive ${node.title}',
    _CommandMutatorType.pin => 'Pin ${node.title}',
    _CommandMutatorType.unpin => 'Unpin ${node.title}',
    _CommandMutatorType.rescheduleTomorrow =>
      'Reschedule ${node.title} tomorrow',
    _CommandMutatorType.link => 'Link ${node.title} → ${targetNode!.title}',
    _CommandMutatorType.unlink =>
      'Unlink ${node.title} from ${targetNode!.title}',
    _CommandMutatorType.tag => 'Tag ${node.title} with $value',
    _CommandMutatorType.removeTag => 'Remove tag $value from ${node.title}',
    _CommandMutatorType.priority => 'Set ${node.title} priority $value',
    _CommandMutatorType.clearPriority => 'Clear ${node.title} priority',
    _CommandMutatorType.status => 'Set ${node.title} status $value',
    _CommandMutatorType.clearStatus => 'Clear ${node.title} status',
    _CommandMutatorType.type => 'Convert ${node.title} to $value',
    _CommandMutatorType.rename => 'Rename ${node.title} → $value',
    _CommandMutatorType.append => 'Append note to ${node.title}',
    _CommandMutatorType.prepend => 'Prepend note to ${node.title}',
    _CommandMutatorType.replaceBody => 'Replace ${node.title} body',
    _CommandMutatorType.project => 'Move ${node.title} to project $value',
    _CommandMutatorType.area => 'Move ${node.title} to area $value',
    _CommandMutatorType.due => 'Set ${node.title} due $value',
    _CommandMutatorType.clearDue => 'Clear ${node.title} due date',
    _CommandMutatorType.clearProject => 'Clear ${node.title} project',
    _CommandMutatorType.clearArea => 'Clear ${node.title} area',
    _CommandMutatorType.clearTags => 'Clear ${node.title} tags',
  };

  IconData get icon => switch (type) {
    _CommandMutatorType.complete => Icons.check_circle_outline,
    _CommandMutatorType.archive => Icons.archive_outlined,
    _CommandMutatorType.unarchive => Icons.unarchive_outlined,
    _CommandMutatorType.pin => Icons.push_pin_outlined,
    _CommandMutatorType.unpin => Icons.push_pin_outlined,
    _CommandMutatorType.rescheduleTomorrow => Icons.event_repeat,
    _CommandMutatorType.link => Icons.account_tree_outlined,
    _CommandMutatorType.unlink => Icons.link_off_outlined,
    _CommandMutatorType.tag => Icons.sell_outlined,
    _CommandMutatorType.removeTag => Icons.label_off_outlined,
    _CommandMutatorType.priority => Icons.priority_high_outlined,
    _CommandMutatorType.clearPriority => Icons.low_priority_outlined,
    _CommandMutatorType.status => Icons.tune_outlined,
    _CommandMutatorType.clearStatus => Icons.tune_outlined,
    _CommandMutatorType.type => Icons.change_circle_outlined,
    _CommandMutatorType.rename => Icons.drive_file_rename_outline,
    _CommandMutatorType.append => Icons.note_add_outlined,
    _CommandMutatorType.prepend => Icons.playlist_add_outlined,
    _CommandMutatorType.replaceBody => Icons.find_replace_outlined,
    _CommandMutatorType.project => Icons.folder_outlined,
    _CommandMutatorType.area => Icons.category_outlined,
    _CommandMutatorType.due => Icons.event_outlined,
    _CommandMutatorType.clearDue => Icons.event_busy_outlined,
    _CommandMutatorType.clearProject => Icons.folder_off_outlined,
    _CommandMutatorType.clearArea => Icons.category_outlined,
    _CommandMutatorType.clearTags => Icons.sell_outlined,
  };

  static _CommandMutator? fromQuery(String query, List<MindmapNode> nodes) {
    final raw = query.trim();
    final rawMutator =
        _renameMutatorFromQuery(raw, nodes) ??
        _appendMutatorFromQuery(raw, nodes) ??
        _prependMutatorFromQuery(raw, nodes) ??
        _replaceBodyMutatorFromQuery(raw, nodes);
    if (rawMutator != null) return rawMutator;

    final normalized = raw.toLowerCase();
    for (final parser in [
      _linkMutatorFromQuery,
      _unlinkMutatorFromQuery,
      _tagMutatorFromQuery,
      _removeTagMutatorFromQuery,
      _priorityMutatorFromQuery,
      _statusMutatorFromQuery,
      _typeMutatorFromQuery,
      _projectMutatorFromQuery,
      _areaMutatorFromQuery,
      _dueMutatorFromQuery,
      _moveDateMutatorFromQuery,
      _clearDueMutatorFromQuery,
      _clearContextMutatorFromQuery,
      _clearStateMutatorFromQuery,
    ]) {
      final mutator = parser(normalized, nodes);
      if (mutator != null) return mutator;
    }

    final patterns = <({String prefix, _CommandMutatorType type})>[
      (prefix: 'complete ', type: _CommandMutatorType.complete),
      (prefix: 'done ', type: _CommandMutatorType.complete),
      (prefix: 'archive ', type: _CommandMutatorType.archive),
      (prefix: 'unarchive ', type: _CommandMutatorType.unarchive),
      (prefix: 'pin ', type: _CommandMutatorType.pin),
      (prefix: 'unpin ', type: _CommandMutatorType.unpin),
      (prefix: 'reschedule ', type: _CommandMutatorType.rescheduleTomorrow),
    ];
    for (final pattern in patterns) {
      if (!normalized.startsWith(pattern.prefix)) continue;
      final needle = normalized.substring(pattern.prefix.length).trim();
      if (needle.isEmpty) return null;
      final node = nodes.firstWhereOrNull(
        (node) =>
            (pattern.type == _CommandMutatorType.unarchive ||
                !node.isArchived) &&
            node.title.toLowerCase().contains(needle),
      );
      if (node == null) return null;
      return _CommandMutator(type: pattern.type, node: node);
    }
    return null;
  }

  static _CommandMutator? _linkMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'link ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' to ');
    if (separator <= 0 || separator >= body.length - 4) return null;

    final sourceNeedle = body.substring(0, separator).trim();
    final targetNeedle = body.substring(separator + 4).trim();
    if (sourceNeedle.isEmpty || targetNeedle.isEmpty) return null;

    final source = _findCommandNode(nodes, sourceNeedle);
    if (source == null) return null;
    final target = _findCommandNode(
      nodes.where((node) => node.id != source.id),
      targetNeedle,
    );
    if (target == null) return null;

    return _CommandMutator(
      type: _CommandMutatorType.link,
      node: source,
      targetNode: target,
    );
  }

  static _CommandMutator? _unlinkMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'unlink ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' from ');
    if (separator <= 0 || separator >= body.length - 6) return null;
    final source = _findCommandNode(nodes, body.substring(0, separator).trim());
    if (source == null) return null;
    final target = _findCommandNode(
      nodes.where((node) => node.id != source.id),
      body.substring(separator + 6).trim(),
    );
    if (target == null) return null;
    return _CommandMutator(
      type: _CommandMutatorType.unlink,
      node: source,
      targetNode: target,
    );
  }

  static _CommandMutator? _tagMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'tag ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' with ');
    if (separator <= 0 || separator >= body.length - 6) return null;
    final node = _findCommandNode(nodes, body.substring(0, separator).trim());
    final tag = body.substring(separator + 6).trim();
    if (node == null || tag.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.tag,
      node: node,
      value: tag,
    );
  }

  static _CommandMutator? _removeTagMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    final prefix = normalized.startsWith('remove tag ')
        ? 'remove tag '
        : normalized.startsWith('untag ')
        ? 'untag '
        : null;
    if (prefix == null) return null;
    final body = normalized.substring(prefix.length).trim();
    final withSeparator = body.indexOf(' with ');
    final fromSeparator = body.indexOf(' from ');
    final split = withSeparator > 0 ? withSeparator : fromSeparator;
    final valueStart = withSeparator > 0
        ? withSeparator + 6
        : fromSeparator + 6;
    if (split <= 0 || valueStart >= body.length) return null;
    final node = _findCommandNode(nodes, body.substring(0, split).trim());
    final tag = body.substring(valueStart).trim();
    if (node == null || tag.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.removeTag,
      node: node,
      value: tag,
    );
  }

  static _CommandMutator? _priorityMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'priority ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final lastSpace = body.lastIndexOf(' ');
    if (lastSpace <= 0) return null;
    final node = _findCommandNode(nodes, body.substring(0, lastSpace).trim());
    final priority = body.substring(lastSpace + 1).trim();
    if (node == null || !_isPriorityValue(priority)) return null;
    return _CommandMutator(
      type: _CommandMutatorType.priority,
      node: node,
      value: priority,
    );
  }

  static _CommandMutator? _statusMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'status ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final lastSpace = body.lastIndexOf(' ');
    if (lastSpace <= 0) return null;
    final node = _findCommandNode(nodes, body.substring(0, lastSpace).trim());
    final status = body.substring(lastSpace + 1).trim();
    if (node == null || !_isStatusValue(status)) return null;
    return _CommandMutator(
      type: _CommandMutatorType.status,
      node: node,
      value: status,
    );
  }

  static _CommandMutator? _typeMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'type ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final lastSpace = body.lastIndexOf(' ');
    if (lastSpace <= 0) return null;
    final node = _findCommandNode(nodes, body.substring(0, lastSpace).trim());
    final type = body.substring(lastSpace + 1).trim();
    if (node == null || !_isTypeValue(type)) return null;
    return _CommandMutator(
      type: _CommandMutatorType.type,
      node: node,
      value: type,
    );
  }

  static _CommandMutator? _renameMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'rename ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' to ');
    if (separator <= 0 || separator >= body.length - 4) return null;
    final node = _findCommandNode(nodes, body.substring(0, separator).trim());
    final title = body.substring(separator + 4).trim();
    if (node == null || title.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.rename,
      node: node,
      value: title,
    );
  }

  static _CommandMutator? _appendMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'append ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' with ');
    if (separator <= 0 || separator >= body.length - 6) return null;
    final node = _findCommandNode(nodes, body.substring(0, separator).trim());
    final text = body.substring(separator + 6).trim();
    if (node == null || text.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.append,
      node: node,
      value: text,
    );
  }

  static _CommandMutator? _prependMutatorFromQuery(
    String raw,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'prepend ';
    if (!raw.toLowerCase().startsWith(prefix)) return null;
    final body = raw.substring(prefix.length).trim();
    final separator = body.toLowerCase().indexOf(' with ');
    if (separator <= 0 || separator >= body.length - 6) return null;
    final node = _findCommandNode(nodes, body.substring(0, separator).trim());
    final text = body.substring(separator + 6).trim();
    if (node == null || text.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.prepend,
      node: node,
      value: text,
    );
  }

  static _CommandMutator? _replaceBodyMutatorFromQuery(
    String raw,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'replace body ';
    if (!raw.toLowerCase().startsWith(prefix)) return null;
    final body = raw.substring(prefix.length).trim();
    final separator = body.toLowerCase().indexOf(' with ');
    if (separator <= 0 || separator >= body.length - 6) return null;
    final node = _findCommandNode(nodes, body.substring(0, separator).trim());
    final text = body.substring(separator + 6).trim();
    if (node == null || text.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.replaceBody,
      node: node,
      value: text,
    );
  }

  static _CommandMutator? _projectMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'project ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' to ');
    final split = separator > 0 ? separator : body.lastIndexOf(' ');
    final valueStart = separator > 0 ? separator + 4 : split + 1;
    if (split <= 0 || valueStart >= body.length) return null;
    final node = _findCommandNode(nodes, body.substring(0, split).trim());
    final project = body.substring(valueStart).trim();
    if (node == null || project.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.project,
      node: node,
      value: project,
    );
  }

  static _CommandMutator? _areaMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'area ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final separator = body.indexOf(' to ');
    final split = separator > 0 ? separator : body.lastIndexOf(' ');
    final valueStart = separator > 0 ? separator + 4 : split + 1;
    if (split <= 0 || valueStart >= body.length) return null;
    final node = _findCommandNode(nodes, body.substring(0, split).trim());
    final area = body.substring(valueStart).trim();
    if (node == null || area.isEmpty) return null;
    return _CommandMutator(
      type: _CommandMutatorType.area,
      node: node,
      value: area,
    );
  }

  static _CommandMutator? _dueMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    const prefix = 'due ';
    if (!normalized.startsWith(prefix)) return null;
    final body = normalized.substring(prefix.length).trim();
    final lastSpace = body.lastIndexOf(' ');
    if (lastSpace <= 0) return null;
    final node = _findCommandNode(nodes, body.substring(0, lastSpace).trim());
    final date = body.substring(lastSpace + 1).trim();
    if (node == null || !_isDueValue(date)) return null;
    return _CommandMutator(
      type: _CommandMutatorType.due,
      node: node,
      value: date,
    );
  }

  static _CommandMutator? _moveDateMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    final prefix = normalized.startsWith('move ')
        ? 'move '
        : normalized.startsWith('schedule ')
        ? 'schedule '
        : null;
    if (prefix == null) return null;
    final body = normalized.substring(prefix.length).trim();
    final lastSpace = body.lastIndexOf(' ');
    if (lastSpace <= 0) return null;
    final node = _findCommandNode(nodes, body.substring(0, lastSpace).trim());
    final date = body.substring(lastSpace + 1).trim();
    if (node == null || !_isDueValue(date)) return null;
    return _CommandMutator(
      type: _CommandMutatorType.due,
      node: node,
      value: date,
    );
  }

  static _CommandMutator? _clearDueMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    final prefix = normalized.startsWith('undue ')
        ? 'undue '
        : normalized.startsWith('clear due ')
        ? 'clear due '
        : null;
    if (prefix == null) return null;
    final needle = normalized.substring(prefix.length).trim();
    if (needle.isEmpty) return null;
    final node = _findCommandNode(nodes, needle);
    if (node == null) return null;
    return _CommandMutator(type: _CommandMutatorType.clearDue, node: node);
  }

  static _CommandMutator? _clearContextMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    final config = normalized.startsWith('clear project ')
        ? (prefix: 'clear project ', type: _CommandMutatorType.clearProject)
        : normalized.startsWith('remove project ')
        ? (prefix: 'remove project ', type: _CommandMutatorType.clearProject)
        : normalized.startsWith('clear area ')
        ? (prefix: 'clear area ', type: _CommandMutatorType.clearArea)
        : normalized.startsWith('remove area ')
        ? (prefix: 'remove area ', type: _CommandMutatorType.clearArea)
        : normalized.startsWith('clear tags ')
        ? (prefix: 'clear tags ', type: _CommandMutatorType.clearTags)
        : normalized.startsWith('remove tags ')
        ? (prefix: 'remove tags ', type: _CommandMutatorType.clearTags)
        : null;
    if (config == null) return null;
    final needle = normalized.substring(config.prefix.length).trim();
    if (needle.isEmpty) return null;
    final node = _findCommandNode(nodes, needle);
    if (node == null) return null;
    return _CommandMutator(type: config.type, node: node);
  }

  static _CommandMutator? _clearStateMutatorFromQuery(
    String normalized,
    List<MindmapNode> nodes,
  ) {
    final config = normalized.startsWith('clear status ')
        ? (prefix: 'clear status ', type: _CommandMutatorType.clearStatus)
        : normalized.startsWith('remove status ')
        ? (prefix: 'remove status ', type: _CommandMutatorType.clearStatus)
        : normalized.startsWith('clear priority ')
        ? (prefix: 'clear priority ', type: _CommandMutatorType.clearPriority)
        : normalized.startsWith('remove priority ')
        ? (prefix: 'remove priority ', type: _CommandMutatorType.clearPriority)
        : null;
    if (config == null) return null;
    final needle = normalized.substring(config.prefix.length).trim();
    if (needle.isEmpty) return null;
    final node = _findCommandNode(nodes, needle);
    if (node == null) return null;
    return _CommandMutator(type: config.type, node: node);
  }

  static bool _isTypeValue(String value) {
    return NodeType.values.any((type) => type.name == value);
  }

  static bool _isStatusValue(String value) {
    return NodeStatus.values.any((status) => status.name == value);
  }

  static bool _isPriorityValue(String value) {
    return NodePriority.values.any((priority) => priority.name == value);
  }

  static bool _isDueValue(String value) {
    if (value == 'today' || value == 'tomorrow') return true;
    final parts = value.split('-');
    if (parts.length != 3) return false;
    return int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null &&
        int.tryParse(parts[2]) != null;
  }

  static MindmapNode? _findCommandNode(
    Iterable<MindmapNode> nodes,
    String needle,
  ) {
    final normalizedNeedle = needle.toLowerCase();
    return nodes.firstWhereOrNull(
      (node) =>
          !node.isArchived &&
          node.title.toLowerCase().contains(normalizedNeedle),
    );
  }
}

class _CommandMutatorPanel extends StatelessWidget {
  const _CommandMutatorPanel({required this.mutator, required this.onRun});

  final _CommandMutator mutator;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: Icon(mutator.icon, size: 16),
        label: Text(mutator.label),
        onPressed: onRun,
      ),
    );
  }
}

class _CommandPowerActionsPanel extends StatelessWidget {
  const _CommandPowerActionsPanel({
    required this.nodes,
    required this.today,
    required this.onCompleteTask,
    required this.onRescheduleOverdue,
    required this.onCreateWeeklyReview,
    required this.onApplyRoutines,
  });

  final List<MindmapNode> nodes;
  final DateTime today;
  final Future<void> Function(List<MindmapNode> nodes) onCompleteTask;
  final Future<void> Function(List<MindmapNode> nodes) onRescheduleOverdue;
  final Future<void> Function() onCreateWeeklyReview;
  final Future<void> Function() onApplyRoutines;

  @override
  Widget build(BuildContext context) {
    final openTaskCount = nodes
        .where(
          (node) =>
              node.type == NodeType.task &&
              !node.isArchived &&
              !node.isDone &&
              node.status != NodeStatus.done,
        )
        .length;
    final overdueCount = nodes
        .where(
          (node) =>
              node.type == NodeType.task &&
              !node.isArchived &&
              !node.isDone &&
              node.dueDate != null &&
              node.dueDate!.dateOnly.isBefore(today),
        )
        .length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ActionChip(
          avatar: const Icon(Icons.check_circle_outline, size: 16),
          label: Text('Complete task ($openTaskCount)'),
          onPressed: openTaskCount == 0 ? null : () => onCompleteTask(nodes),
        ),
        ActionChip(
          avatar: const Icon(Icons.event_repeat, size: 16),
          label: Text('Reschedule overdue ($overdueCount)'),
          onPressed: overdueCount == 0
              ? null
              : () => onRescheduleOverdue(nodes),
        ),
        ActionChip(
          avatar: const Icon(Icons.rate_review_outlined, size: 16),
          label: const Text('Create weekly review'),
          onPressed: onCreateWeeklyReview,
        ),
        ActionChip(
          avatar: const Icon(Icons.auto_awesome_motion_outlined, size: 16),
          label: const Text('Apply routines'),
          onPressed: onApplyRoutines,
        ),
      ],
    );
  }
}

final class _CommandNavigationRoute {
  const _CommandNavigationRoute({
    required this.label,
    required this.path,
    required this.icon,
  });

  final String label;
  final String path;
  final IconData icon;
}

class _CommandNavigationPanel extends StatelessWidget {
  const _CommandNavigationPanel({
    required this.initialDate,
    required this.onNavigate,
  });

  final DateTime initialDate;
  final ValueChanged<_CommandNavigationRoute> onNavigate;

  @override
  Widget build(BuildContext context) {
    final routes = [
      const _CommandNavigationRoute(
        label: 'Open Calendar',
        path: '/calendar',
        icon: Icons.calendar_today_outlined,
      ),
      _CommandNavigationRoute(
        label: 'Open Today',
        path: '/calendar/${dayKey(DateTime.now().dateOnly)}',
        icon: Icons.today_outlined,
      ),
      _CommandNavigationRoute(
        label: 'Open Current Day',
        path: '/calendar/${dayKey(initialDate)}',
        icon: Icons.view_day_outlined,
      ),
      const _CommandNavigationRoute(
        label: 'Open Insights',
        path: '/insights',
        icon: Icons.insights_outlined,
      ),
      const _CommandNavigationRoute(
        label: 'Open Graph',
        path: '/graph',
        icon: Icons.account_tree_outlined,
      ),
      const _CommandNavigationRoute(
        label: 'Open Workspaces',
        path: '/workspaces',
        icon: Icons.workspaces_outline,
      ),
      const _CommandNavigationRoute(
        label: 'Open Settings',
        path: '/settings',
        icon: Icons.settings_outlined,
      ),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final route in routes)
          ActionChip(
            avatar: Icon(route.icon, size: 16),
            label: Text(route.label),
            onPressed: () => onNavigate(route),
          ),
      ],
    );
  }
}

class _RecentCommandPanel extends StatelessWidget {
  const _RecentCommandPanel({required this.commands, required this.onSelected});

  final List<_RecentCommand> commands;
  final ValueChanged<_RecentCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.22,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Recent commands', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final command in commands)
                  ActionChip(
                    avatar: Icon(command.icon, size: 16),
                    label: Text('Recent: ${command.title}'),
                    tooltip: command.subtitle,
                    onPressed: () => onSelected(command),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandEmptyState extends StatelessWidget {
  const _CommandEmptyState({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.manage_search_rounded,
            size: 42,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),
          Text('No matching commands', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            query.trim().isEmpty
                ? 'Try a node title, tag, date, or quick create phrase.'
                : 'No results for "$query".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _CommandHintChip(label: 'today', text: 'jump'),
              _CommandHintChip(label: 'task buy milk', text: 'create'),
              _CommandHintChip(label: '#tag', text: 'filter'),
            ],
          ),
          if (query.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.clear_rounded),
              label: const Text('Clear search'),
            ),
          ],
        ],
      ),
    );
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
    required this.templates,
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
  final List<NodeTemplate> templates;
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
              for (final template in templates) ...[
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

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.value, required this.query});

  final String value;
  final String query;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final index = normalizedQuery.isEmpty
        ? -1
        : value.toLowerCase().indexOf(normalizedQuery);
    if (index < 0) {
      return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final theme = Theme.of(context);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.bodyLarge,
        children: [
          TextSpan(text: value.substring(0, index)),
          TextSpan(
            text: value.substring(index, index + normalizedQuery.length),
            style: TextStyle(
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.22,
              ),
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: value.substring(index + normalizedQuery.length)),
        ],
      ),
    );
  }
}

class _CommandResultTile extends StatelessWidget {
  const _CommandResultTile({
    required this.node,
    required this.query,
    required this.onTap,
    required this.isActive,
  });

  final MindmapNode node;
  final String query;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('global-command-result-${node.id}'),
      dense: true,
      tileColor: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : theme.dividerColor,
          width: isActive ? 2.0 : 1.0,
        ),
      ),
      leading: Icon(NodeVisuals.icon(node.type)),
      title: _HighlightedText(value: node.title, query: query),
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
  const _JumpDateCommandTile({
    required this.command,
    required this.onTap,
    required this.isActive,
  });

  final CommandDateResult command;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('global-command-jump-result-${dayKey(command.date)}'),
      dense: true,
      tileColor: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : theme.dividerColor,
          width: isActive ? 2.0 : 1.0,
        ),
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
  const _QuickCreateCommandTile({
    required this.command,
    required this.onTap,
    required this.isActive,
  });

  final QuickCreateCommand command;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: const ValueKey('global-command-quick-create-result'),
      dense: true,
      tileColor: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : theme.dividerColor,
          width: isActive ? 2.0 : 1.0,
        ),
      ),
      leading: Icon(NodeVisuals.icon(command.type)),
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

class _CollabCommandTile extends StatelessWidget {
  const _CollabCommandTile({
    required this.link,
    required this.onTap,
    required this.isActive,
  });

  final String link;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: const ValueKey('global-command-collab-result'),
      dense: true,
      tileColor: isActive
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? theme.colorScheme.primary : theme.dividerColor,
          width: isActive ? 2.0 : 1.0,
        ),
      ),
      leading: const Icon(Icons.people_alt_outlined),
      title: const Text('Join Collaboration Room', maxLines: 1),
      subtitle: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
