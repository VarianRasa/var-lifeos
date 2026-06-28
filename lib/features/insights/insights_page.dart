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
import '../../shared/widgets/error_message.dart';
import '../../shared/widgets/search_field.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/recurring_routine_application.dart';
import '../mindmap/domain/automation_event.dart';
import '../mindmap/domain/automation_forecast.dart';
import '../mindmap/domain/automation_health.dart';
import '../mindmap/domain/automation_rule.dart';
import '../mindmap/domain/automation_suggestion.dart';
import '../mindmap/domain/life_os_summary.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/mindmap_repository.dart';
import '../mindmap/domain/node_graph.dart';
import '../mindmap/domain/node_template.dart';
import '../mindmap/domain/recurring_routine.dart';
import '../mindmap/domain/smart_node_view.dart';
import '../mindmap/domain/workspace_context.dart';
import 'domain/insights_summary.dart';

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  SmartNodeViewType? _smartViewFilter;
  String? _projectFilter;
  String? _areaFilter;
  NodeStatus? _statusFilter;
  NodePriority? _priorityFilter;

  bool _initializedFilters = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedFilters) {
      _initializedFilters = true;
      try {
        final state = GoRouterState.of(context);
        final project = state.uri.queryParameters['project'];
        final area = state.uri.queryParameters['area'];
        if (project != null) {
          _projectFilter = project;
        } else if (area != null) {
          _areaFilter = area;
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final smartViews = ref.watch(smartNodeViewsProvider);
    final automationSuggestions = ref.watch(automationSuggestionsProvider);
    final today = ref.watch(currentDateProvider);

    final isDesktop =
        MediaQuery.sizeOf(context).width >= LayoutConstants.desktopBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          SearchField(
            key: const ValueKey('insights-search-field'),
            controller: _searchController,
            hintText: 'Search nodes...',
            onChanged: (value) {
              setState(() => _query = value.trim().toLowerCase());
            },
          ),
          if (isDesktop)
            const SizedBox(width: 460)
          else
            const SizedBox(width: 16),
        ],
      ),
      body: smartViews.when(
        data: (value) {
          final filteredNodes = _filterNodes(value.nodesFor(_smartViewFilter));
          final workspaceContexts = WorkspaceContexts.fromNodes(value.allNodes);
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
          final weeklyPulse = InsightsWeeklyPulse.fromNodes(
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
          final automationEvents = automationEventsFromNodes(value.allNodes);
          final nodeGraph = NodeGraph.fromNodes(value.allNodes);
          return _InsightsBody(
            today: today,
            nodes: value.allNodes,
            filteredNodes: filteredNodes,
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
            weeklyPulse: weeklyPulse,
            nodeGraph: nodeGraph,
            searchQuery: _query,
            smartViewFilter: _smartViewFilter,
            projectFilter: _projectFilter,
            areaFilter: _areaFilter,
            statusFilter: _statusFilter,
            priorityFilter: _priorityFilter,
            onSmartViewChanged: (smartView) {
              setState(() {
                _smartViewFilter = _smartViewFilter == smartView
                    ? null
                    : smartView;
              });
            },
            onProjectChanged: (project) {
              setState(() {
                _projectFilter = _projectFilter == project ? null : project;
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
                _priorityFilter = _priorityFilter == priority ? null : priority;
              });
            },
            onReviewAutomations: _openAutomationCenter,
            onPauseAutomationIssue: _pauseAutomationHealthIssue,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorMessage(
          message: 'Unable to load insights',
          onRetry: () => ref.invalidate(smartNodeViewsProvider),
        ),
      ),
    );
  }

  List<MindmapNode> _filterNodes(List<MindmapNode> nodes) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = nodes.where((node) {
      if (_statusFilter != null && node.status != _statusFilter) return false;
      if (_priorityFilter != null && node.priority != _priorityFilter) {
        return false;
      }
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
    required this.weeklyPulse,
    required this.nodeGraph,
    required this.searchQuery,
    required this.smartViewFilter,
    required this.projectFilter,
    required this.areaFilter,
    required this.statusFilter,
    required this.priorityFilter,
    required this.onSmartViewChanged,
    required this.onProjectChanged,
    required this.onAreaChanged,
    required this.onStatusChanged,
    required this.onPriorityChanged,
    required this.onReviewAutomations,
    required this.onPauseAutomationIssue,
  });

  final DateTime today;
  final List<MindmapNode> nodes;
  final List<MindmapNode> filteredNodes;
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
  final InsightsWeeklyPulse weeklyPulse;
  final NodeGraph nodeGraph;
  final String searchQuery;
  final SmartNodeViewType? smartViewFilter;
  final String? projectFilter;
  final String? areaFilter;
  final NodeStatus? statusFilter;
  final NodePriority? priorityFilter;
  final ValueChanged<SmartNodeViewType> onSmartViewChanged;
  final ValueChanged<String> onProjectChanged;
  final ValueChanged<String> onAreaChanged;
  final ValueChanged<NodeStatus> onStatusChanged;
  final ValueChanged<NodePriority> onPriorityChanged;
  final ValueChanged<AutomationSuggestions> onReviewAutomations;
  final Future<void> Function(AutomationHealthIssue) onPauseAutomationIssue;

  @override
  Widget build(BuildContext context) {
    final spacing = MediaQuery.sizeOf(context).width < 720 ? 12.0 : 16.0;
    final showOverviewPanels =
        searchQuery.trim().isEmpty &&
        smartViewFilter == null &&
        projectFilter == null &&
        areaFilter == null &&
        statusFilter == null &&
        priorityFilter == null;
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

    return Padding(
      padding: EdgeInsets.all(spacing),
      child: ListView(
        children: [
          if (showOverviewPanels) ...[
            _buildWeeklyDigest(context),
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
                label: '${nodes.where((node) => node.isDone).length} done',
              ),
              _MetricPill(
                icon: Icons.flag_outlined,
                label:
                    '${nodes.where((node) => node.priority.index >= NodePriority.high.index).length} high priority',
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
            _FocusTimerAnalyticsPanel(summary: insightsSummary, today: today),
          ],
          SizedBox(height: spacing),
          _FilterBand(
            statusFilter: statusFilter,
            priorityFilter: priorityFilter,
            onStatusChanged: onStatusChanged,
            onPriorityChanged: onPriorityChanged,
          ),
          SizedBox(height: spacing),
          if (filteredNodes.isEmpty)
            const SizedBox(height: 260, child: _EmptyResults())
          else
            for (var index = 0; index < filteredNodes.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              _InsightNodeTile(node: filteredNodes[index]),
            ],
          if (showOverviewPanels) ...[
            SizedBox(height: spacing),
            _KnowledgeGraphPanel(graph: nodeGraph),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyDigest(BuildContext context) {
    final theme = Theme.of(context);

    final totalTasks = nodes.where((n) => n.type == NodeType.task).length;
    final doneTasks = nodes
        .where((n) => n.type == NodeType.task && n.isDone)
        .length;
    final completionPct = totalTasks > 0 ? (doneTasks / totalTasks) : 0.0;

    final activeNodesCount = nodes.length;
    final moodAvg = lifeSummary.averageMood;
    final habitCount = nodes.where((n) => n.type == NodeType.habit).length;

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
      builder: (context) => _ExportDataDialog(nodes: nodes),
    );
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
                Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No matching nodes',
        style: Theme.of(context).textTheme.bodySmall,
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
  const _ExportDataDialog({required this.nodes});

  final List<MindmapNode> nodes;

  @override
  State<_ExportDataDialog> createState() => _ExportDataDialogState();
}

class _ExportDataDialogState extends State<_ExportDataDialog> {
  bool _isJson = true;
  late String _data;

  @override
  void initState() {
    super.initState();
    _generateData();
  }

  void _generateData() {
    if (_isJson) {
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
      title: const Text('Export Workspace Data'),
      content: SizedBox(
        width: 600,
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('JSON Format'),
                  selected: _isJson,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _isJson = true;
                        _generateData();
                      });
                    }
                  },
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text('CSV Format'),
                  selected: !_isJson,
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _isJson = false;
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
                const SnackBar(content: Text('Copied data to clipboard!')),
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

class _FocusTimerAnalyticsPanel extends StatelessWidget {
  const _FocusTimerAnalyticsPanel({required this.summary, required this.today});

  final InsightsSummary summary;
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
                Text(
                  'Focus Session Analytics',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MetricRail(
              children: [
                _MetricPill(
                  icon: Icons.timer_outlined,
                  label:
                      '${summary.totalFocusMinutesToday} focus minutes today',
                ),
                _MetricPill(
                  icon: Icons.alarm_on,
                  label:
                      '${summary.weeklyFocusSessionsCount} focus sessions this week',
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
                    final mins = summary.focusMinutesByDay[key] ?? 0;
                    return _FocusDayPill(day: day, focusMinutes: mins);
                  }(),
              ],
            ),
          ],
        ),
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
