/// Search and insights center for the local mindmap workspace.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/layout/adaptive_scaffold.dart';
import '../../shared/widgets/doodle_border.dart';
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/automation_event.dart';
import '../mindmap/domain/automation_forecast.dart';
import '../mindmap/domain/automation_health.dart';
import '../mindmap/domain/automation_rule.dart';
import '../mindmap/domain/automation_suggestion.dart';
import '../mindmap/domain/canvas_position.dart';
import '../mindmap/domain/life_os_summary.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/mindmap_repository.dart';
import '../mindmap/domain/node_graph.dart';
import '../mindmap/domain/node_template.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/smart_node_view.dart';
import '../mindmap/domain/workspace_context.dart';
import 'application/context_health.dart' as health;
import 'application/focus_insights.dart' as focus;
import 'application/goal_insights.dart' as goals;
import 'application/habit_insights.dart' as habits;
import 'application/insight_cache.dart' as insight_cache;
import 'application/insight_filters.dart' as insight_filters;
import 'application/insight_recommendations.dart' as recs;
import 'application/insight_risk_engine.dart' as risks;
import 'application/insights_markdown_export.dart' as md_export;
import 'application/insights_summary.dart' as mission;
import 'application/insights_trends.dart' as trends;
import 'application/review_insights.dart' as reviews;
import 'domain/insights_summary.dart';

class _SetInsightRangeIntent extends Intent {
  const _SetInsightRangeIntent(this.preset);

  final insight_filters.InsightRangePreset preset;
}

class _FocusInsightSearchIntent extends Intent {
  const _FocusInsightSearchIntent();
}

class _ExportInsightReportIntent extends Intent {
  const _ExportInsightReportIntent();
}

class _RefreshInsightsIntent extends Intent {
  const _RefreshInsightsIntent();
}

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key, this.initialShowDashboardPanels = false});

  final bool initialShowDashboardPanels;

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';
  String _latestMarkdownReport = '';
  SmartNodeViewType? _smartViewFilter;
  String? _projectFilter;
  String? _areaFilter;
  NodeStatus? _statusFilter;
  NodePriority? _priorityFilter;
  NodeType? _typeFilter;
  String? _tagFilter;
  insight_filters.InsightRangePreset _rangePreset =
      insight_filters.InsightRangePreset.sevenDays;
  late bool _showDashboardPanels;

  Uri? _lastFilterUri;

  @override
  void initState() {
    super.initState();
    _showDashboardPanels = widget.initialShowDashboardPanels;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final uri = GoRouterState.of(context).uri;
      if (_lastFilterUri == uri) return;
      _lastFilterUri = uri;
      final project = uri.queryParameters['project'];
      final area = uri.queryParameters['area'];
      _projectFilter = project;
      _areaFilter = project == null ? area : null;
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final smartViews = ref.watch(smartNodeViewsProvider);
    final automationSuggestions = ref.watch(automationSuggestionsProvider);
    final today = ref.watch(currentDateProvider);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyT): _SetInsightRangeIntent(
          insight_filters.InsightRangePreset.today,
        ),
        SingleActivator(LogicalKeyboardKey.keyW): _SetInsightRangeIntent(
          insight_filters.InsightRangePreset.sevenDays,
        ),
        SingleActivator(LogicalKeyboardKey.keyM): _SetInsightRangeIntent(
          insight_filters.InsightRangePreset.thisMonth,
        ),
        SingleActivator(LogicalKeyboardKey.slash): _FocusInsightSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyE): _ExportInsightReportIntent(),
        SingleActivator(LogicalKeyboardKey.keyR): _RefreshInsightsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SetInsightRangeIntent: CallbackAction<_SetInsightRangeIntent>(
            onInvoke: (intent) {
              if (_isEditingText()) return null;
              setState(() => _rangePreset = intent.preset);
              return null;
            },
          ),
          _FocusInsightSearchIntent: CallbackAction<_FocusInsightSearchIntent>(
            onInvoke: (_) {
              _searchFocusNode.requestFocus();
              return null;
            },
          ),
          _ExportInsightReportIntent:
              CallbackAction<_ExportInsightReportIntent>(
                onInvoke: (_) {
                  if (_isEditingText()) return null;
                  if (_latestMarkdownReport.isNotEmpty) {
                    Clipboard.setData(
                      ClipboardData(text: _latestMarkdownReport),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Markdown report copied to clipboard'),
                      ),
                    );
                  }
                  return null;
                },
              ),
          _RefreshInsightsIntent: CallbackAction<_RefreshInsightsIntent>(
            onInvoke: (_) {
              if (_isEditingText()) return null;
              ref.invalidate(smartNodeViewsProvider);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: const AppRouteChromeTabs(currentRoute: AppRoute.insights),
              actions: [
                IconButton(
                  tooltip: _showDashboardPanels
                      ? 'Hide dashboard panels'
                      : 'Show dashboard panels',
                  icon: Icon(
                    _showDashboardPanels
                        ? Icons.dashboard_customize
                        : Icons.dashboard_customize_outlined,
                  ),
                  onPressed: () => setState(() {
                    _showDashboardPanels = !_showDashboardPanels;
                  }),
                ),
                SearchField(
                  key: const ValueKey('insights-search-field'),
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  hintText: 'Search nodes...',
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                ),
                const SizedBox(width: 16),
              ],
            ),
            body: smartViews.when(
              data: (value) {
                final range = insight_filters.insightDateRangeForPreset(
                  preset: _rangePreset,
                  today: today,
                );
                final dashboardFilter = insight_filters.InsightFilterState(
                  project: _projectFilter,
                  area: _areaFilter,
                  tag: _tagFilter,
                  nodeType: _typeFilter,
                  priority: _priorityFilter,
                  status: _statusFilter,
                );
                final nodeIndex = insight_cache.buildInsightNodeIndex(
                  nodes: value.allNodes,
                  filter: dashboardFilter,
                  range: range,
                  today: today,
                );
                final scopedNodes = nodeIndex.scopedNodes;
                final filteredNodes = _filterNodes(
                  value.nodesFor(_smartViewFilter),
                  range,
                );
                final workspaceContexts = WorkspaceContexts.fromNodes(
                  value.allNodes,
                );
                final lifeSummary = LifeOsSummary.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final lifeRhythm = LifeOsRhythm.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final attention = LifeOsAttention.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final insightsSummary = InsightsSummary.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final missionSummaries = mission.buildInsightsSummary(
                  today: today,
                  nodes: scopedNodes,
                );
                final completionTrend = trends.buildCompletionTrend(
                  start: range.start,
                  end: range.end,
                  today: today,
                  nodes: scopedNodes,
                );
                final habitRoutineInsights = habits.buildHabitRoutineInsights(
                  start: range.start,
                  end: range.end,
                  today: today,
                  nodes: scopedNodes,
                );
                final focusInsights = focus.buildFocusInsightSummary(
                  start: range.start,
                  end: range.end,
                  nodes: scopedNodes,
                );
                final reviewInsights = reviews.buildReviewInsightSummary(
                  start: range.start,
                  end: range.end,
                  today: today,
                  nodes: scopedNodes,
                );
                final contextHealth = health.buildContextHealthSummary(
                  today: today,
                  nodes: scopedNodes,
                );
                final goalInsights = goals.buildGoalInsightSummary(
                  today: today,
                  nodes: scopedNodes,
                );
                final insightRisks = risks.buildInsightRisks(
                  today: today,
                  nodes: scopedNodes,
                );
                final recommendations = recs.buildInsightRecommendations(
                  risks: insightRisks,
                  overdueCount: insightsSummary.overdueCount,
                  openTaskCount: nodeIndex.openTaskCount,
                  reviewCount: reviewInsights.reviewCount,
                  hasContextFilter: !dashboardFilter.isEmpty,
                );
                final markdownReport = md_export.buildInsightsMarkdownReport(
                  md_export.InsightsMarkdownReportInput(
                    generatedAt: DateTime.now(),
                    rangeStart: range.start,
                    rangeEnd: range.end,
                    nodes: scopedNodes,
                    missionSummaries: missionSummaries,
                    completionTrend: completionTrend,
                    risks: insightRisks,
                    recommendations: recommendations,
                    contextHealth: contextHealth,
                    focusSummary: focusInsights,
                    habitSummary: habitRoutineInsights.habits,
                    reviewSummary: reviewInsights,
                    goalSummary: goalInsights,
                    scopeLabel: _rangePresetLabel(_rangePreset),
                  ),
                );
                _latestMarkdownReport = markdownReport;
                final weeklyPulse = InsightsWeeklyPulse.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final weeklyReview = InsightsWeeklyReview.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final automationForecast = AutomationForecast.fromNodes(
                  today: today,
                  nodes: value.allNodes,
                );
                final automationHealth = AutomationHealth.fromNodes(
                  nodes: value.allNodes,
                );
                final automationEvents = automationEventsFromNodes(
                  value.allNodes,
                );
                final nodeGraph = NodeGraph.fromNodes(value.allNodes);
                return _InsightsBody(
                  today: today,
                  nodes: value.allNodes,
                  filteredNodes: filteredNodes,
                  nodeIndex: nodeIndex,
                  automationSuggestions: automationSuggestions.valueOrNull,
                  automationForecast: automationForecast,
                  automationHealth: automationHealth,
                  automationEvents: automationEvents,
                  smartViews: value.views,
                  workspaceContexts: workspaceContexts.contexts,
                  lifeSummary: lifeSummary,
                  lifeRhythm: lifeRhythm,
                  attention: attention,
                  insightsSummary: insightsSummary,
                  missionSummaries: missionSummaries,
                  completionTrend: completionTrend,
                  habitRoutineInsights: habitRoutineInsights,
                  focusInsights: focusInsights,
                  reviewInsights: reviewInsights,
                  contextHealth: contextHealth,
                  goalInsights: goalInsights,
                  insightRisks: insightRisks,
                  recommendations: recommendations,
                  markdownReport: markdownReport,
                  weeklyPulse: weeklyPulse,
                  weeklyReview: weeklyReview,
                  nodeGraph: nodeGraph,
                  searchQuery: _query,
                  smartViewFilter: _smartViewFilter,
                  projectFilter: _projectFilter,
                  areaFilter: _areaFilter,
                  statusFilter: _statusFilter,
                  priorityFilter: _priorityFilter,
                  typeFilter: _typeFilter,
                  tagFilter: _tagFilter,
                  rangePreset: _rangePreset,
                  showDashboardPanels: _showDashboardPanels,
                  onSmartViewChanged: (smartView) {
                    setState(() {
                      _smartViewFilter = _smartViewFilter == smartView
                          ? null
                          : smartView;
                    });
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
                  onStatusChanged: (status) {
                    setState(() {
                      _statusFilter = _statusFilter == status ? null : status;
                    });
                  },
                  onPriorityChanged: (priority) {
                    setState(() {
                      _priorityFilter = _priorityFilter == priority
                          ? null
                          : priority;
                    });
                  },
                  onTypeChanged: (type) {
                    setState(() {
                      _typeFilter = _typeFilter == type ? null : type;
                    });
                  },
                  onTagChanged: (tag) {
                    setState(() {
                      _tagFilter = _tagFilter == tag ? null : tag;
                    });
                  },
                  onRangePresetChanged: (preset) {
                    setState(() => _rangePreset = preset);
                  },
                  onClearInsightFilters: () {
                    setState(() {
                      _projectFilter = null;
                      _areaFilter = null;
                      _statusFilter = null;
                      _priorityFilter = null;
                      _typeFilter = null;
                      _tagFilter = null;
                      _rangePreset =
                          insight_filters.InsightRangePreset.sevenDays;
                    });
                  },
                  onCreateWeeklyReview: () => _createWeeklyReview(today),
                  onRescheduleNode: _rescheduleOverdueNode,
                  onCompleteNode: _completeOverdueNode,
                  onPinGoal: _pinGoal,
                  onCreateGoalNextAction: _createGoalNextAction,
                  onReviewAutomations: _openAutomationCenter,
                  onPauseAutomationIssue: _pauseAutomationHealthIssue,
                );
              },
              loading: () => const _InsightsLoadingSkeleton(),
              error: (error, _) => _InsightsErrorState(
                message: 'Unable to load insights',
                onRetry: () => ref.invalidate(smartNodeViewsProvider),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isEditingText() {
    final focused = FocusManager.instance.primaryFocus?.context?.widget;
    return focused is EditableText;
  }

  List<MindmapNode> _filterNodes(
    List<MindmapNode> nodes,
    insight_filters.InsightDateRange range,
  ) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = nodes.where((node) {
      if (_statusFilter != null && node.status != _statusFilter) return false;
      if (_priorityFilter != null && node.priority != _priorityFilter) {
        return false;
      }
      if (_typeFilter != null && node.type != _typeFilter) return false;
      if (_tagFilter != null && !node.tags.contains(_tagFilter)) return false;
      if (_projectFilter != null && node.project != _projectFilter) {
        return false;
      }
      if (_areaFilter != null && node.area != _areaFilter) return false;
      if (normalizedQuery.isEmpty) return true;
      return _matchesQuery(node, normalizedQuery);
    }).toList();

    filtered.sort(_compareInsightNodes);
    return filtered;
  }

  Future<void> _rescheduleOverdueNode(MindmapNode node) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final tomorrow = ref.read(currentDateProvider).dateOnly.addDays(1);
    final updated = node.copyWith(dueDate: tomorrow, updatedAt: DateTime.now());
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day, extraDay: tomorrow);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rescheduled ${node.title} to tomorrow')),
    );
  }

  Future<void> _completeOverdueNode(MindmapNode node) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final updated = node.copyWith(
      isDone: true,
      status: NodeStatus.done,
      progress: 1,
      updatedAt: DateTime.now(),
    );
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Completed ${node.title}')));
  }

  Future<void> _pinGoal(MindmapNode node) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final updated = node.copyWith(isPinned: true, updatedAt: DateTime.now());
    await repository.saveNode(updated);
    invalidateMindmapState(ref, day: node.day);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Pinned ${node.title}')));
  }

  Future<void> _createGoalNextAction(MindmapNode goal) async {
    final repository = ref.read(mindmapRepositoryProvider);
    final today = ref.read(currentDateProvider).dateOnly;
    final now = DateTime.now();
    final node = MindmapNode(
      id: 'goal-action-${now.microsecondsSinceEpoch}',
      type: NodeType.task,
      title: 'Next action: ${goal.title}',
      day: today,
      createdAt: now,
      updatedAt: now,
      body: 'Move goal forward: [[${goal.title}]]',
      position: CanvasPosition(goal.position.dx + 260, goal.position.dy + 80),
      priority: NodePriority.high,
      project: goal.project,
      area: goal.area,
      tags: const ['next-action'],
      relatedNodeIds: [goal.id],
      dueDate: today,
      data: {
        'relations': [
          {'targetId': goal.id, 'label': 'moves goal'},
        ],
      },
    );
    await repository.saveNode(node);
    invalidateMindmapState(ref, day: today, extraDay: goal.day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Next action created for ${goal.title}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => goToDay(context, today, highlightNodeId: node.id),
        ),
      ),
    );
  }

  Future<void> _createWeeklyReview(DateTime today) async {
    final normalizedToday = today.dateOnly;
    final repository = ref.read(mindmapRepositoryProvider);
    final now = DateTime.now();
    final node = MindmapNode(
      id: 'weekly-review-${now.microsecondsSinceEpoch}',
      type: NodeType.journal,
      title: 'Weekly review',
      day: normalizedToday,
      createdAt: now,
      updatedAt: now,
      body: 'Wins\n- \n\nLessons\n- \n\nNext week focus\n- ',
      position: const CanvasPosition(0, 0),
      tags: const ['weekly-review'],
      data: const {
        'journal': {'isWeeklyReview': true, 'prompt': 'Weekly review'},
      },
    );
    await repository.saveNode(node);
    invalidateMindmapState(ref, day: normalizedToday);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Weekly review created'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () =>
              goToDay(context, normalizedToday, highlightNodeId: node.id),
        ),
      ),
    );
  }

  Future<void> _openAutomationCenter(AutomationSuggestions suggestions) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AutomationCenterDialog(suggestions: suggestions),
    );
  }

  Future<void> _pauseAutomationHealthIssue(AutomationHealthIssue issue) async {
    if (!issue.canPauseRules) return;

    final repository = ref.read(mindmapRepositoryProvider);
    final pausedRuleNodeIds = <String>[];
    final pausedLabels = <String>[];
    for (final nodeId in issue.pausableRuleNodeIds) {
      final node = await repository.getNode(nodeId);
      if (node == null) continue;
      final rule = automationRuleFromNode(node);
      if (rule == null || !rule.enabled) continue;

      await repository.saveNode(
        updateAutomationRuleNode(
          node: node,
          label: rule.label,
          templateId: rule.templateId,
          rule: rule.rule,
          enabled: false,
        ),
      );
      pausedRuleNodeIds.add(nodeId);
      pausedLabels.add(rule.label);
    }

    if (pausedRuleNodeIds.isNotEmpty) {
      final now = DateTime.now();
      final target = issue.title.replaceFirst('Duplicate ', '');
      await repository.saveNode(
        createAutomationEventNode(
          id: 'pause-duplicates-${now.microsecondsSinceEpoch}',
          type: AutomationEventType.pauseDuplicateRules,
          title: 'Paused duplicate automation rules',
          message:
              'Paused ${_joinAutomationLabels(pausedLabels)} to resolve duplicate $target.',
          day: ref.read(currentDateProvider),
          occurredAt: now,
          affectedRuleNodeIds: pausedRuleNodeIds,
          affectedLabels: pausedLabels,
        ),
      );
    }

    _invalidateAutomationState(ref.read(currentDateProvider).dateOnly);
  }

  void _invalidateAutomationState(DateTime day) {
    invalidateMindmapState(ref, day: day);
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.today,
    required this.nodes,
    required this.filteredNodes,
    required this.nodeIndex,
    required this.automationSuggestions,
    required this.automationForecast,
    required this.automationHealth,
    required this.automationEvents,
    required this.smartViews,
    required this.workspaceContexts,
    required this.lifeSummary,
    required this.lifeRhythm,
    required this.attention,
    required this.insightsSummary,
    required this.missionSummaries,
    required this.completionTrend,
    required this.habitRoutineInsights,
    required this.focusInsights,
    required this.reviewInsights,
    required this.contextHealth,
    required this.goalInsights,
    required this.insightRisks,
    required this.recommendations,
    required this.markdownReport,
    required this.weeklyPulse,
    required this.weeklyReview,
    required this.nodeGraph,
    required this.searchQuery,
    required this.smartViewFilter,
    required this.projectFilter,
    required this.areaFilter,
    required this.statusFilter,
    required this.priorityFilter,
    required this.typeFilter,
    required this.tagFilter,
    required this.rangePreset,
    required this.showDashboardPanels,
    required this.onSmartViewChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onTypeChanged,
    required this.onTagChanged,
    required this.onRangePresetChanged,
    required this.onClearInsightFilters,
    required this.onCreateWeeklyReview,
    required this.onRescheduleNode,
    required this.onCompleteNode,
    required this.onPinGoal,
    required this.onCreateGoalNextAction,
    required this.onReviewAutomations,
    required this.onPauseAutomationIssue,
  });

  final DateTime today;
  final List<MindmapNode> nodes;
  final List<MindmapNode> filteredNodes;
  final insight_cache.InsightNodeIndex nodeIndex;
  final AutomationSuggestions? automationSuggestions;
  final AutomationForecast automationForecast;
  final AutomationHealth automationHealth;
  final List<AutomationEventRecord> automationEvents;
  final List<SmartNodeView> smartViews;
  final List<WorkspaceContext> workspaceContexts;
  final LifeOsSummary lifeSummary;
  final LifeOsRhythm lifeRhythm;
  final LifeOsAttention attention;
  final InsightsSummary insightsSummary;
  final List<mission.InsightsSummary> missionSummaries;
  final trends.InsightTrendSeries completionTrend;
  final habits.HabitRoutineInsightSummary habitRoutineInsights;
  final focus.FocusInsightSummary focusInsights;
  final reviews.ReviewInsightSummary reviewInsights;
  final health.ContextHealthSummary contextHealth;
  final goals.GoalInsightSummary goalInsights;
  final List<risks.InsightRisk> insightRisks;
  final List<recs.InsightRecommendation> recommendations;
  final String markdownReport;
  final InsightsWeeklyPulse weeklyPulse;
  final InsightsWeeklyReview weeklyReview;
  final NodeGraph nodeGraph;
  final String searchQuery;
  final SmartNodeViewType? smartViewFilter;
  final String? projectFilter;
  final String? areaFilter;
  final NodeStatus? statusFilter;
  final NodePriority? priorityFilter;
  final NodeType? typeFilter;
  final String? tagFilter;
  final insight_filters.InsightRangePreset rangePreset;
  final bool showDashboardPanels;
  final ValueChanged<SmartNodeViewType> onSmartViewChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<insight_filters.InsightRangePreset> onRangePresetChanged;
  final VoidCallback onClearInsightFilters;
  final Future<void> Function() onCreateWeeklyReview;
  final Future<void> Function(MindmapNode node) onRescheduleNode;
  final Future<void> Function(MindmapNode node) onCompleteNode;
  final Future<void> Function(MindmapNode node) onPinGoal;
  final Future<void> Function(MindmapNode node) onCreateGoalNextAction;
  final ValueChanged<AutomationSuggestions> onReviewAutomations;
  final Future<void> Function(AutomationHealthIssue) onPauseAutomationIssue;

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    final hasCleanDashboardScope =
        searchQuery.trim().isEmpty &&
        smartViewFilter == null &&
        projectFilter == null &&
        areaFilter == null &&
        statusFilter == null &&
        priorityFilter == null;
    final showOverviewPanels = showDashboardPanels && hasCleanDashboardScope;
    final showAttentionPanel =
        attention.signals.isNotEmpty && showOverviewPanels;
    final showAutomationPanel =
        automationSuggestions != null &&
        !automationSuggestions!.isEmpty &&
        showOverviewPanels;
    final showAutomationForecast =
        !automationForecast.isEmpty && showOverviewPanels;
    final showAutomationHealth =
        automationHealth.hasIssues && showOverviewPanels;
    final showAutomationHistory =
        automationEvents.isNotEmpty && showOverviewPanels;
    final showWorkspaceFocus =
        workspaceContexts.isNotEmpty && showOverviewPanels;
    final isEmptyWorkspace = nodes.isEmpty && hasCleanDashboardScope;

    return Padding(
      padding: EdgeInsets.all(spacing),
      child: ListView(
        children: [
          if (showOverviewPanels) ...[
            _buildWeeklyDigest(context),
            SizedBox(height: spacing),
          ],
          _InsightRangeFilterBar(
            rangePreset: rangePreset,
            typeFilter: typeFilter,
            tagFilter: tagFilter,
            nodes: nodes,
            onRangePresetChanged: onRangePresetChanged,
            onTypeChanged: onTypeChanged,
            onTagChanged: onTagChanged,
            onClear: onClearInsightFilters,
          ),
          const SizedBox(height: 8),
          const _InsightShortcutHintBar(),
          SizedBox(height: spacing),
          if (isEmptyWorkspace) ...[
            const _NewUserEmptyState(),
            SizedBox(height: spacing),
          ],
          _MetricRail(
            children: [
              _MetricPill(
                icon: Icons.hub_outlined,
                label: '${nodes.length} nodes',
              ),
              _MetricPill(
                icon: Icons.check_circle_outline,
                label: '${nodeIndex.completedCount} done',
              ),
              _MetricPill(
                icon: Icons.flag_outlined,
                label: '${nodeIndex.highPriorityOpenTaskCount} high priority',
              ),
              if (insightsSummary.taskCount > 0)
                _MetricPill(
                  icon: Icons.task_alt_outlined,
                  label:
                      '${_percentLabel(insightsSummary.taskCompletionRate)} task completion',
                ),
              if (insightsSummary.overdueCount > 0)
                _MetricPill(
                  icon: Icons.warning_amber_outlined,
                  label: '${insightsSummary.overdueCount} overdue',
                ),
              if (insightsSummary.productiveDayCount > 0)
                _MetricPill(
                  icon: Icons.calendar_view_week_outlined,
                  label:
                      '${insightsSummary.productiveDayCount} productive days',
                ),
              if (insightsSummary.habitConsistency > 0)
                _MetricPill(
                  icon: Icons.repeat_on_outlined,
                  label:
                      '${_percentLabel(insightsSummary.habitConsistency)} habit consistency',
                ),
              if (insightsSummary.activeDayCount > 0)
                _MetricPill(
                  icon: Icons.calendar_today_outlined,
                  label: '${insightsSummary.activeDayCount} active days',
                ),
              if (insightsSummary.averageNodesPerActiveDay > 0)
                _MetricPill(
                  icon: Icons.query_stats_outlined,
                  label:
                      '${insightsSummary.averageNodesPerActiveDay.toStringAsFixed(1)} nodes/day',
                ),
              if (insightsSummary.averageGoalProgress > 0)
                _MetricPill(
                  icon: Icons.stacked_line_chart_outlined,
                  label:
                      '${_percentLabel(insightsSummary.averageGoalProgress)} goal progress',
                ),
              if (insightsSummary.monthlyReviewCount > 0)
                _MetricPill(
                  icon: Icons.event_note_outlined,
                  label: '${insightsSummary.monthlyReviewCount} monthly review',
                ),
              if (lifeSummary.bestHabitStreak > 0)
                _MetricPill(
                  icon: Icons.local_fire_department_outlined,
                  label: '${lifeSummary.bestHabitStreak} habit streak',
                ),
              if (lifeSummary.averageMood > 0)
                _MetricPill(
                  icon: Icons.mood_outlined,
                  label: '${lifeSummary.averageMood.toStringAsFixed(1)} mood',
                ),
              if (lifeSummary.averageGoalProgress > 0)
                _MetricPill(
                  icon: Icons.track_changes_outlined,
                  label:
                      '${(lifeSummary.averageGoalProgress * 100).round()}% goals',
                ),
              if (lifeSummary.weeklyReviewCount > 0)
                _MetricPill(
                  icon: Icons.rate_review_outlined,
                  label: '${lifeSummary.weeklyReviewCount} weekly review',
                ),
              if (insightsSummary.totalFocusMinutesToday > 0)
                _MetricPill(
                  icon: Icons.hourglass_empty,
                  label:
                      '${insightsSummary.totalFocusMinutesToday} mins focused today',
                ),
            ],
          ),
          if (showOverviewPanels) ...[
            SizedBox(height: spacing),
            _InsightActionStrip(
              overdueCount: nodeIndex.overdueTaskCount,
              highPriorityCount: nodeIndex.highPriorityOpenTaskCount,
              automationCount: automationSuggestions?.readyCount ?? 0,
              onOverdue: () => onSmartViewChanged(SmartNodeViewType.overdue),
              onHighPriority: () => onPriorityChanged(NodePriority.high),
              onAutomations: automationSuggestions == null
                  ? null
                  : () => onReviewAutomations(automationSuggestions!),
            ),
          ],
          if (showAttentionPanel) ...[
            SizedBox(height: spacing),
            _AttentionPanel(attention: attention),
          ],
          SizedBox(height: spacing),
          _SmartViewsBand(
            views: smartViews,
            selectedView: smartViewFilter,
            onChanged: onSmartViewChanged,
          ),
          SizedBox(height: spacing),
          _WorkspaceContextsBand(
            contexts: workspaceContexts,
            selectedProject: projectFilter,
            selectedArea: areaFilter,
            onProjectChanged: onProjectChanged,
            onAreaChanged: onAreaChanged,
          ),
          if (showAutomationPanel) ...[
            SizedBox(height: spacing),
            _AutomationPanel(
              suggestions: automationSuggestions!,
              onReview: () => onReviewAutomations(automationSuggestions!),
            ),
          ],
          if (showAutomationForecast) ...[
            SizedBox(height: spacing),
            _AutomationForecastPanel(forecast: automationForecast),
          ],
          if (showAutomationHealth) ...[
            SizedBox(height: spacing),
            _AutomationHealthPanel(
              health: automationHealth,
              onPauseIssue: onPauseAutomationIssue,
            ),
          ],
          if (showAutomationHistory) ...[
            SizedBox(height: spacing),
            _AutomationHistoryPanel(events: automationEvents),
          ],
          if (showWorkspaceFocus) ...[
            SizedBox(height: spacing),
            _WorkspaceFocusPanel(
              contexts: workspaceContexts,
              today: today,
              onProjectChanged: onProjectChanged,
              onAreaChanged: onAreaChanged,
            ),
          ],
          if (showOverviewPanels) ...[
            SizedBox(height: spacing),
            _LifeRhythmPanel(rhythm: lifeRhythm),
            SizedBox(height: spacing),
            _WeeklyPulsePanel(pulse: weeklyPulse),
            SizedBox(height: spacing),
            _WeeklyReviewPanel(
              review: weeklyReview,
              onCreateWeeklyReview: onCreateWeeklyReview,
              onRescheduleNode: onRescheduleNode,
              onCompleteNode: onCompleteNode,
              onPinGoal: onPinGoal,
              onCreateGoalNextAction: onCreateGoalNextAction,
            ),
            SizedBox(height: spacing),
            _FocusTimerAnalyticsPanel(
              summary: insightsSummary,
              focusSummary: focusInsights,
              today: today,
            ),
            SizedBox(height: spacing),
            _KnowledgeGraphPanel(graph: nodeGraph),
            SizedBox(height: spacing),
            _MissionDashboardPanel(summaries: missionSummaries),
            SizedBox(height: spacing),
            _WorkloadTrendPanel(series: completionTrend),
            SizedBox(height: spacing),
            _HabitRoutineInsightPanel(summary: habitRoutineInsights),
            SizedBox(height: spacing),
            _ReviewInsightPanel(summary: reviewInsights),
            SizedBox(height: spacing),
            _ContextHealthPanel(summary: contextHealth),
            SizedBox(height: spacing),
            _GoalInsightPanel(summary: goalInsights),
            SizedBox(height: spacing),
            _InsightRiskPanel(riskItems: insightRisks),
            SizedBox(height: spacing),
            _RecommendationPanel(
              recommendations: recommendations,
              onSmartViewChanged: onSmartViewChanged,
              onPriorityChanged: onPriorityChanged,
              onCreateWeeklyReview: onCreateWeeklyReview,
              onProjectChanged: onProjectChanged,
              markdownReport: markdownReport,
            ),
            SizedBox(height: spacing),
            _InsightDrillDownPanel(
              nodeIndex: nodeIndex,
              contextHealth: contextHealth,
              habitSummary: habitRoutineInsights.habits,
              reviewSummary: reviewInsights,
              goalSummary: goalInsights,
              onProjectChanged: onProjectChanged,
              onAreaChanged: onAreaChanged,
            ),
          ],
          SizedBox(height: spacing),
          _FilterBand(
            statusFilter: statusFilter,
            priorityFilter: priorityFilter,
            onStatusChanged: onStatusChanged,
            onPriorityChanged: onPriorityChanged,
          ),
          SizedBox(height: spacing),
          _SectionLabel(
            icon: Icons.manage_search_outlined,
            title: 'Focus results',
            subtitle: filteredNodes.isEmpty
                ? 'No nodes match the active filters'
                : '${filteredNodes.length} sorted nodes ready to inspect',
          ),
          SizedBox(height: spacing * 0.75),
          if (filteredNodes.isEmpty)
            const SizedBox(height: 260, child: _EmptyResults())
          else
            for (var index = 0; index < filteredNodes.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              _InsightNodeTile(node: filteredNodes[index]),
            ],
        ],
      ),
    );
  }

  Widget _buildWeeklyDigest(BuildContext context) {
    final theme = Theme.of(context);

    final totalTasks = insightsSummary.taskCount;
    final doneTasks = insightsSummary.completedTaskCount;
    final completionPct = insightsSummary.taskCompletionRate;

    final activeNodesCount = nodeIndex.activeCount;
    final moodAvg = lifeSummary.averageMood;
    final habitCount = nodeIndex.typeCounts[NodeType.habit] ?? 0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Weekly Digest',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                key: const ValueKey('insights-export-button'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _showExportDialog(context),
                icon: const Icon(Icons.download, size: 16),
                label: const Text(
                  'Export Data',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _generateDigestText(
              doneTasks,
              totalTasks,
              completionPct,
              habitCount,
              moodAvg,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(
                alpha: 0.9,
              ),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDigestStatItem(
                context,
                icon: Icons.task_alt,
                value: (completionPct * 100).round(),
                suffix: '%',
                label: 'Tasks Done',
              ),
              _buildDigestStatItem(
                context,
                icon: Icons.hub,
                value: activeNodesCount,
                suffix: '',
                label: 'Active Nodes',
              ),
              _buildDigestStatItem(
                context,
                icon: Icons.mood,
                value: moodAvg,
                suffix: '/5',
                label: 'Mood Avg',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _generateDigestText(
    int done,
    int total,
    double pct,
    int habits,
    double mood,
  ) {
    final buffer = StringBuffer();
    if (total == 0) {
      buffer.write(
        'You have no tasks created this week. Try adding some tasks in the calendar to get started!',
      );
    } else {
      buffer.write(
        'You completed $done of $total tasks (${(pct * 100).round()}% completion rate) this week. ',
      );
      if (pct >= 0.8) {
        buffer.write(
          'Outstanding productivity! You are crushing your outcomes. ',
        );
      } else if (pct >= 0.5) {
        buffer.write('Solid progress, you are moving in the right direction. ');
      } else {
        buffer.write(
          'A quiet week for tasks. Take a moment to sequence your top outcomes. ',
        );
      }
    }

    if (habits > 0) {
      buffer.write('You are tracking $habits habits actively. ');
    }

    if (mood > 0) {
      buffer.write(
        'Your average mood is ${mood.toStringAsFixed(1)}/5.0, reflecting a stable mindset.',
      );
    }
    return buffer.toString();
  }

  Widget _buildDigestStatItem(
    BuildContext context, {
    required IconData icon,
    required num value,
    required String suffix,
    required String label,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          icon,
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
          size: 20,
        ),
        const SizedBox(height: 6),
        AnimatedCounter(
          value: value,
          suffix: suffix,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) =>
          _ExportDataDialog(nodes: nodes, markdownReport: markdownReport),
    );
  }
}

class _InsightsLoadingSkeleton extends StatelessWidget {
  const _InsightsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    return Padding(
      padding: EdgeInsets.all(spacing),
      child: ListView(
        children: const [
          _SkeletonBlock(height: 96, widthFactor: 1),
          SizedBox(height: 12),
          _SkeletonMetricRail(),
          SizedBox(height: 12),
          _SkeletonBlock(height: 180, widthFactor: 1),
          SizedBox(height: 12),
          _SkeletonBlock(height: 120, widthFactor: 0.85),
          SizedBox(height: 12),
          _SkeletonBlock(height: 120, widthFactor: 0.7),
        ],
      ),
    );
  }
}

class _SkeletonMetricRail extends StatelessWidget {
  const _SkeletonMetricRail();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SkeletonPill(),
          SizedBox(width: 8),
          _SkeletonPill(),
          SizedBox(width: 8),
          _SkeletonPill(),
          SizedBox(width: 8),
          _SkeletonPill(),
        ],
      ),
    );
  }
}

class _SkeletonPill extends StatelessWidget {
  const _SkeletonPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Loading insights',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: const SizedBox(width: 132, height: 36),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.height, required this.widthFactor});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Semantics(
        label: 'Loading insights',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.55,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: SizedBox(height: height),
        ),
      ),
    );
  }
}

class _InsightsErrorState extends StatelessWidget {
  const _InsightsErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 36,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                ErrorMessage(message: message, onRetry: onRetry),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewUserEmptyState extends StatelessWidget {
  const _NewUserEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('insights-empty-state'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final copy = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  'No insight signals yet',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Create tasks, habits, goals, or journal notes from Calendar. Insights stay local and become useful as your day pages fill up.',
                  textAlign: compact ? TextAlign.center : TextAlign.start,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HelperChip(label: 'Add 3 tasks'),
                    _HelperChip(label: 'Log focus time'),
                    _HelperChip(label: 'Write a review'),
                  ],
                ),
              ],
            );
            final icon = Icon(
              Icons.explore_outlined,
              size: compact ? 36 : 44,
              color: theme.colorScheme.primary,
            );
            if (compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [icon, const SizedBox(height: 10), copy],
              );
            }
            return Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: copy),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HelperChip extends StatelessWidget {
  const _HelperChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _InsightActionStrip extends StatelessWidget {
  const _InsightActionStrip({
    required this.overdueCount,
    required this.highPriorityCount,
    required this.automationCount,
    required this.onOverdue,
    required this.onHighPriority,
    required this.onAutomations,
  });

  final int overdueCount;
  final int highPriorityCount;
  final int automationCount;
  final VoidCallback onOverdue;
  final VoidCallback onHighPriority;
  final VoidCallback? onAutomations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOverdue = overdueCount > 0;
    final hasHighPriority = highPriorityCount > 0;
    final hasAutomations = automationCount > 0 && onAutomations != null;

    return DecoratedBox(
      key: const ValueKey('insights-action-strip'),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.28,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.tips_and_updates_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested next moves',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _actionSummary(
                      hasOverdue: hasOverdue,
                      hasHighPriority: hasHighPriority,
                      hasAutomations: hasAutomations,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasOverdue)
                  ActionChip(
                    key: const ValueKey('insights-action-overdue'),
                    avatar: const Icon(Icons.warning_amber_outlined, size: 16),
                    label: Text('Review $overdueCount overdue'),
                    onPressed: onOverdue,
                  ),
                if (hasHighPriority)
                  ActionChip(
                    key: const ValueKey('insights-action-high-priority'),
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text('Focus $highPriorityCount high'),
                    onPressed: onHighPriority,
                  ),
                if (hasAutomations)
                  ActionChip(
                    key: const ValueKey('insights-action-automations'),
                    avatar: const Icon(
                      Icons.auto_awesome_motion_outlined,
                      size: 16,
                    ),
                    label: Text('Run $automationCount routines'),
                    onPressed: onAutomations,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _actionSummary({
    required bool hasOverdue,
    required bool hasHighPriority,
    required bool hasAutomations,
  }) {
    if (!hasOverdue && !hasHighPriority && !hasAutomations) {
      return 'Everything looks steady. Use filters below to inspect your system.';
    }
    return 'Jump straight to the items most likely to unblock the day.';
  }
}

class _MissionDashboardPanel extends StatelessWidget {
  const _MissionDashboardPanel({required this.summaries});

  final List<mission.InsightsSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('insights-mission-dashboard'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Mission dashboard', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 980
                    ? 3
                    : width >= 640
                    ? 2
                    : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  childAspectRatio: columns == 1 ? 3.1 : 2.25,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  children: [
                    for (final summary in summaries)
                      _MissionWindowCard(summary: summary),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionWindowCard extends StatelessWidget {
  const _MissionWindowCard({required this.summary});

  final mission.InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _missionStatusColor(theme, summary.status);
    final metrics = summary.current;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _missionWindowLabel(summary.window.kind),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      _missionStatusLabel(summary.status),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MissionMetric(
                  label: 'Open',
                  value: '${metrics.openTasks}',
                  delta: summary.openTaskDelta,
                  lowerIsBetter: true,
                ),
                _MissionMetric(
                  label: 'Done',
                  value: '${metrics.completedTasks}',
                  delta: summary.completedTaskDelta,
                ),
                _MissionMetric(
                  label: 'Overdue',
                  value: '${metrics.overdueTasks}',
                  delta: summary.overdueTaskDelta,
                  lowerIsBetter: true,
                ),
                _MissionMetric(
                  label: 'High',
                  value: '${metrics.highPriorityOpenTasks}',
                  delta: summary.highPriorityOpenTaskDelta,
                  lowerIsBetter: true,
                ),
                _MissionMetric(
                  label: 'Focus',
                  value: '${metrics.focusMinutes}m',
                  delta: summary.focusMinuteDelta,
                ),
                _MissionMetric(
                  label: 'Habit',
                  value: _percentLabel(metrics.habitCompletionRate),
                  delta: (summary.habitCompletionDelta * 100).round(),
                ),
                _MissionMetric(
                  label: 'Review',
                  value: '${metrics.reviewCount}',
                  delta: summary.reviewCountDelta,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionMetric extends StatelessWidget {
  const _MissionMetric({
    required this.label,
    required this.value,
    required this.delta,
    this.lowerIsBetter = false,
  });

  final String label;
  final String value;
  final int delta;
  final bool lowerIsBetter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGood = lowerIsBetter ? delta < 0 : delta > 0;
    final isBad = lowerIsBetter ? delta > 0 : delta < 0;
    final deltaColor = isGood
        ? Colors.greenAccent.shade400
        : isBad
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(value, style: theme.textTheme.titleSmall),
              Text(
                _deltaLabel(delta),
                style: theme.textTheme.labelSmall?.copyWith(color: deltaColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _missionWindowLabel(mission.InsightsWindowKind kind) {
  switch (kind) {
    case mission.InsightsWindowKind.today:
      return 'Today';
    case mission.InsightsWindowKind.week:
      return 'This week';
    case mission.InsightsWindowKind.month:
      return 'This month';
  }
}

String _missionStatusLabel(mission.InsightMissionStatus status) {
  switch (status) {
    case mission.InsightMissionStatus.stable:
      return 'Stable';
    case mission.InsightMissionStatus.improving:
      return 'Improving';
    case mission.InsightMissionStatus.atRisk:
      return 'At risk';
    case mission.InsightMissionStatus.critical:
      return 'Critical';
  }
}

Color _missionStatusColor(
  ThemeData theme,
  mission.InsightMissionStatus status,
) {
  switch (status) {
    case mission.InsightMissionStatus.stable:
      return theme.colorScheme.primary;
    case mission.InsightMissionStatus.improving:
      return Colors.greenAccent.shade400;
    case mission.InsightMissionStatus.atRisk:
      return Colors.orangeAccent.shade400;
    case mission.InsightMissionStatus.critical:
      return theme.colorScheme.error;
  }
}

String _deltaLabel(int delta) {
  if (delta == 0) return '±0';
  return delta > 0 ? '+$delta' : '$delta';
}

class _WorkloadTrendPanel extends StatelessWidget {
  const _WorkloadTrendPanel({required this.series});

  final trends.InsightTrendSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalDone = series.points.fold<int>(
      0,
      (total, point) => total + point.completedTasks,
    );
    final totalOpen = series.points.fold<int>(
      0,
      (total, point) => total + point.openTasks,
    );
    final totalOverdue = series.points.fold<int>(
      0,
      (total, point) => total + point.overdueTasks,
    );
    final totalHighPriority = series.points.fold<int>(
      0,
      (total, point) => total + point.highPriorityOpenTasks,
    );

    return DecoratedBox(
      key: const ValueKey('insights-workload-trend-panel'),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface,
        shape: DoodleShapeBorder(
          side: BorderSide(color: theme.dividerColor),
          radius: 12,
          wobble: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stacked_bar_chart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Completion and workload trends',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _TrendChip(
                  label: 'Done ${_trendLabel(series.completionDirection)}',
                  direction: series.completionDirection,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (series.points.isEmpty || series.isEmpty)
              Text(
                'No task trend data in the selected window yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrendTotalPill(
                    label: 'Done',
                    value: totalDone,
                    color: Colors.greenAccent.shade400,
                  ),
                  _TrendTotalPill(
                    label: 'Open',
                    value: totalOpen,
                    color: theme.colorScheme.primary,
                  ),
                  _TrendTotalPill(
                    label: 'Overdue',
                    value: totalOverdue,
                    color: theme.colorScheme.error,
                  ),
                  _TrendTotalPill(
                    label: 'High',
                    value: totalHighPriority,
                    color: Colors.orangeAccent.shade400,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 112,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final point in series.points)
                      Expanded(child: _TrendDayBar(point: point)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TrendChip(
                    label: 'Open ${_trendLabel(series.openWorkDirection)}',
                    direction: series.openWorkDirection,
                  ),
                  _TrendChip(
                    label: 'Overdue ${_trendLabel(series.overdueDirection)}',
                    direction: series.overdueDirection,
                  ),
                  _TrendChip(
                    label:
                        'High priority ${_trendLabel(series.highPriorityDirection)}',
                    direction: series.highPriorityDirection,
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

class _TrendTotalPill extends StatelessWidget {
  const _TrendTotalPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.08),
        shape: DoodleShapeBorder(
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          radius: 999,
          wobble: 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$label $value',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _TrendDayBar extends StatelessWidget {
  const _TrendDayBar({required this.point});

  final trends.InsightTrendPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = [
      point.openTasks,
      point.completedTasks,
      point.overdueTasks,
      point.highPriorityOpenTasks,
      1,
    ].reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _MiniBar(
            value: point.completedTasks,
            maxValue: maxValue,
            color: Colors.greenAccent.shade400,
          ),
          const SizedBox(height: 2),
          _MiniBar(
            value: point.openTasks,
            maxValue: maxValue,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 2),
          _MiniBar(
            value: point.overdueTasks,
            maxValue: maxValue,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 2),
          _MiniBar(
            value: point.highPriorityOpenTasks,
            maxValue: maxValue,
            color: Colors.orangeAccent.shade400,
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat('E').format(point.day).substring(0, 1),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final int value;
  final int maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final height = value == 0 ? 4.0 : 4.0 + (value / maxValue) * 18.0;
    return Tooltip(
      message: '$value',
      child: Container(
        width: 18,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: value == 0 ? 0.25 : 0.85),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _TrendChip extends StatelessWidget {
  const _TrendChip({required this.label, required this.direction});

  final String label;
  final trends.InsightTrendDirection direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _trendColor(theme, direction);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_trendIcon(direction), size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

String _trendLabel(trends.InsightTrendDirection direction) {
  switch (direction) {
    case trends.InsightTrendDirection.up:
      return 'up';
    case trends.InsightTrendDirection.down:
      return 'down';
    case trends.InsightTrendDirection.flat:
      return 'flat';
    case trends.InsightTrendDirection.volatile:
      return 'volatile';
  }
}

IconData _trendIcon(trends.InsightTrendDirection direction) {
  switch (direction) {
    case trends.InsightTrendDirection.up:
      return Icons.trending_up;
    case trends.InsightTrendDirection.down:
      return Icons.trending_down;
    case trends.InsightTrendDirection.flat:
      return Icons.trending_flat;
    case trends.InsightTrendDirection.volatile:
      return Icons.show_chart;
  }
}

Color _trendColor(ThemeData theme, trends.InsightTrendDirection direction) {
  switch (direction) {
    case trends.InsightTrendDirection.up:
      return Colors.greenAccent.shade400;
    case trends.InsightTrendDirection.down:
      return Colors.orangeAccent.shade400;
    case trends.InsightTrendDirection.flat:
      return theme.colorScheme.onSurfaceVariant;
    case trends.InsightTrendDirection.volatile:
      return theme.colorScheme.error;
  }
}

class _HabitRoutineInsightPanel extends StatelessWidget {
  const _HabitRoutineInsightPanel({required this.summary});

  final habits.HabitRoutineInsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final habit = summary.habits;
    final routine = summary.routines;

    return DecoratedBox(
      key: const ValueKey('insights-habit-routine-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.repeat_on_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Habit and routine intelligence',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _TrendChip(
                  label: 'Habits ${_percentLabel(habit.completionRate)}',
                  direction: habit.completionRate >= 0.75
                      ? trends.InsightTrendDirection.up
                      : habit.completionRate == 0
                      ? trends.InsightTrendDirection.flat
                      : trends.InsightTrendDirection.down,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (habit.habitCount == 0 &&
                routine.appliedCount == 0 &&
                routine.skippedCount == 0 &&
                routine.snoozedCount == 0)
              Text(
                'No habit or routine signal in this window yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              _MetricRail(
                children: [
                  _MetricPill(
                    icon: Icons.check_circle_outline,
                    label:
                        '${habit.completedCount}/${habit.expectedCount} habit completions',
                  ),
                  if (habit.streakAtRisk != null)
                    _MetricPill(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Streak at risk: ${habit.streakAtRisk!.title}',
                    ),
                  if (habit.mostConsistentHabit != null)
                    _MetricPill(
                      icon: Icons.workspace_premium_outlined,
                      label:
                          'Most consistent: ${habit.mostConsistentHabit!.title}',
                    ),
                  _MetricPill(
                    icon: Icons.playlist_add_check_outlined,
                    label: '${routine.appliedCount} applied',
                  ),
                  _MetricPill(
                    icon: Icons.block_outlined,
                    label: '${routine.skippedCount} skipped',
                  ),
                  _MetricPill(
                    icon: Icons.snooze_outlined,
                    label: '${routine.snoozedCount} snoozed',
                  ),
                  if (routine.frequentlySnoozedRoutine != null)
                    _MetricPill(
                      icon: Icons.warning_amber_outlined,
                      label:
                          'Frequently snoozed: ${routine.frequentlySnoozedRoutine}',
                    ),
                ],
              ),
              if (habit.missedHabits.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Missed habits',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final node in habit.missedHabits.take(4))
                      Chip(
                        avatar: const Icon(
                          Icons.radio_button_unchecked,
                          size: 16,
                        ),
                        label: Text(node.title),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewInsightPanel extends StatelessWidget {
  const _ReviewInsightPanel({required this.summary});

  final reviews.ReviewInsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastReview = summary.lastReviewDate;

    return DecoratedBox(
      key: const ValueKey('insights-review-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Review and journaling cadence',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (!summary.hasReviewThisWeek)
                  const _TrendChip(
                    label: 'No review this week',
                    direction: trends.InsightTrendDirection.down,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.edit_note_outlined,
                  label: '${summary.journalCount} journals',
                ),
                _MetricPill(
                  icon: Icons.fact_check_outlined,
                  label: '${summary.reviewCount} reviews',
                ),
                _MetricPill(
                  icon: Icons.local_fire_department_outlined,
                  label: '${summary.currentReflectionStreak} reflection streak',
                ),
                _MetricPill(
                  icon: Icons.timeline_outlined,
                  label: '${summary.longestReflectionStreak} longest streak',
                ),
                if (lastReview != null)
                  _MetricPill(
                    icon: Icons.event_available_outlined,
                    label: 'Last ${DateFormat('MMM d').format(lastReview)}',
                  ),
                if (summary.reviewGaps.isNotEmpty)
                  _MetricPill(
                    icon: Icons.warning_amber_outlined,
                    label: '${summary.reviewGaps.first.dayCount}d review gap',
                  ),
              ],
            ),
            if (summary.keywordBuckets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Recurring themes',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in summary.keywordBuckets.entries)
                    Chip(label: Text('${entry.key} ${entry.value}')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContextHealthPanel extends StatelessWidget {
  const _ContextHealthPanel({required this.summary});

  final health.ContextHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = summary.items.take(6).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-context-health-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Project and area health',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (summary.neglectedContexts.isNotEmpty)
                  _TrendChip(
                    label: '${summary.neglectedContexts.length} neglected',
                    direction: trends.InsightTrendDirection.down,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (visibleItems.isEmpty)
              Text(
                'No project or area context yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  horizontalMargin: 0,
                  headingTextStyle: theme.textTheme.labelMedium,
                  dataTextStyle: theme.textTheme.bodySmall,
                  columns: const [
                    DataColumn(label: Text('Context')),
                    DataColumn(label: Text('Open')),
                    DataColumn(label: Text('Done')),
                    DataColumn(label: Text('Late')),
                    DataColumn(label: Text('High')),
                    DataColumn(label: Text('Health')),
                  ],
                  rows: [
                    for (final item in visibleItems)
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${item.isProject ? 'Project' : 'Area'} ${item.name}',
                            ),
                          ),
                          DataCell(Text('${item.openTasks}')),
                          DataCell(Text('${item.completedTasks}')),
                          DataCell(Text('${item.overdueTasks}')),
                          DataCell(Text('${item.highPriorityOpenTasks}')),
                          DataCell(
                            Text(
                              _contextHealthLabel(item.status),
                              style: TextStyle(
                                color: _contextHealthColor(theme, item.status),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _MetricRail(
                children: [
                  if (summary.hotContexts.isNotEmpty)
                    _MetricPill(
                      icon: Icons.local_fire_department_outlined,
                      label: 'Hot: ${summary.hotContexts.first.name}',
                    ),
                  if (summary.neglectedContexts.isNotEmpty)
                    _MetricPill(
                      icon: Icons.schedule_outlined,
                      label:
                          'Neglected: ${summary.neglectedContexts.first.name}',
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

String _contextHealthLabel(health.ContextHealthStatus status) {
  switch (status) {
    case health.ContextHealthStatus.good:
      return 'good';
    case health.ContextHealthStatus.watch:
      return 'watch';
    case health.ContextHealthStatus.stale:
      return 'stale';
    case health.ContextHealthStatus.critical:
      return 'critical';
  }
}

Color _contextHealthColor(ThemeData theme, health.ContextHealthStatus status) {
  switch (status) {
    case health.ContextHealthStatus.good:
      return Colors.greenAccent.shade400;
    case health.ContextHealthStatus.watch:
      return Colors.orangeAccent.shade400;
    case health.ContextHealthStatus.stale:
      return theme.colorScheme.tertiary;
    case health.ContextHealthStatus.critical:
      return theme.colorScheme.error;
  }
}

class _GoalInsightPanel extends StatelessWidget {
  const _GoalInsightPanel({required this.summary});

  final goals.GoalInsightSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('insights-goal-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.track_changes_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Goal and milestone progress',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (summary.needsNextActionGoals.isNotEmpty)
                  const _TrendChip(
                    label: 'Goal needs next action',
                    direction: trends.InsightTrendDirection.down,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (summary.goalCount == 0)
              Text(
                'No goal nodes yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              _MetricRail(
                children: [
                  _MetricPill(
                    icon: Icons.flag_outlined,
                    label: '${summary.goalCount} goals',
                  ),
                  _MetricPill(
                    icon: Icons.stacked_line_chart_outlined,
                    label:
                        '${_percentLabel(summary.averageProgress)} avg progress',
                  ),
                  _MetricPill(
                    icon: Icons.radio_button_unchecked,
                    label: '${summary.notStartedCount} not started',
                  ),
                  _MetricPill(
                    icon: Icons.pending_actions_outlined,
                    label: '${summary.inProgressCount} in progress',
                  ),
                  _MetricPill(
                    icon: Icons.check_circle_outline,
                    label: '${summary.completedCount} done',
                  ),
                  if (summary.milestoneMomentumCount > 0)
                    _MetricPill(
                      icon: Icons.rocket_launch_outlined,
                      label:
                          '${summary.milestoneMomentumCount} milestone momentum',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (summary.stalledGoals.isNotEmpty)
                    _GoalInsightChip(
                      icon: Icons.warning_amber_outlined,
                      label:
                          'Stalled: ${summary.stalledGoals.first.node.title}',
                      color: theme.colorScheme.error,
                    ),
                  if (summary.recentlyProgressedGoals.isNotEmpty)
                    _GoalInsightChip(
                      icon: Icons.trending_up,
                      label:
                          'Recently progressed: ${summary.recentlyProgressedGoals.first.node.title}',
                      color: Colors.greenAccent.shade400,
                    ),
                  if (summary.needsNextActionGoals.isNotEmpty)
                    _GoalInsightChip(
                      icon: Icons.add_task_outlined,
                      label:
                          'Next action: ${summary.needsNextActionGoals.first.node.title}',
                      color: Colors.orangeAccent.shade400,
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

class _GoalInsightChip extends StatelessWidget {
  const _GoalInsightChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightRiskPanel extends StatelessWidget {
  const _InsightRiskPanel({required this.riskItems});

  final List<risks.InsightRisk> riskItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleRisks = riskItems.take(5).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-risk-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Smart risk detection',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _TrendChip(
                  label: riskItems.isEmpty
                      ? 'No active risks'
                      : '${riskItems.length} risks',
                  direction: riskItems.isEmpty
                      ? trends.InsightTrendDirection.flat
                      : trends.InsightTrendDirection.volatile,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (visibleRisks.isEmpty)
              Text(
                'No actionable risk detected in local data.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: [
                  for (final risk in visibleRisks) _InsightRiskTile(risk: risk),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InsightRiskTile extends StatelessWidget {
  const _InsightRiskTile({required this.risk});

  final risks.InsightRisk risk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _riskSeverityColor(theme, risk.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_riskSeverityIcon(risk.severity), color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      risk.title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(risk.message, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      _riskActionLabel(risk.actionType),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _riskSeverityColor(ThemeData theme, risks.InsightRiskSeverity severity) {
  switch (severity) {
    case risks.InsightRiskSeverity.info:
      return theme.colorScheme.primary;
    case risks.InsightRiskSeverity.watch:
      return Colors.orangeAccent.shade400;
    case risks.InsightRiskSeverity.high:
      return theme.colorScheme.tertiary;
    case risks.InsightRiskSeverity.critical:
      return theme.colorScheme.error;
  }
}

IconData _riskSeverityIcon(risks.InsightRiskSeverity severity) {
  switch (severity) {
    case risks.InsightRiskSeverity.info:
      return Icons.info_outline;
    case risks.InsightRiskSeverity.watch:
      return Icons.visibility_outlined;
    case risks.InsightRiskSeverity.high:
      return Icons.priority_high;
    case risks.InsightRiskSeverity.critical:
      return Icons.report_gmailerrorred;
  }
}

String _riskActionLabel(risks.InsightRiskActionType actionType) {
  switch (actionType) {
    case risks.InsightRiskActionType.openCalendar:
      return 'Action: open Calendar';
    case risks.InsightRiskActionType.openDayReview:
      return 'Action: open Day review';
    case risks.InsightRiskActionType.filterContext:
      return 'Action: inspect context';
    case risks.InsightRiskActionType.createWeeklyReview:
      return 'Action: create weekly review';
    case risks.InsightRiskActionType.scheduleOverdue:
      return 'Action: schedule overdue tasks';
    case risks.InsightRiskActionType.balanceWorkload:
      return 'Action: balance workload';
  }
}

class _RecommendationPanel extends StatelessWidget {
  const _RecommendationPanel({
    required this.recommendations,
    required this.onSmartViewChanged,
    required this.onPriorityChanged,
    required this.onCreateWeeklyReview,
    required this.onProjectChanged,
    required this.markdownReport,
  });

  final List<recs.InsightRecommendation> recommendations;
  final ValueChanged<SmartNodeViewType> onSmartViewChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final Future<void> Function() onCreateWeeklyReview;
  final ValueChanged<String> onProjectChanged;
  final String markdownReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = recommendations.take(5).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-recommendation-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recommended next actions',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (visibleItems.isEmpty)
              Text(
                'No recommendations right now.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Column(
                children: [
                  for (final item in visibleItems)
                    _RecommendationTile(
                      item: item,
                      onPressed: () => _runRecommendation(context, item),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _runRecommendation(
    BuildContext context,
    recs.InsightRecommendation item,
  ) {
    switch (item.action) {
      case recs.InsightRecommendationAction.openCalendar:
        context.go(AppRoute.calendar.path);
      case recs.InsightRecommendationAction.openDayReview:
        context.go(AppRoute.calendar.path);
      case recs.InsightRecommendationAction.filterContext:
        final contextName = item.contextName;
        if (contextName != null && contextName.isNotEmpty) {
          onProjectChanged(contextName);
        }
      case recs.InsightRecommendationAction.createWeeklyReview:
        onCreateWeeklyReview();
      case recs.InsightRecommendationAction.scheduleOverdueTasks:
        onSmartViewChanged(SmartNodeViewType.overdue);
      case recs.InsightRecommendationAction.applyDayTemplate:
        context.go(AppRoute.calendar.path);
      case recs.InsightRecommendationAction.balanceWorkload:
        onPriorityChanged(NodePriority.high);
      case recs.InsightRecommendationAction.exportReport:
        Clipboard.setData(ClipboardData(text: markdownReport));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Markdown report copied to clipboard')),
        );
    }
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.item, required this.onPressed});

  final recs.InsightRecommendation item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(
                _recommendationIcon(item.action),
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(item.message, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onPressed,
                child: Text(_recommendationActionLabel(item.action)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _recommendationIcon(recs.InsightRecommendationAction action) {
  switch (action) {
    case recs.InsightRecommendationAction.openCalendar:
      return Icons.calendar_month_outlined;
    case recs.InsightRecommendationAction.openDayReview:
      return Icons.today_outlined;
    case recs.InsightRecommendationAction.filterContext:
      return Icons.filter_alt_outlined;
    case recs.InsightRecommendationAction.createWeeklyReview:
      return Icons.rate_review_outlined;
    case recs.InsightRecommendationAction.scheduleOverdueTasks:
      return Icons.event_repeat_outlined;
    case recs.InsightRecommendationAction.applyDayTemplate:
      return Icons.dashboard_customize_outlined;
    case recs.InsightRecommendationAction.balanceWorkload:
      return Icons.balance_outlined;
    case recs.InsightRecommendationAction.exportReport:
      return Icons.ios_share_outlined;
  }
}

String _recommendationActionLabel(recs.InsightRecommendationAction action) {
  switch (action) {
    case recs.InsightRecommendationAction.openCalendar:
      return 'Open';
    case recs.InsightRecommendationAction.openDayReview:
      return 'Review';
    case recs.InsightRecommendationAction.filterContext:
      return 'Filter';
    case recs.InsightRecommendationAction.createWeeklyReview:
      return 'Create';
    case recs.InsightRecommendationAction.scheduleOverdueTasks:
      return 'Schedule';
    case recs.InsightRecommendationAction.applyDayTemplate:
      return 'Apply';
    case recs.InsightRecommendationAction.balanceWorkload:
      return 'Balance';
    case recs.InsightRecommendationAction.exportReport:
      return 'Export';
  }
}

class _LifeRhythmPanel extends StatelessWidget {
  const _LifeRhythmPanel({required this.rhythm});

  final LifeOsRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('insights-life-rhythm-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_border, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Life rhythm', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.monitor_heart_outlined,
                  label: rhythm.scoreLabel,
                ),
                _MetricPill(
                  icon: Icons.edit_note_outlined,
                  label:
                      '${rhythm.journalDayCount}/${rhythm.windowDayCount} journal days',
                ),
                _MetricPill(
                  icon: Icons.repeat_on_outlined,
                  label:
                      '${rhythm.habitCompletionDayCount}/${rhythm.windowDayCount} habit days',
                ),
                _MetricPill(
                  icon: Icons.rate_review_outlined,
                  label: rhythm.hasWeeklyReviewThisWeek
                      ? 'Weekly review done'
                      : 'Weekly review missing',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyPulsePanel extends StatelessWidget {
  const _WeeklyPulsePanel({required this.pulse});

  final InsightsWeeklyPulse pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busiestDay = pulse.busiestDay;

    return DecoratedBox(
      key: const ValueKey('insights-weekly-pulse-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Weekly pulse', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.calendar_view_week_outlined,
                  label:
                      '${pulse.activeDayCount} active / ${pulse.quietDayCount} quiet',
                ),
                _MetricPill(
                  icon: Icons.auto_graph_outlined,
                  label: busiestDay == null
                      ? 'No activity'
                      : 'Busiest ${dayKey(busiestDay)}',
                ),
                _MetricPill(
                  icon: Icons.pending_actions_outlined,
                  label: _countLabel(pulse.upcomingTaskCount, 'upcoming task'),
                ),
                _MetricPill(
                  icon: Icons.task_alt_outlined,
                  label:
                      '${_percentLabel(pulse.taskCompletionRate)} week completion',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in pulse.days) _WeeklyPulseDayPill(day: day),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyReviewPanel extends StatelessWidget {
  const _WeeklyReviewPanel({
    required this.review,
    required this.onCreateWeeklyReview,
    required this.onRescheduleNode,
    required this.onCompleteNode,
    required this.onPinGoal,
    required this.onCreateGoalNextAction,
  });

  final InsightsWeeklyReview review;
  final Future<void> Function() onCreateWeeklyReview;
  final Future<void> Function(MindmapNode node) onRescheduleNode;
  final Future<void> Function(MindmapNode node) onCompleteNode;
  final Future<void> Function(MindmapNode node) onPinGoal;
  final Future<void> Function(MindmapNode node) onCreateGoalNextAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('insights-weekly-review-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Weekly review',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('insights-create-weekly-review'),
                  onPressed: onCreateWeeklyReview,
                  icon: const Icon(Icons.add_task_outlined, size: 16),
                  label: const Text('Create review'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.task_alt_outlined,
                  label: _countLabel(
                    review.completedTasks.length,
                    'recent win',
                  ),
                ),
                _MetricPill(
                  icon: Icons.warning_amber_outlined,
                  label: _countLabel(review.overdueTasks.length, 'overdue'),
                ),
                _MetricPill(
                  icon: Icons.flag_outlined,
                  label: _countLabel(
                    review.activeGoals.length,
                    'goal to review',
                  ),
                ),
                _MetricPill(
                  icon: Icons.rate_review_outlined,
                  label: _countLabel(review.reviewNotes.length, 'review note'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ReviewList(
                  title: 'Wins',
                  empty: 'No completed tasks this week',
                  nodes: review.completedTasks,
                  icon: Icons.emoji_events_outlined,
                ),
                _ReviewList(
                  title: 'Needs attention',
                  empty: 'No overdue tasks',
                  nodes: review.overdueTasks,
                  icon: Icons.priority_high_rounded,
                  onRescheduleNode: onRescheduleNode,
                  onCompleteNode: onCompleteNode,
                ),
                _ReviewList(
                  title: 'Goals',
                  empty: 'No active goals',
                  nodes: review.activeGoals,
                  icon: Icons.flag_outlined,
                  onPinNode: onPinGoal,
                  onCreateNextAction: onCreateGoalNextAction,
                ),
              ],
            ),
            if (review.suggestedActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Suggested actions', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              for (final action in review.suggestedActions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_right_rounded, size: 18),
                      const SizedBox(width: 4),
                      Expanded(child: Text(action)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.title,
    required this.empty,
    required this.nodes,
    required this.icon,
    this.onRescheduleNode,
    this.onCompleteNode,
    this.onPinNode,
    this.onCreateNextAction,
  });

  final String title;
  final String empty;
  final List<MindmapNode> nodes;
  final IconData icon;
  final Future<void> Function(MindmapNode node)? onRescheduleNode;
  final Future<void> Function(MindmapNode node)? onCompleteNode;
  final Future<void> Function(MindmapNode node)? onPinNode;
  final Future<void> Function(MindmapNode node)? onCreateNextAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.25,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.65)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(title, style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 8),
              if (nodes.isEmpty)
                Text(
                  empty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                for (final node in nodes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '• ${node.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (onRescheduleNode != null)
                          IconButton(
                            tooltip: 'Reschedule tomorrow',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.event_repeat, size: 16),
                            onPressed: () => onRescheduleNode?.call(node),
                          ),
                        if (onCompleteNode != null)
                          IconButton(
                            tooltip: 'Mark done',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 16,
                            ),
                            onPressed: () => onCompleteNode?.call(node),
                          ),
                        if (onPinNode != null)
                          IconButton(
                            tooltip: 'Pin goal',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.push_pin_outlined, size: 16),
                            onPressed: () => onPinNode?.call(node),
                          ),
                        if (onCreateNextAction != null)
                          IconButton(
                            tooltip: 'Create next action',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_task_outlined, size: 16),
                            onPressed: () => onCreateNextAction?.call(node),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyPulseDayPill extends StatelessWidget {
  const _WeeklyPulseDayPill({required this.day});

  final InsightsDayPulse day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = day.isActive;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: 104,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            '${dayKey(day.day)} ${day.nodeCount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _AutomationPanel extends StatelessWidget {
  const _AutomationPanel({required this.suggestions, required this.onReview});

  final AutomationSuggestions suggestions;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('insights-automation-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_motion_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Automation', style: theme.textTheme.titleSmall),
                ),
                TextButton.icon(
                  key: const ValueKey('insights-automation-review-action'),
                  onPressed: onReview,
                  icon: const Icon(Icons.tune_outlined, size: 16),
                  label: Text(suggestions.primaryActionLabel),
                ),
              ],
            ),
            if (suggestions.completedCount > 0) ...[
              const SizedBox(height: 10),
              _AutomationStatusPill(
                icon: Icons.check_circle_outline,
                label: '${suggestions.completedCount} completed',
              ),
            ],
            if (suggestions.skippedTodayCount > 0) ...[
              const SizedBox(height: 10),
              _AutomationStatusPill(
                icon: Icons.block_outlined,
                label: '${suggestions.skippedTodayCount} skipped',
              ),
            ],
            if (suggestions.snoozedTodayCount > 0) ...[
              const SizedBox(height: 10),
              _AutomationStatusPill(
                icon: Icons.snooze_outlined,
                label: '${suggestions.snoozedTodayCount} snoozed',
              ),
            ],
            const SizedBox(height: 10),
            for (var index = 0; index < suggestions.items.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _AutomationSuggestionRow(item: suggestions.items[index]),
            ],
            if (suggestions.items.isEmpty &&
                (suggestions.completedItems.isNotEmpty ||
                    suggestions.skippedItems.isNotEmpty ||
                    suggestions.snoozedItems.isNotEmpty)) ...[
              const SizedBox(height: 2),
              Text(
                'All due routines have been handled for this day.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutomationForecastPanel extends StatelessWidget {
  const _AutomationForecastPanel({required this.forecast});

  final AutomationForecast forecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcomingItems = forecast.weekItems.take(6).toList(growable: false);
    final pausedRules = forecast.pausedRules.take(3).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-automation-forecast-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.online_prediction, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Automation forecast', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.today_outlined,
                  label: '${forecast.tomorrowCount} tomorrow',
                ),
                _MetricPill(
                  icon: Icons.date_range_outlined,
                  label: '${forecast.weekCount} next 7d',
                ),
                if (forecast.pausedCount > 0)
                  _MetricPill(
                    icon: Icons.pause_circle_outline,
                    label: '${forecast.pausedCount} paused',
                  ),
              ],
            ),
            if (upcomingItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in upcomingItems)
                    _AutomationForecastItemPill(item: item),
                ],
              ),
            ],
            if (pausedRules.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final rule in pausedRules)
                    _PausedAutomationRulePill(rule: rule),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutomationHealthPanel extends StatelessWidget {
  const _AutomationHealthPanel({
    required this.health,
    required this.onPauseIssue,
  });

  final AutomationHealth health;
  final Future<void> Function(AutomationHealthIssue) onPauseIssue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issues = health.issues.take(4).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-automation-health-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Automation health',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _AutomationStatusPill(
                  icon: Icons.warning_amber_outlined,
                  label: health.conflictCount == 1
                      ? '1 conflict'
                      : '${health.conflictCount} conflicts',
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < issues.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _AutomationHealthIssueRow(
                issue: issues[index],
                onPause: () => onPauseIssue(issues[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutomationHealthIssueRow extends StatelessWidget {
  const _AutomationHealthIssueRow({required this.issue, required this.onPause});

  final AutomationHealthIssue issue;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_outlined,
          size: 20,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                issue.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                issue.affectedLabels.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 3),
              Text(
                issue.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (issue.canPauseRules) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            key: ValueKey('automation-health-pause-${issue.id}'),
            onPressed: onPause,
            icon: const Icon(Icons.pause_circle_outline, size: 16),
            label: const Text('Pause duplicates'),
          ),
        ],
      ],
    );
  }
}

class _AutomationHistoryPanel extends StatelessWidget {
  const _AutomationHistoryPanel({required this.events});

  final List<AutomationEventRecord> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentEvents = events.take(4).toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-automation-history-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Automation history',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                _AutomationStatusPill(
                  icon: Icons.event_note_outlined,
                  label: events.length == 1
                      ? '1 event'
                      : '${events.length} events',
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < recentEvents.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _AutomationHistoryRow(event: recentEvents[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutomationHistoryRow extends StatelessWidget {
  const _AutomationHistoryRow({required this.event});

  final AutomationEventRecord event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.fact_check_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                event.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AutomationForecastItemPill extends StatelessWidget {
  const _AutomationForecastItemPill({required this.item});

  final AutomationForecastItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 154,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.36,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 3),
              Text(item.dayLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PausedAutomationRulePill extends StatelessWidget {
  const _PausedAutomationRulePill({required this.rule});

  final AutomationRuleRecord rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 6),
            Text(
              'Paused: ${rule.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AutomationStatusPill extends StatelessWidget {
  const _AutomationStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomationCenterDialog extends ConsumerStatefulWidget {
  const _AutomationCenterDialog({required this.suggestions});

  final AutomationSuggestions suggestions;

  @override
  ConsumerState<_AutomationCenterDialog> createState() {
    return _AutomationCenterDialogState();
  }
}

class _AutomationCenterDialogState
    extends ConsumerState<_AutomationCenterDialog> {
  late Set<String> _selectedRoutineIds;
  List<AutomationRuleRecord> _automationRules = const [];
  bool _isLoadingRules = true;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _selectedRoutineIds = {
      for (final item in widget.suggestions.items) item.routineId,
    };
    _loadAutomationRules();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const ValueKey('automation-center-dialog'),
      title: const Text('Automation center'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AutomationCenterChip(
                  icon: Icons.playlist_add_check_outlined,
                  label: '${widget.suggestions.readyCount} ready',
                ),
                _AutomationCenterChip(
                  icon: Icons.block_outlined,
                  label: '${widget.suggestions.blockedCount} unavailable',
                ),
                _AutomationCenterChip(
                  icon: Icons.event_outlined,
                  label: dayKey(widget.suggestions.day),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('automation-center-add-rule-button'),
                  onPressed: _isApplying ? null : _showNewRuleDialog,
                  icon: const Icon(Icons.add_task_outlined, size: 16),
                  label: const Text('Add rule'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preset library', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in defaultAutomationRulePresets)
                          FilterChip(
                            key: ValueKey(
                              'automation-center-preset-${preset.id}',
                            ),
                            avatar: Icon(
                              _hasAutomationPreset(preset)
                                  ? Icons.check_circle_outline
                                  : Icons.add_outlined,
                              size: 16,
                            ),
                            label: Text(preset.label),
                            selected: _hasAutomationPreset(preset),
                            onSelected:
                                _isApplying || _hasAutomationPreset(preset)
                                ? null
                                : (_) => _installPresetRule(preset),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_automationRules.isNotEmpty) ...[
                      Text('Custom rules', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      for (final rule in _automationRules)
                        _AutomationRuleManageRow(
                          rule: rule,
                          onEdit: _isApplying
                              ? null
                              : () => _showEditRuleDialog(rule),
                          onToggle: _isApplying
                              ? null
                              : () => _toggleRule(rule),
                          onDelete: _isApplying
                              ? null
                              : () => _deleteRule(rule),
                        ),
                      const SizedBox(height: 12),
                    ] else if (_isLoadingRules) ...[
                      Text(
                        'Loading custom rules...',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.suggestions.items.isNotEmpty) ...[
                      Text('Ready to apply', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      for (final item in widget.suggestions.items)
                        CheckboxListTile(
                          key: ValueKey(
                            'automation-center-routine-${item.routineId}',
                          ),
                          value: _selectedRoutineIds.contains(item.routineId),
                          onChanged: _isApplying
                              ? null
                              : (_) => _toggleRoutine(item.routineId),
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -4,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.title),
                          subtitle: Text(
                            item.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ] else
                      Text(
                        'No routines are waiting to be applied.',
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 12),
                    Text('Schedule manager', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 66,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in widget.suggestions.scheduleItems)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _AutomationScheduleRow(item: item),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.suggestions.completedItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Completed today',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      for (final item in widget.suggestions.completedItems)
                        ListTile(
                          key: ValueKey(
                            'automation-center-completed-${item.routineId}',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.check_circle_outline,
                            color: theme.colorScheme.primary,
                          ),
                          title: Text(item.title),
                          subtitle: Text(item.message),
                        ),
                    ],
                    if (widget.suggestions.skippedItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Skipped today', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      for (final item in widget.suggestions.skippedItems)
                        ListTile(
                          key: ValueKey(
                            'automation-center-skipped-${item.routineId}',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.block_outlined,
                            color: theme.colorScheme.outline,
                          ),
                          title: Text(item.title),
                          subtitle: Text(item.message),
                        ),
                    ],
                    if (widget.suggestions.snoozedItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Snoozed today', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      for (final item in widget.suggestions.snoozedItems)
                        ListTile(
                          key: ValueKey(
                            'automation-center-snoozed-${item.routineId}',
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.snooze_outlined,
                            color: theme.colorScheme.outline,
                          ),
                          title: Text(item.title),
                          subtitle: Text(item.message),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (_selectedRoutineIds.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Select at least one routine to apply or skip.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _selectedRoutineIds.isEmpty || _isApplying
              ? null
              : _skipSelected,
          icon: const Icon(Icons.block_outlined),
          label: Text('Skip selected ${_selectedRoutineIds.length}'),
        ),
        OutlinedButton.icon(
          onPressed: _selectedRoutineIds.isEmpty || _isApplying
              ? null
              : _snoozeSelected,
          icon: const Icon(Icons.snooze_outlined),
          label: Text('Snooze selected ${_selectedRoutineIds.length}'),
        ),
        FilledButton.icon(
          onPressed: _selectedRoutineIds.isEmpty || _isApplying
              ? null
              : _applySelected,
          icon: _isApplying
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check_outlined),
          label: Text(
            _isApplying
                ? 'Applying'
                : 'Apply selected ${_selectedRoutineIds.length}',
          ),
        ),
      ],
    );
  }

  void _toggleRoutine(String routineId) {
    setState(() {
      final next = {..._selectedRoutineIds};
      if (!next.remove(routineId)) {
        next.add(routineId);
      }
      _selectedRoutineIds = next;
    });
  }

  Future<void> _loadAutomationRules() async {
    final repository = ref.read(mindmapRepositoryProvider);
    final nodes = await repository.listNodes();
    if (!mounted) return;
    setState(() {
      _automationRules = automationRulesFromNodes(nodes);
      _isLoadingRules = false;
    });
  }

  Future<void> _showNewRuleDialog() async {
    final result = await showDialog<_AutomationRuleFormResult>(
      context: context,
      builder: (context) => const _NewAutomationRuleDialog(),
    );
    if (result == null) return;

    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final day = widget.suggestions.day.dateOnly;
    final now = DateTime.now();
    final ruleNode = createAutomationRuleNode(
      id: _automationRuleIdFromLabel(result.label, now),
      label: result.label,
      templateId: result.templateId,
      rule: result.rule,
      enabled: result.enabled,
      day: day,
      now: now,
    );

    await repository.saveNode(ruleNode);
    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _showEditRuleDialog(AutomationRuleRecord rule) async {
    final result = await showDialog<_AutomationRuleFormResult>(
      context: context,
      builder: (context) => _NewAutomationRuleDialog(initialRule: rule),
    );
    if (result == null) return;

    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final node = await repository.getNode(rule.nodeId);
    final day = widget.suggestions.day.dateOnly;
    if (node != null) {
      await repository.saveNode(
        updateAutomationRuleNode(
          node: node,
          label: result.label,
          templateId: result.templateId,
          rule: result.rule,
          enabled: result.enabled,
        ),
      );
    }
    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _toggleRule(AutomationRuleRecord rule) async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final node = await repository.getNode(rule.nodeId);
    final day = widget.suggestions.day.dateOnly;
    if (node != null) {
      await repository.saveNode(
        updateAutomationRuleNode(
          node: node,
          label: rule.label,
          templateId: rule.templateId,
          rule: rule.rule,
          enabled: !rule.enabled,
        ),
      );
    }
    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteRule(AutomationRuleRecord rule) async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final day = widget.suggestions.day.dateOnly;
    await repository.deleteNode(rule.nodeId);
    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  bool _hasAutomationPreset(AutomationRulePreset preset) {
    return _automationRules.any(
      (rule) =>
          rule.id == preset.id ||
          (rule.label == preset.label && rule.templateId == preset.templateId),
    );
  }

  Future<void> _installPresetRule(AutomationRulePreset preset) async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final day = widget.suggestions.day.dateOnly;
    final now = DateTime.now();
    await repository.saveNode(
      createAutomationRuleNodeFromPreset(
        id: preset.id,
        preset: preset,
        day: day,
        now: now,
      ),
    );
    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _applySelected() async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final selectedRoutines = await _selectedRoutines(repository);
    final day = widget.suggestions.day.dateOnly;

    await applyRecurringRoutines(
      repository: repository,
      day: day,
      routines: selectedRoutines,
    );
    await _recordAutomationEvent(
      repository: repository,
      type: AutomationEventType.applyRoutines,
      title: 'Applied automation routines',
      message:
          'Applied ${_joinRoutineLabels(selectedRoutines.map((routine) => routine.label))}.',
      day: day,
      affectedLabels: [for (final routine in selectedRoutines) routine.label],
    );

    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _skipSelected() async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final selectedRoutines = await _selectedRoutines(repository);
    final day = widget.suggestions.day.dateOnly;

    await skipRecurringRoutines(
      repository: repository,
      day: day,
      routines: selectedRoutines,
    );
    await _recordAutomationEvent(
      repository: repository,
      type: AutomationEventType.skipRoutines,
      title: 'Skipped automation routines',
      message:
          'Skipped ${_joinRoutineLabels(selectedRoutines.map((routine) => routine.label))} for ${dayKey(day)}.',
      day: day,
      affectedLabels: [for (final routine in selectedRoutines) routine.label],
    );

    _invalidateAutomationState(day);

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _snoozeSelected() async {
    setState(() => _isApplying = true);
    final repository = ref.read(mindmapRepositoryProvider);
    final selectedRoutines = await _selectedRoutines(repository);
    final day = widget.suggestions.day.dateOnly;

    await snoozeRecurringRoutines(
      repository: repository,
      day: day,
      targetDay: day.addDays(1),
      routines: selectedRoutines,
    );
    await _recordAutomationEvent(
      repository: repository,
      type: AutomationEventType.snoozeRoutines,
      title: 'Snoozed automation routines',
      message:
          'Snoozed ${_joinRoutineLabels(selectedRoutines.map((routine) => routine.label))} to ${dayKey(day.addDays(1))}.',
      day: day,
      affectedLabels: [for (final routine in selectedRoutines) routine.label],
    );

    _invalidateAutomationState(day, extraDay: day.addDays(1));

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<List<RecurringNodeRoutine>> _selectedRoutines(
    MindmapRepository repository,
  ) async {
    final routines = await loadRecurringRoutines(repository: repository);
    return [
      for (final routine in routines)
        if (_selectedRoutineIds.contains(routine.id)) routine,
    ];
  }

  Future<void> _recordAutomationEvent({
    required MindmapRepository repository,
    required AutomationEventType type,
    required String title,
    required String message,
    required DateTime day,
    required List<String> affectedLabels,
  }) async {
    if (affectedLabels.isEmpty) return;
    final now = DateTime.now();
    await repository.saveNode(
      createAutomationEventNode(
        id: '${type.name}-${now.microsecondsSinceEpoch}',
        type: type,
        title: title,
        message: message,
        day: day,
        occurredAt: now,
        affectedLabels: affectedLabels,
      ),
    );
  }

  void _invalidateAutomationState(DateTime day, {DateTime? extraDay}) {
    invalidateMindmapState(ref, day: day, extraDay: extraDay);
  }
}

String _automationRuleIdFromLabel(String label, DateTime now) {
  final slug = label
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final normalizedSlug = slug.isEmpty ? 'rule' : slug;
  return 'custom-$normalizedSlug-${now.microsecondsSinceEpoch}';
}

final class _AutomationRuleFormResult {
  const _AutomationRuleFormResult({
    required this.label,
    required this.templateId,
    required this.rule,
    required this.enabled,
  });

  final String label;
  final String templateId;
  final RecurringRule rule;
  final bool enabled;
}

class _NewAutomationRuleDialog extends StatefulWidget {
  const _NewAutomationRuleDialog({this.initialRule});

  final AutomationRuleRecord? initialRule;

  @override
  State<_NewAutomationRuleDialog> createState() {
    return _NewAutomationRuleDialogState();
  }
}

class _NewAutomationRuleDialogState extends State<_NewAutomationRuleDialog> {
  late final TextEditingController _labelController;
  late String _templateId;
  RecurringFrequency _frequency = RecurringFrequency.daily;
  int _weekday = DateTime.monday;
  int _dayOfMonth = 1;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final initialRule = widget.initialRule;
    _labelController = TextEditingController(text: initialRule?.label ?? '');
    _labelController.addListener(() => setState(() {}));
    _templateId = initialRule?.templateId ?? _initialTemplateId();
    if (initialRule != null) {
      _frequency = initialRule.rule.frequency;
      _weekday = initialRule.rule.weekday ?? DateTime.monday;
      _dayOfMonth = initialRule.rule.dayOfMonth ?? 1;
      _enabled = initialRule.enabled;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('automation-rule-dialog'),
      title: Text(
        widget.initialRule == null ? 'New automation rule' : 'Edit rule',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Presets',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in defaultAutomationRulePresets)
                      ActionChip(
                        key: ValueKey('automation-rule-preset-${preset.id}'),
                        avatar: const Icon(
                          Icons.auto_awesome_outlined,
                          size: 16,
                        ),
                        label: Text(preset.label),
                        onPressed: () => _applyPreset(preset),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('automation-rule-label-field'),
                controller: _labelController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Rule name',
                  hintText: 'Daily research',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('automation-rule-template-field'),
                initialValue: _templateId,
                decoration: const InputDecoration(labelText: 'Template'),
                items: [
                  for (final template in defaultNodeTemplates)
                    DropdownMenuItem(
                      value: template.id,
                      child: Text(template.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _templateId = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RecurringFrequency>(
                key: const ValueKey('automation-rule-frequency-field'),
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Cadence'),
                items: const [
                  DropdownMenuItem(
                    value: RecurringFrequency.daily,
                    child: Text('Daily'),
                  ),
                  DropdownMenuItem(
                    value: RecurringFrequency.weekly,
                    child: Text('Weekly'),
                  ),
                  DropdownMenuItem(
                    value: RecurringFrequency.monthly,
                    child: Text('Monthly'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _frequency = value);
                },
              ),
              if (_frequency == RecurringFrequency.weekly) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('automation-rule-weekday-field'),
                  initialValue: _weekday,
                  decoration: const InputDecoration(labelText: 'Weekday'),
                  items: const [
                    DropdownMenuItem(
                      value: DateTime.monday,
                      child: Text('Monday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.tuesday,
                      child: Text('Tuesday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.wednesday,
                      child: Text('Wednesday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.thursday,
                      child: Text('Thursday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.friday,
                      child: Text('Friday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.saturday,
                      child: Text('Saturday'),
                    ),
                    DropdownMenuItem(
                      value: DateTime.sunday,
                      child: Text('Sunday'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _weekday = value);
                  },
                ),
              ],
              if (_frequency == RecurringFrequency.monthly) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('automation-rule-month-day-field'),
                  initialValue: _dayOfMonth,
                  decoration: const InputDecoration(labelText: 'Month day'),
                  items: [
                    for (var day = 1; day <= 31; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _dayOfMonth = value);
                  },
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('automation-rule-save-button'),
          onPressed: () {
            final label = _labelController.text.trim();
            if (label.isEmpty) return;
            _save(label);
          },
          icon: const Icon(Icons.save_outlined),
          label: Text(widget.initialRule == null ? 'Create rule' : 'Save rule'),
        ),
      ],
    );
  }

  void _save(String label) {
    Navigator.of(context).pop(
      _AutomationRuleFormResult(
        label: label,
        templateId: _templateId,
        rule: _buildRule(),
        enabled: _enabled,
      ),
    );
  }

  void _applyPreset(AutomationRulePreset preset) {
    _labelController.text = preset.label;
    setState(() {
      _templateId = preset.templateId;
      _frequency = preset.rule.frequency;
      _weekday = preset.rule.weekday ?? DateTime.monday;
      _dayOfMonth = preset.rule.dayOfMonth ?? 1;
      _enabled = true;
    });
  }

  RecurringRule _buildRule() {
    return switch (_frequency) {
      RecurringFrequency.daily => RecurringRule.daily(),
      RecurringFrequency.weekly => RecurringRule.weekly(weekday: _weekday),
      RecurringFrequency.monthly => RecurringRule.monthly(
        dayOfMonth: _dayOfMonth,
      ),
    };
  }
}

String _initialTemplateId() {
  for (final template in defaultNodeTemplates) {
    if (template.id == 'research-note') return template.id;
  }
  return defaultNodeTemplates.first.id;
}

class _AutomationRuleManageRow extends StatelessWidget {
  const _AutomationRuleManageRow({
    required this.rule,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final AutomationRuleRecord rule;
  final VoidCallback? onEdit;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cadence = _ruleCadenceLabel(rule.rule);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            rule.enabled ? Icons.auto_awesome_outlined : Icons.pause_outlined,
            size: 18,
            color: rule.enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '$cadence / ${rule.enabled ? 'Enabled' : 'Paused'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('automation-rule-edit-${rule.id}'),
            tooltip: 'Edit rule',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey('automation-rule-toggle-${rule.id}'),
            tooltip: rule.enabled ? 'Pause rule' : 'Enable rule',
            onPressed: onToggle,
            icon: Icon(
              rule.enabled ? Icons.pause_circle_outline : Icons.play_circle,
            ),
          ),
          IconButton(
            key: ValueKey('automation-rule-delete-${rule.id}'),
            tooltip: 'Delete rule',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

String _ruleCadenceLabel(RecurringRule rule) {
  return switch (rule.frequency) {
    RecurringFrequency.daily => 'Daily',
    RecurringFrequency.weekly => 'Weekly',
    RecurringFrequency.monthly => 'Monthly',
  };
}

class _AutomationScheduleRow extends StatelessWidget {
  const _AutomationScheduleRow({required this.item});

  final AutomationScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 160,
      height: 62,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.32,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_repeat_outlined,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.cadenceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(item.statusLabel, style: theme.textTheme.bodySmall),
                ],
              ),
              Text(
                item.nextDueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutomationCenterChip extends StatelessWidget {
  const _AutomationCenterChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _AutomationSuggestionRow extends StatelessWidget {
  const _AutomationSuggestionRow({required this.item});

  final AutomationSuggestion item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.playlist_add_check_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(item.message, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => goToDay(context, item.day),
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text(item.actionLabel),
        ),
      ],
    );
  }
}

class _WorkspaceFocusPanel extends StatelessWidget {
  const _WorkspaceFocusPanel({
    required this.contexts,
    required this.today,
    required this.onProjectChanged,
    required this.onAreaChanged,
  });

  final List<WorkspaceContext> contexts;
  final DateTime today;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusContexts = _workspaceFocusContexts(contexts, today);
    if (focusContexts.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      key: const ValueKey('insights-workspace-focus-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspaces_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Workspace focus', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < focusContexts.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _WorkspaceFocusRow(
                workspaceContext: focusContexts[index],
                today: today,
                onFocus: () {
                  switch (focusContexts[index].type) {
                    case WorkspaceContextType.project:
                      onProjectChanged(focusContexts[index].name);
                    case WorkspaceContextType.area:
                      onAreaChanged(focusContexts[index].name);
                    case WorkspaceContextType.daily:
                      break;
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceFocusRow extends StatelessWidget {
  const _WorkspaceFocusRow({
    required this.workspaceContext,
    required this.today,
    required this.onFocus,
  });

  final WorkspaceContext workspaceContext;
  final DateTime today;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdueCount = workspaceContext.overdueCount(today);
    final color = overdueCount > 0
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Row(
      children: [
        Icon(_workspaceIcon(workspaceContext.type), size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${workspaceContext.type.label} ${workspaceContext.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                workspaceContext.healthLabel(today),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onFocus,
          icon: const Icon(Icons.filter_alt_outlined, size: 16),
          label: const Text('Focus'),
        ),
      ],
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.attention});

  final LifeOsAttention attention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey('insights-attention-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notification_important_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Needs attention',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                if (attention.criticalCount > 0)
                  _MetricPill(
                    icon: Icons.priority_high,
                    label: '${attention.criticalCount} critical',
                  ),
                if (attention.warningCount > 0)
                  _MetricPill(
                    icon: Icons.warning_amber_outlined,
                    label: '${attention.warningCount} warning',
                  ),
                if (attention.infoCount > 0)
                  _MetricPill(
                    icon: Icons.info_outline,
                    label: '${attention.infoCount} info',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < attention.signals.length; index++) ...[
              if (index > 0) const Divider(height: 18),
              _AttentionRow(signal: attention.signals[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.signal});

  final LifeOsAttentionSignal signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _attentionColor(theme, signal.severity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_attentionIcon(signal.type), size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                signal.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(signal.message, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () =>
              goToDay(context, signal.day, highlightNodeId: signal.nodeId),
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text(signal.actionLabel),
        ),
      ],
    );
  }
}

class _SmartViewsBand extends StatelessWidget {
  const _SmartViewsBand({
    required this.views,
    required this.selectedView,
    required this.onChanged,
  });

  final List<SmartNodeView> views;
  final SmartNodeViewType? selectedView;
  final ValueChanged<SmartNodeViewType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < views.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            FilterChip(
              key: ValueKey('insights-smart-${views[index].type.name}'),
              label: Text(views[index].countLabel),
              selected: selectedView == views[index].type,
              onSelected: (_) => onChanged(views[index].type),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightShortcutHintBar extends StatelessWidget {
  const _InsightShortcutHintBar();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Insights keyboard shortcuts',
      child: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ShortcutHint(label: 'T', action: 'Today'),
            SizedBox(width: 6),
            _ShortcutHint(label: 'W', action: 'Week'),
            SizedBox(width: 6),
            _ShortcutHint(label: 'M', action: 'Month'),
            SizedBox(width: 6),
            _ShortcutHint(label: '/', action: 'Search'),
            SizedBox(width: 6),
            _ShortcutHint(label: 'E', action: 'Export'),
            SizedBox(width: 6),
            _ShortcutHint(label: 'R', action: 'Refresh'),
          ],
        ),
      ),
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.label, required this.action});

  final String label;
  final String action;

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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Text(action, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _InsightRangeFilterBar extends StatelessWidget {
  const _InsightRangeFilterBar({
    required this.rangePreset,
    required this.typeFilter,
    required this.tagFilter,
    required this.nodes,
    required this.onRangePresetChanged,
    required this.onTypeChanged,
    required this.onTagChanged,
    required this.onClear,
  });

  final insight_filters.InsightRangePreset rangePreset;
  final NodeType? typeFilter;
  final String? tagFilter;
  final List<MindmapNode> nodes;
  final ValueChanged<insight_filters.InsightRangePreset> onRangePresetChanged;
  final ValueChanged<NodeType> onTypeChanged;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tags = <String>{
      for (final node in nodes)
        for (final tag in node.tags)
          if (tag.trim().isNotEmpty) tag,
    }.toList()..sort();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final preset in insight_filters.InsightRangePreset.values)
          ChoiceChip(
            label: Text(_rangePresetLabel(preset)),
            selected: rangePreset == preset,
            onSelected: (_) => onRangePresetChanged(preset),
          ),
        const SizedBox(width: 4),
        for (final type in NodeType.values.take(8))
          FilterChip(
            label: Text(type.label),
            selected: typeFilter == type,
            onSelected: (_) => onTypeChanged(type),
          ),
        for (final tag in tags.take(6))
          FilterChip(
            label: Text('Tag: #$tag'),
            selected: tagFilter == tag,
            onSelected: (_) => onTagChanged(tag),
          ),
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.clear_all),
          label: const Text('Clear filters'),
        ),
      ],
    );
  }
}

String _rangePresetLabel(insight_filters.InsightRangePreset preset) {
  switch (preset) {
    case insight_filters.InsightRangePreset.today:
      return 'Today';
    case insight_filters.InsightRangePreset.sevenDays:
      return '7 days';
    case insight_filters.InsightRangePreset.thirtyDays:
      return '30 days';
    case insight_filters.InsightRangePreset.thisMonth:
      return 'This month';
  }
}

class _MetricRail extends StatelessWidget {
  const _MetricRail({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _WorkspaceContextsBand extends StatelessWidget {
  const _WorkspaceContextsBand({
    required this.contexts,
    required this.selectedProject,
    required this.selectedArea,
    required this.onProjectChanged,
    required this.onAreaChanged,
  });

  final List<WorkspaceContext> contexts;
  final String? selectedProject;
  final String? selectedArea;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;

  @override
  Widget build(BuildContext context) {
    if (contexts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final workspaceContext in contexts)
          if (workspaceContext.type != WorkspaceContextType.daily)
            FilterChip(
              key: ValueKey(
                'insights-${workspaceContext.type.name}-${workspaceContextKey(workspaceContext.name)}',
              ),
              label: Text(workspaceContext.countLabel),
              selected: switch (workspaceContext.type) {
                WorkspaceContextType.project =>
                  selectedProject == workspaceContext.name,
                WorkspaceContextType.area =>
                  selectedArea == workspaceContext.name,
                WorkspaceContextType.daily => false,
              },
              onSelected: (_) {
                switch (workspaceContext.type) {
                  case WorkspaceContextType.project:
                    onProjectChanged(workspaceContext.name);
                    break;
                  case WorkspaceContextType.area:
                    onAreaChanged(workspaceContext.name);
                    break;
                  case WorkspaceContextType.daily:
                    break;
                }
              },
            ),
      ],
    );
  }
}

class _FilterBand extends StatelessWidget {
  const _FilterBand({
    required this.statusFilter,
    required this.priorityFilter,
    required this.onStatusChanged,
    required this.onPriorityChanged,
  });

  final NodeStatus? statusFilter;
  final NodePriority? priorityFilter;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.filter_list, size: 18, color: theme.colorScheme.primary),
            for (final priority in NodePriority.values)
              if (priority != NodePriority.none)
                FilterChip(
                  key: ValueKey('insights-priority-${priority.name}'),
                  label: Text('Priority ${priority.label}'),
                  selected: priorityFilter == priority,
                  onSelected: (_) => onPriorityChanged(priority),
                ),
            for (final status in NodeStatus.values)
              FilterChip(
                key: ValueKey('insights-status-${status.name}'),
                label: Text('Status ${status.label}'),
                selected: statusFilter == status,
                onSelected: (_) => onStatusChanged(status),
              ),
          ],
        ),
      ),
    );
  }
}

class _KnowledgeGraphPanel extends StatelessWidget {
  const _KnowledgeGraphPanel({required this.graph});

  final NodeGraph graph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hubs = _topGraphHubs(graph);
    final crossDayCount = graph.edges.where((edge) => edge.isCrossDay).length;

    return DecoratedBox(
      key: const ValueKey('insights-knowledge-graph-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Knowledge graph', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.hub_outlined,
                  label: '${graph.nodes.length} graph nodes',
                ),
                _MetricPill(
                  icon: Icons.link_outlined,
                  label: '${graph.edgeCount} links',
                ),
                _MetricPill(
                  icon: Icons.calendar_month_outlined,
                  label: '$crossDayCount cross-day',
                ),
              ],
            ),
            if (hubs.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (var index = 0; index < hubs.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _GraphHubRow(node: hubs[index]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _GraphHubRow extends StatelessWidget {
  const _GraphHubRow({required this.node});

  final NodeGraphNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          _nodeIcon(node.node.type),
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            node.node.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _countLabel(node.totalDegree, 'connection'),
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Insight metric: $label',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightNodeTile extends StatelessWidget {
  const _InsightNodeTile({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _nodeIcon(node.type),
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${node.type.label} - ${dayKey(node.day)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (node.body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      node.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (_metadataLabelsFor(node).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _MetadataPills(labels: _metadataLabelsFor(node)),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open day',
              onPressed: () =>
                  goToDay(context, node.day, highlightNodeId: node.id),
              icon: const Icon(Icons.open_in_new),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataPills extends StatelessWidget {
  const _MetadataPills({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels)
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.7,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.65),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_outlined,
                color: theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: 10),
              Text('No matching nodes', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Try clearing search, status, priority, workspace, or smart view filters.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _matchesQuery(MindmapNode node, String query) {
  final values = [
    node.title,
    node.body,
    node.type.label,
    node.status.label,
    node.priority.label,
    node.project,
    node.area,
    dayKey(node.day),
    for (final tag in node.tags) tag,
  ];

  return values.any((value) => value.toLowerCase().contains(query));
}

int _compareInsightNodes(MindmapNode a, MindmapNode b) {
  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
  final aDueDate = a.dueDate;
  final bDueDate = b.dueDate;
  if (aDueDate != null && bDueDate != null) {
    final dueDate = aDueDate.compareTo(bDueDate);
    if (dueDate != 0) return dueDate;
  } else if (aDueDate != null) {
    return -1;
  } else if (bDueDate != null) {
    return 1;
  }

  final updated = b.updatedAt.compareTo(a.updatedAt);
  if (updated != 0) return updated;
  return a.title.compareTo(b.title);
}

List<NodeGraphNode> _topGraphHubs(NodeGraph graph) {
  final hubs = [
    for (final node in graph.nodes)
      if (node.totalDegree > 0) node,
  ];
  hubs.sort((a, b) {
    final degree = b.totalDegree.compareTo(a.totalDegree);
    if (degree != 0) return degree;
    return a.node.title.compareTo(b.node.title);
  });
  return hubs.take(3).toList(growable: false);
}

List<String> _metadataLabelsFor(MindmapNode node) {
  return [
    if (node.priority != NodePriority.none) node.priority.label,
    if (node.status != NodeStatus.open) node.status.label,
    if (node.project.isNotEmpty) 'Project: ${node.project}',
    if (node.area.isNotEmpty) 'Area: ${node.area}',
    for (final tag in node.tags.take(3)) '#$tag',
    if (node.dueDate != null) _dueDateLabel(node.dueDate!),
    if (node.progress > 0) '${(node.progress * 100).round()}%',
    if (node.checklist.isNotEmpty)
      '${node.completedChecklistCount}/${node.checklist.length}',
    if (node.isPinned) 'Pinned',
    if (node.isArchived) 'Archived',
  ];
}

String _dueDateLabel(DateTime dueDate) {
  final normalizedDueDate = dueDate.dateOnly;
  final today = DateTime.now().dateOnly;
  if (normalizedDueDate.isSameDay(today)) return 'Due Today';
  return 'Due ${dayKey(normalizedDueDate)}';
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
  NodeType.event => Icons.event_outlined,
  NodeType.decision => Icons.rule_outlined,
  NodeType.resource => Icons.inventory_2_outlined,
  NodeType.idea => Icons.lightbulb_outline,
  NodeType.question => Icons.help_outline,
  NodeType.contact => Icons.person_outline,
  NodeType.metric => Icons.query_stats_outlined,
  NodeType.expense => Icons.payments_outlined,
  NodeType.bookmark => Icons.bookmark_border,
  NodeType.routine => Icons.repeat_on_outlined,
  NodeType.empty => Icons.crop_square_outlined,
};

IconData _attentionIcon(LifeOsAttentionType type) => switch (type) {
  LifeOsAttentionType.overdueTask => Icons.assignment_late_outlined,
  LifeOsAttentionType.habitDue => Icons.repeat_on_outlined,
  LifeOsAttentionType.stuckGoal => Icons.flag_outlined,
  LifeOsAttentionType.journalIncomplete => Icons.edit_note_outlined,
};

IconData _workspaceIcon(WorkspaceContextType type) => switch (type) {
  WorkspaceContextType.project => Icons.folder_special_outlined,
  WorkspaceContextType.area => Icons.category_outlined,
  WorkspaceContextType.daily => Icons.today_outlined,
};

List<WorkspaceContext> _workspaceFocusContexts(
  List<WorkspaceContext> contexts,
  DateTime today,
) {
  final focusContexts = [
    for (final context in contexts)
      if (context.activeNodeCount > 0 &&
          context.type != WorkspaceContextType.daily)
        context,
  ];
  focusContexts.sort((a, b) {
    final overdue = b.overdueCount(today).compareTo(a.overdueCount(today));
    if (overdue != 0) return overdue;
    final highPriority = b.highPriorityCount.compareTo(a.highPriorityCount);
    if (highPriority != 0) return highPriority;
    final activeCount = b.activeNodeCount.compareTo(a.activeNodeCount);
    if (activeCount != 0) return activeCount;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return focusContexts.take(4).toList(growable: false);
}

Color _attentionColor(ThemeData theme, LifeOsAttentionSeverity severity) {
  return switch (severity) {
    LifeOsAttentionSeverity.critical => theme.colorScheme.error,
    LifeOsAttentionSeverity.warning => theme.colorScheme.tertiary,
    LifeOsAttentionSeverity.info => theme.colorScheme.primary,
  };
}

String _percentLabel(double value) {
  return '${(value * 100).round()}%';
}

String _countLabel(int count, String singular) {
  return '$count $singular${count == 1 ? '' : 's'}';
}

String _joinAutomationLabels(List<String> labels) {
  if (labels.isEmpty) return 'automation rules';
  if (labels.length == 1) return labels.single;
  return labels.join(', ');
}

String _joinRoutineLabels(Iterable<String> labels) {
  final normalizedLabels = [
    for (final label in labels)
      if (label.trim().isNotEmpty) label.trim(),
  ];
  return _joinAutomationLabels(normalizedLabels);
}

class AnimatedCounter extends StatefulWidget {
  const AnimatedCounter({
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.style,
    super.key,
  });

  final num value;
  final String prefix;
  final String suffix;
  final TextStyle? style;

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: widget.value.toDouble())
        .animate(
          CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
        );
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation =
          Tween<double>(
            begin: _animation.value,
            end: widget.value.toDouble(),
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn),
          );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final val = _animation.value;
        final isInt = widget.value is int;
        final displayText = isInt
            ? val.round().toString()
            : val.toStringAsFixed(1);
        return Text(
          '${widget.prefix}$displayText${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

class _ExportDataDialog extends StatefulWidget {
  const _ExportDataDialog({required this.nodes, required this.markdownReport});

  final List<MindmapNode> nodes;
  final String markdownReport;

  @override
  State<_ExportDataDialog> createState() => _ExportDataDialogState();
}

enum _ExportFormat { markdown, json, csv }

class _ExportDataDialogState extends State<_ExportDataDialog> {
  _ExportFormat _format = _ExportFormat.markdown;
  late String _data;

  @override
  void initState() {
    super.initState();
    _generateData();
  }

  void _generateData() {
    if (_format == _ExportFormat.markdown) {
      _data = widget.markdownReport;
    } else if (_format == _ExportFormat.json) {
      final list = widget.nodes
          .map(
            (n) => {
              'id': n.id,
              'type': n.type.name,
              'title': n.title,
              'body': n.body,
              'day': n.day.toIso8601String(),
              'isDone': n.isDone,
              'status': n.status.name,
              'priority': n.priority.name,
              'project': n.project,
              'area': n.area,
              'tags': n.tags,
              'dueDate': n.dueDate?.toIso8601String(),
              'progress': n.progress,
              'isPinned': n.isPinned,
              'isArchived': n.isArchived,
              'checklist': n.checklist.map((item) => item.toJson()).toList(),
              'relatedNodeIds': n.relatedNodeIds,
              'data': n.data,
            },
          )
          .toList();
      _data = const JsonEncoder.withIndent('  ').convert(list);
    } else {
      final buffer = StringBuffer();
      buffer.writeln(
        'ID,Type,Title,Day,Done,Status,Priority,Project,Area,Tags',
      );
      for (final n in widget.nodes) {
        final titleEscaped = n.title.replaceAll('"', '""');
        final tagsJoined = n.tags.join(';');
        buffer.writeln(
          '${n.id},${n.type.name},"$titleEscaped",${dayKey(n.day)},${n.isDone},${n.status.name},${n.priority.name},"${n.project}","${n.area}","$tagsJoined"',
        );
      }
      _data = buffer.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Export Insights Report'),
      content: SizedBox(
        width: 600,
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Markdown Report'),
                  selected: _format == _ExportFormat.markdown,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _format = _ExportFormat.markdown;
                        _generateData();
                      });
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('JSON Format'),
                  selected: _format == _ExportFormat.json,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _format = _ExportFormat.json;
                        _generateData();
                      });
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('CSV Format'),
                  selected: _format == _ExportFormat.csv,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _format = _ExportFormat.csv;
                        _generateData();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.all(8),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _data,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _data));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied export to clipboard!')),
              );
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy to Clipboard'),
        ),
      ],
    );
  }
}

class _InsightDrillDownPanel extends StatelessWidget {
  const _InsightDrillDownPanel({
    required this.nodeIndex,
    required this.contextHealth,
    required this.habitSummary,
    required this.reviewSummary,
    required this.goalSummary,
    required this.onProjectChanged,
    required this.onAreaChanged,
  });

  final insight_cache.InsightNodeIndex nodeIndex;
  final health.ContextHealthSummary contextHealth;
  final habits.HabitInsightSummary habitSummary;
  final reviews.ReviewInsightSummary reviewSummary;
  final goals.GoalInsightSummary goalSummary;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = nodeIndex.overdueTaskNodes.take(8).toList(growable: false);
    final highPriority = nodeIndex.highPriorityOpenTaskNodes
        .take(8)
        .toList(growable: false);
    final contextItems = contextHealth.items.take(8).toList(growable: false);
    final habitsAtRisk =
        [
              if (habitSummary.streakAtRisk != null) habitSummary.streakAtRisk!,
              ...habitSummary.streaks.where((streak) => streak.isAtRisk),
            ]
            .fold<Map<String, habits.HabitStreak>>(
              <String, habits.HabitStreak>{},
              (values, streak) =>
                  values..putIfAbsent(streak.nodeId, () => streak),
            )
            .values
            .toList(growable: false);
    final reviewGaps = reviewSummary.reviewGaps.take(5).toList(growable: false);
    final goalItems =
        [...goalSummary.stalledGoals, ...goalSummary.needsNextActionGoals]
            .fold<Map<String, goals.GoalProgressItem>>(
              <String, goals.GoalProgressItem>{},
              (values, item) => values..putIfAbsent(item.node.id, () => item),
            )
            .values
            .take(8)
            .toList(growable: false);

    return DecoratedBox(
      key: const ValueKey('insights-drill-down-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.unfold_more, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Drill-down panels', style: theme.textTheme.titleSmall),
                ],
              ),
            ),
            _DrillDownTile(
              title: 'Overdue tasks detail',
              count: overdue.length,
              icon: Icons.warning_amber_outlined,
              children: _nodeRows(context, overdue, empty: 'No overdue tasks.'),
            ),
            _DrillDownTile(
              title: 'High-priority tasks detail',
              count: highPriority.length,
              icon: Icons.priority_high_outlined,
              children: _nodeRows(
                context,
                highPriority,
                empty: 'No high-priority open tasks.',
              ),
            ),
            _DrillDownTile(
              title: 'Project / area detail',
              count: contextItems.length,
              icon: Icons.workspaces_outline,
              children: contextItems.isEmpty
                  ? const [
                      _EmptyDrillDownRow(
                        message: 'No project or area activity.',
                      ),
                    ]
                  : [
                      for (final item in contextItems)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            item.isProject
                                ? Icons.folder_outlined
                                : Icons.public_outlined,
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            '${item.openTasks} open · ${item.completedTasks} done · ${item.overdueTasks} overdue',
                          ),
                          trailing: Text(_contextStatusLabel(item.status)),
                          onTap: () => item.isProject
                              ? onProjectChanged(item.name)
                              : onAreaChanged(item.name),
                        ),
                    ],
            ),
            _DrillDownTile(
              title: 'Habit detail',
              count: habitSummary.missedHabits.length + habitsAtRisk.length,
              icon: Icons.repeat_on_outlined,
              children: [
                if (habitSummary.missedHabits.isEmpty && habitsAtRisk.isEmpty)
                  const _EmptyDrillDownRow(message: 'No habit issues.'),
                for (final node in habitSummary.missedHabits.take(6))
                  _NodeDrillDownRow(
                    node: node,
                    subtitle: 'Missed in selected range',
                  ),
                for (final streak in habitsAtRisk.take(6))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.local_fire_department_outlined),
                    title: Text(streak.title),
                    subtitle: Text(
                      'Current ${streak.currentStreak} · Longest ${streak.longestStreak}',
                    ),
                  ),
              ],
            ),
            _DrillDownTile(
              title: 'Review detail',
              count: reviewGaps.length,
              icon: Icons.rate_review_outlined,
              children: reviewGaps.isEmpty
                  ? const [_EmptyDrillDownRow(message: 'No review gaps.')]
                  : [
                      for (final gap in reviewGaps)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.event_busy_outlined),
                          title: Text('${gap.dayCount} day gap'),
                          subtitle: Text(
                            '${dayKey(gap.start)} → ${dayKey(gap.end)}',
                          ),
                        ),
                    ],
            ),
            _DrillDownTile(
              title: 'Goal detail',
              count: goalItems.length,
              icon: Icons.track_changes_outlined,
              children: goalItems.isEmpty
                  ? const [_EmptyDrillDownRow(message: 'No goal issues.')]
                  : [
                      for (final item in goalItems)
                        _NodeDrillDownRow(
                          node: item.node,
                          subtitle:
                              '${(item.progress * 100).round()}% · ${item.isStalled ? 'stalled' : 'needs next action'}',
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _nodeRows(
    BuildContext context,
    List<MindmapNode> values, {
    required String empty,
  }) {
    if (values.isEmpty) return [_EmptyDrillDownRow(message: empty)];
    return [
      for (final node in values)
        _NodeDrillDownRow(node: node, subtitle: _nodeSubtitle(node)),
    ];
  }
}

class _DrillDownTile extends StatelessWidget {
  const _DrillDownTile({
    required this.title,
    required this.count,
    required this.icon,
    required this.children,
  });

  final String title;
  final int count;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      leading: Icon(icon),
      title: Text(title),
      trailing: Chip(
        label: Text('$count'),
        visualDensity: VisualDensity.compact,
      ),
      children: children,
    );
  }
}

class _NodeDrillDownRow extends StatelessWidget {
  const _NodeDrillDownRow({required this.node, required this.subtitle});

  final MindmapNode node;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(_nodeIcon(node.type)),
      title: Text(node.title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () => context.go(
        '/calendar/${dayKey(node.day)}/node/${Uri.encodeComponent(node.id)}',
      ),
    );
  }
}

class _EmptyDrillDownRow extends StatelessWidget {
  const _EmptyDrillDownRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline),
      title: Text(message),
    );
  }
}

String _nodeSubtitle(MindmapNode node) {
  final parts = <String>[
    node.status.label,
    node.priority.label,
    dayKey(node.day),
    if (node.dueDate != null) 'due ${dayKey(node.dueDate!)}',
    if (node.project.isNotEmpty) node.project,
    if (node.area.isNotEmpty) node.area,
    ...node.tags.map((tag) => '#$tag'),
  ];
  return parts.join(' · ');
}

String _contextStatusLabel(health.ContextHealthStatus status) {
  switch (status) {
    case health.ContextHealthStatus.good:
      return 'good';
    case health.ContextHealthStatus.watch:
      return 'watch';
    case health.ContextHealthStatus.stale:
      return 'stale';
    case health.ContextHealthStatus.critical:
      return 'critical';
  }
}

class _FocusTimerAnalyticsPanel extends StatelessWidget {
  const _FocusTimerAnalyticsPanel({
    required this.summary,
    required this.focusSummary,
    required this.today,
  });

  final InsightsSummary summary;
  final focus.FocusInsightSummary focusSummary;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedToday = today.dateOnly;

    final days = [
      for (var offset = 6; offset >= 0; offset--)
        normalizedToday.subtract(Duration(days: offset)),
    ];

    return DecoratedBox(
      key: const ValueKey('insights-focus-timer-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_empty, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Focus and time investment',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (focusSummary.hasLowFocusWarning)
                  const _TrendChip(
                    label: 'Low focus warning',
                    direction: trends.InsightTrendDirection.volatile,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.timer_outlined,
                  label: '${focusSummary.totalMinutes} focus minutes',
                ),
                if (focusSummary.bestFocusDay != null)
                  _MetricPill(
                    icon: Icons.bolt_outlined,
                    label:
                        'Best ${DateFormat('E').format(focusSummary.bestFocusDay!)} ${focusSummary.bestFocusMinutes}m',
                  ),
                _MetricPill(
                  icon: Icons.alarm_on,
                  label:
                      '${summary.weeklyFocusSessionsCount} focus sessions this week',
                ),
                if (focusSummary.plannedOpenTasks > 0)
                  _MetricPill(
                    icon: Icons.task_alt_outlined,
                    label: '${focusSummary.plannedOpenTasks} planned open',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final day in days)
                  () {
                    final key = dayKey(day);
                    final bucket = focusSummary.minutesByDay.firstWhere(
                      (item) => item.label == key,
                      orElse: () => focus.FocusBucket(label: key, minutes: 0),
                    );
                    return _FocusDayPill(
                      day: day,
                      focusMinutes: bucket.minutes,
                    );
                  }(),
              ],
            ),
            if (focusSummary.minutesByProject.isNotEmpty ||
                focusSummary.minutesByArea.isNotEmpty ||
                focusSummary.minutesByTag.isNotEmpty) ...[
              const SizedBox(height: 12),
              _FocusContextBuckets(summary: focusSummary),
            ],
          ],
        ),
      ),
    );
  }
}

class _FocusContextBuckets extends StatelessWidget {
  const _FocusContextBuckets({required this.summary});

  final focus.FocusInsightSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.minutesByProject.isNotEmpty)
          _FocusBucketRail(
            title: 'Projects',
            buckets: summary.minutesByProject,
          ),
        if (summary.minutesByArea.isNotEmpty)
          _FocusBucketRail(title: 'Areas', buckets: summary.minutesByArea),
        if (summary.minutesByTag.isNotEmpty)
          _FocusBucketRail(title: 'Tags', buckets: summary.minutesByTag),
      ],
    );
  }
}

class _FocusBucketRail extends StatelessWidget {
  const _FocusBucketRail({required this.title, required this.buckets});

  final String title;
  final List<focus.FocusBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final bucket in buckets)
                _MetricPill(
                  icon: Icons.pie_chart_outline,
                  label: '${bucket.label} ${bucket.minutes}m',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FocusDayPill extends StatelessWidget {
  const _FocusDayPill({required this.day, required this.focusMinutes});

  final DateTime day;
  final int focusMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = focusMinutes > 0;

    final dateFormat = DateFormat('E');
    final formattedDay = dateFormat.format(day);
    final dateStr = dayKey(day).substring(5);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: 104,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$formattedDay ($dateStr)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                focusMinutes > 0 ? '$focusMinutes m' : '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.bold : null,
                  color: isActive ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
