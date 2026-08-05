/// Workspace detail page with List, Kanban, and Gantt views.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/runtime_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_design_tokens.dart';
import '../../core/theme/node_visuals.dart';
import '../../core/utils/date_utils.dart';
import '../mindmap/application/canvas_board_package_service.dart';
import '../mindmap/application/canvas_command_controller.dart';
import '../mindmap/application/canvas_workshop_controller.dart';
import '../mindmap/application/collaboration_controller.dart';
import '../mindmap/application/media_file_import_service.dart';
import '../mindmap/application/mindmap_providers.dart';
import '../mindmap/application/nested_board_service.dart';
import '../mindmap/data/collaboration_canvas_board_repository.dart';
import '../mindmap/domain/canvas_board.dart';
import '../mindmap/domain/canvas_board_template.dart';
import '../mindmap/domain/canvas_workshop.dart';
import '../mindmap/domain/collaboration_room.dart';
import '../mindmap/domain/mindmap_node.dart';
import '../mindmap/domain/workspace_context.dart';
import '../mindmap/presentation/canvas_assistant_dialog.dart';
import '../mindmap/presentation/collaboration_share_dialog.dart';
import '../mindmap/presentation/mindmap_canvas.dart';
import 'application/voting_providers.dart';
import 'application/workspace_goal_summary.dart';
import 'application/workspace_health.dart';
import 'application/workspace_markdown_export.dart';
import 'application/workspace_next_actions.dart';
import 'application/workspace_overview.dart';
import 'application/workspace_recommendations.dart';
import 'application/workspace_relationships.dart';
import 'application/workspace_timeline.dart';
import 'data/workshop_agenda_templates.dart';
import 'data/workspace_title_repository.dart';

/// View modes for the workspace detail page.
enum _WorkspaceView { list, kanban, gantt, canvas }

enum _WorkspaceCanvasVotingAction { start, end, reveal, reset, results }

enum _WorkspaceWorkshopAction {
  start,
  startFacilitated,
  pause,
  resume,
  advanceStage,
  restartStage,
  skipStage,
  revealStage,
  extend1,
  extend5,
  extend10,
  end,
  participants,
  summary,
}

enum _WorkspaceBoardAction { rename, duplicate, archive, restore }

enum _WorkspaceBoardTransferAction { import, export }

String _canvasVotingLabel(CanvasObject object) {
  for (final key in const <String>['text', 'title', 'fileName']) {
    final value = object.payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return object.type.name;
}

CanvasBoard _recordCanvasMutation(CanvasBoard before, CanvasBoard after) {
  final now = after.updatedAt;
  if (before.votingSession != after.votingSession) {
    final type = switch (after.votingSession.status) {
      CanvasVotingStatus.active
          when before.votingSession.status != CanvasVotingStatus.active =>
        CanvasActivityType.votingStarted,
      CanvasVotingStatus.ended => CanvasActivityType.votingEnded,
      CanvasVotingStatus.inactive => CanvasActivityType.votingReset,
      _ => CanvasActivityType.votesChanged,
    };
    final summary = switch (type) {
      CanvasActivityType.votingStarted =>
        'Started voting with ${after.votingSession.maxVotesPerParticipant} votes per participant',
      CanvasActivityType.votingEnded => 'Ended voting session',
      CanvasActivityType.votingReset => 'Reset voting session',
      _ => 'Updated canvas votes',
    };
    return after.recordActivity(type: type, summary: summary, now: now);
  }
  final beforeById = <String, CanvasObject>{
    for (final object in before.objects) object.id: object,
  };
  final afterById = <String, CanvasObject>{
    for (final object in after.objects) object.id: object,
  };
  final addedIds = afterById.keys
      .where((objectId) => !beforeById.containsKey(objectId))
      .toList();
  if (addedIds.isNotEmpty) {
    return after.recordActivity(
      type: CanvasActivityType.objectsAdded,
      summary:
          'Added ${addedIds.length} canvas object${addedIds.length == 1 ? '' : 's'}',
      now: now,
      objectIds: addedIds,
    );
  }
  final deletedIds = beforeById.keys
      .where((objectId) => !afterById.containsKey(objectId))
      .toList();
  if (deletedIds.isNotEmpty) {
    return after.recordActivity(
      type: CanvasActivityType.objectsDeleted,
      summary:
          'Deleted ${deletedIds.length} canvas object${deletedIds.length == 1 ? '' : 's'}',
      now: now,
      objectIds: deletedIds,
    );
  }
  final updatedIds = afterById.keys
      .where(
        (objectId) =>
            beforeById.containsKey(objectId) &&
            beforeById[objectId] != afterById[objectId],
      )
      .toList();
  if (updatedIds.isNotEmpty) {
    return after.recordActivity(
      type: CanvasActivityType.objectsUpdated,
      summary:
          'Updated ${updatedIds.length} canvas object${updatedIds.length == 1 ? '' : 's'}',
      now: now,
      objectIds: updatedIds,
    );
  }
  return after;
}

class WorkspaceDetailPage extends ConsumerStatefulWidget {
  const WorkspaceDetailPage({
    super.key,
    required this.typeName,
    required this.name,
    this.initialCanvas = false,
    this.initialBoardId,
  });

  final String typeName;
  final String name;
  final bool initialCanvas;
  final String? initialBoardId;

  @override
  ConsumerState<WorkspaceDetailPage> createState() =>
      _WorkspaceDetailPageState();
}

class _WorkspaceDetailPageState extends ConsumerState<WorkspaceDetailPage> {
  late _WorkspaceView _view;

  @override
  void initState() {
    super.initState();
    _view = widget.initialCanvas ? _WorkspaceView.canvas : _WorkspaceView.list;
  }

  @override
  void didUpdateWidget(covariant WorkspaceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCanvas != widget.initialCanvas &&
        widget.initialCanvas) {
      _view = _WorkspaceView.canvas;
    }
  }

  WorkspaceContextType get _type {
    for (final t in WorkspaceContextType.values) {
      if (t.name == widget.typeName) return t;
    }
    return WorkspaceContextType.project;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contextsFuture = ref.watch(workspaceContextsProvider);
    final titleMap = ref.watch(workspaceTitleProvider);
    final titleKey = '${_type.name}_${widget.name}';
    final customTitle = titleMap[titleKey];
    final displayTitle = customTitle == null || customTitle.isEmpty
        ? '${_type.label} ${widget.name}'
        : customTitle;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/workspaces'),
        ),
        title: Text(displayTitle, style: theme.textTheme.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SegmentedButton<_WorkspaceView>(
              segments: const [
                ButtonSegment(
                  value: _WorkspaceView.list,
                  label: Text('List'),
                  icon: Icon(Icons.view_list_outlined),
                ),
                ButtonSegment(
                  value: _WorkspaceView.kanban,
                  label: Text('Kanban'),
                  icon: Icon(Icons.view_kanban_outlined),
                ),
                ButtonSegment(
                  value: _WorkspaceView.gantt,
                  label: Text('Gantt'),
                  icon: Icon(Icons.waterfall_chart_outlined),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selected) {
                setState(() => _view = selected.first);
              },
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
      body: contextsFuture.when(
        data: (contexts) {
          final workspace = contexts.contextFor(_type, widget.name);
          final detailView = switch (_view) {
            _WorkspaceView.list => _WorkspaceListView(workspace: workspace),
            _WorkspaceView.kanban => _WorkspaceKanbanView(workspace: workspace),
            _WorkspaceView.gantt => _WorkspaceGanttView(workspace: workspace),
            _WorkspaceView.canvas => _WorkspaceCanvasView(
              workspace: workspace,
              initialBoardId: widget.initialBoardId,
            ),
          };

          return Column(
            children: [
              if (_view != _WorkspaceView.list)
                _WorkspaceDetailHeader(workspace: workspace),
              Expanded(child: detailView),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('Failed to load workspace'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => ref.invalidate(workspaceContextsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkshopTemplateDialog extends ConsumerWidget {
  const _WorkshopTemplateDialog();

  static const _builtIns = <(String, String, String, IconData)>[
    (
      'brainstorm',
      'Brainstorm',
      'Private ideas, reveal, cluster, vote, review',
      Icons.lightbulb_outline,
    ),
    (
      'retrospective',
      'Retrospective',
      'Reflect, reveal themes, prioritize actions',
      Icons.replay_outlined,
    ),
    (
      'decision',
      'Decision workshop',
      'Generate options, vote, confirm decision',
      Icons.rule_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(workshopAgendaTemplatesProvider);
    const workshop = CanvasWorkshopController();
    return SimpleDialog(
      title: const Text('Start facilitated workshop'),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SingleChildScrollView(
            key: const ValueKey('workspace-workshop-template-list'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final builtIn in _builtIns)
                  SimpleDialogOption(
                    key: ValueKey('workspace-workshop-template-${builtIn.$1}'),
                    onPressed: () => Navigator.pop(
                      context,
                      workshop.agendaTemplate(builtIn.$1),
                    ),
                    child: ListTile(
                      leading: Icon(builtIn.$4),
                      title: Text(builtIn.$2),
                      subtitle: Text(builtIn.$3),
                    ),
                  ),
                for (final template in templates)
                  ListTile(
                    key: ValueKey('workspace-workshop-template-${template.id}'),
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(template.name),
                    subtitle: Text('${template.stages.length} stages'),
                    onTap: () => Navigator.pop(context, template.stages),
                    trailing: IconButton(
                      tooltip: 'Delete ${template.name}',
                      onPressed: () => ref
                          .read(workshopAgendaTemplatesProvider.notifier)
                          .delete(template.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                SimpleDialogOption(
                  key: const ValueKey('workspace-workshop-template-create'),
                  onPressed: () async {
                    final template = await showDialog<WorkshopAgendaTemplate>(
                      context: context,
                      builder: (_) => const _CreateWorkshopTemplateDialog(),
                    );
                    if (template == null || !context.mounted) return;
                    await ref
                        .read(workshopAgendaTemplatesProvider.notifier)
                        .save(template);
                  },
                  child: const ListTile(
                    leading: Icon(Icons.add),
                    title: Text('Create custom template'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateWorkshopTemplateDialog extends StatefulWidget {
  const _CreateWorkshopTemplateDialog();

  @override
  State<_CreateWorkshopTemplateDialog> createState() =>
      _CreateWorkshopTemplateDialogState();
}

class _CreateWorkshopTemplateDialogState
    extends State<_CreateWorkshopTemplateDialog> {
  String _name = '';
  final List<_WorkshopStageDraft> _stages = <_WorkshopStageDraft>[
    _WorkshopStageDraft(),
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create workshop template'),
    content: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('workshop-template-fields'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('workshop-template-name'),
              decoration: const InputDecoration(labelText: 'Template name'),
              onChanged: (value) => _name = value,
            ),
            const SizedBox(height: 12),
            for (final (index, stage) in _stages.indexed)
              Row(
                key: ValueKey('workshop-template-stage-$index'),
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: ValueKey('workshop-template-stage-title-$index'),
                      decoration: const InputDecoration(
                        labelText: 'Stage title',
                      ),
                      onChanged: (value) => stage.title = value,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<CanvasWorkshopStageType>(
                      key: ValueKey('workshop-template-stage-type-$index'),
                      initialValue: stage.type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        for (final type in CanvasWorkshopStageType.values)
                          DropdownMenuItem(value: type, child: Text(type.name)),
                      ],
                      onChanged: (value) => stage.type = value ?? stage.type,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('workshop-template-stage-minutes-$index'),
                      initialValue: '${stage.minutes}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                      onChanged: (value) =>
                          stage.minutes = int.tryParse(value) ?? 0,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete stage',
                    onPressed: _stages.length == 1
                        ? null
                        : () => setState(() => _stages.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('workshop-template-add-stage'),
                onPressed: _stages.length == 12
                    ? null
                    : () => setState(() => _stages.add(_WorkshopStageDraft())),
                icon: const Icon(Icons.add),
                label: const Text('Add stage'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('workshop-template-save'),
        onPressed: () {
          if (_name.trim().isEmpty ||
              _stages.any(
                (stage) =>
                    stage.title.trim().isEmpty ||
                    stage.minutes < 1 ||
                    stage.minutes > 120,
              )) {
            return;
          }
          final id = const Uuid().v4();
          Navigator.pop(
            context,
            WorkshopAgendaTemplate(
              id: id,
              name: _name,
              stages: [
                for (final (index, stage) in _stages.indexed)
                  CanvasWorkshopStage(
                    id: '$id-$index',
                    title: stage.title.trim(),
                    type: stage.type,
                    durationSeconds: stage.minutes * 60,
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

final class _WorkshopStageDraft {
  String title = '';
  CanvasWorkshopStageType type = CanvasWorkshopStageType.intro;
  int minutes = 5;
}

enum _NestedBoardDialogChoice { empty, template, copySelection, existing }

sealed class _TemplateGalleryChoice {
  const _TemplateGalleryChoice(this.name);

  final String name;
}

final class _BuiltInTemplateGalleryChoice extends _TemplateGalleryChoice {
  _BuiltInTemplateGalleryChoice(this.template) : super(template.name);

  final BuiltInCanvasBoardTemplate template;
}

final class _UserTemplateGalleryChoice extends _TemplateGalleryChoice {
  _UserTemplateGalleryChoice(this.template) : super(template.name);

  final CanvasBoardTemplate template;
}

final class _NestedBoardNavigationEntry {
  const _NestedBoardNavigationEntry({
    required this.board,
    required this.referenceObjectId,
    required this.viewport,
  });

  final CanvasBoard board;
  final String referenceObjectId;
  final CanvasViewport viewport;
}

class _WorkspaceCanvasView extends ConsumerStatefulWidget {
  const _WorkspaceCanvasView({required this.workspace, this.initialBoardId});

  final WorkspaceContext workspace;
  final String? initialBoardId;

  @override
  ConsumerState<_WorkspaceCanvasView> createState() =>
      _WorkspaceCanvasViewState();
}

class _WorkspaceCanvasViewState extends ConsumerState<_WorkspaceCanvasView> {
  final CanvasCommandStack _history = CanvasCommandStack();
  static const CanvasWorkshopController _workshop = CanvasWorkshopController();
  CanvasBoard? _currentBoard;
  String? _selectedBoardId;
  String? _pendingReconciliationSignature;
  final Map<String, GlobalKey<MindmapCanvasState>> _canvasKeys = {};
  String? _followingPresenterUid;
  String? _workshopMaintenanceSignature;
  bool? _presencePrivacyMode;
  Timer? _workshopTicker;
  List<CanvasObject> _assistantPreviewObjects = const <CanvasObject>[];
  bool _isSharingBoard = false;
  final List<_NestedBoardNavigationEntry> _nestedBoardHistory =
      <_NestedBoardNavigationEntry>[];
  final Set<String> _purgedWorkspaceNames = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedBoardId = widget.initialBoardId?.trim().isEmpty ?? true
        ? null
        : widget.initialBoardId!.trim();
    _workshopTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_currentBoard?.workshopSession.isActive ?? false)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _workshopTicker?.cancel();
    super.dispose();
  }

  Future<int?> _promptWorkshopDuration() async {
    var minutes = 15;
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start workshop'),
        content: TextFormField(
          key: const ValueKey('workspace-workshop-duration'),
          initialValue: '$minutes',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Duration in minutes (5–120)',
          ),
          onChanged: (value) => minutes = int.tryParse(value) ?? 0,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('workspace-workshop-start-confirm'),
            onPressed: () {
              if (minutes < 5 || minutes > 120) return;
              Navigator.pop(dialogContext, minutes);
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Future<List<CanvasWorkshopStage>?> _promptWorkshopTemplate() =>
      showDialog<List<CanvasWorkshopStage>>(
        context: context,
        builder: (dialogContext) => const _WorkshopTemplateDialog(),
      );

  Future<void> _showWorkshopParticipants(
    CollaborationState collaboration,
    CanvasWorkshopSession session,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Workshop participants'),
      content: SizedBox(
        width: 420,
        child: collaboration.members.isEmpty
            ? Text('${session.participantIds.length} local participants')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final member in collaboration.members)
                    ListTile(
                      leading: Icon(
                        member.uid == session.presenterUid
                            ? Icons.present_to_all
                            : Icons.person_outline,
                      ),
                      title: Text(member.displayName),
                      subtitle: Text(member.role.name),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _showWorkshopSummary(
    CanvasWorkshopSummary summary,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Workshop summary'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active time: ${summary.activeDurationSeconds ~/ 60}m ${summary.activeDurationSeconds % 60}s',
            ),
            Text('Participants: ${summary.participantCount}'),
            Text('Objects added: ${summary.objectsAdded}'),
            Text('Objects updated: ${summary.objectsUpdated}'),
            Text('Objects deleted: ${summary.objectsDeleted}'),
            Text('Winning votes: ${summary.votingWinnerVotes}'),
            Text('Clusters: ${summary.clusterCount}'),
            Text('Stages completed: ${summary.completedStageIds.length}'),
            if (summary.stageContributionCounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Contributions by stage',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final entry in summary.stageContributionCounts.entries)
                Text('${entry.key}: ${entry.value}'),
            ],
            if (summary.votingRanking.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Voting ranking',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final entry in summary.votingRanking.entries.take(5))
                Text('${entry.key}: ${entry.value} votes'),
            ],
            if (summary.reactionTotals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in summary.reactionTotals.entries)
                    Chip(label: Text('${entry.key} ${entry.value}')),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  String _workshopTime(CanvasWorkshopSession session) {
    final seconds = session.hasAgenda
        ? session.activeStageRemainingSeconds(DateTime.now())
        : session.remainingSeconds(DateTime.now());
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  GlobalKey<MindmapCanvasState> _canvasKey(String boardId) =>
      _canvasKeys.putIfAbsent(boardId, GlobalKey<MindmapCanvasState>.new);

  CanvasBoard _withVotingSession(
    CanvasBoard board,
    CanvasVotingSession session,
    DateTime now,
  ) => board.copyWith(
    votingSession: session,
    objects: <CanvasObject>[
      for (final object in board.objects)
        if (object.voteCount == session.votesForObject(object.id))
          object
        else
          object.withVoteCount(
            session.votesForObject(object.id),
            updatedAt: now,
          ),
    ],
    updatedAt: now,
  );

  Future<void> _startVoting(
    CanvasBoard board,
    Future<void> Function(CanvasBoard board) execute,
  ) async {
    var limitText = '3';
    var anonymous = false;
    final settings = await showDialog<(int, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Start voting session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('workspace-voting-limit-field'),
                initialValue: limitText,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (value) => limitText = value,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'Votes per participant',
                  helperText: 'Enter 1 to 10',
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('workspace-voting-anonymous'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Anonymous voting'),
                value: anonymous,
                onChanged: (value) =>
                    setDialogState(() => anonymous = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('workspace-voting-start-confirm'),
              onPressed: () {
                final value = int.tryParse(limitText);
                if (value == null || value < 1 || value > 10) return;
                Navigator.pop(dialogContext, (value, anonymous));
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
    if (settings == null || !mounted) return;
    final now = DateTime.now();
    await execute(
      _withVotingSession(
        board,
        board.votingSession.start(
          maxVotes: settings.$1,
          anonymous: settings.$2,
        ),
        now,
      ),
    );
  }

  Future<void> _showVotingResults(CanvasBoard board) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final ranked =
          board.objects
              .where((object) => object.type != CanvasObjectType.connector)
              .toList()
            ..sort((left, right) {
              final voteComparison = board.votingSession
                  .votesForObject(right.id)
                  .compareTo(board.votingSession.votesForObject(left.id));
              if (voteComparison != 0) return voteComparison;
              final labelComparison = _canvasVotingLabel(
                left,
              ).compareTo(_canvasVotingLabel(right));
              return labelComparison != 0
                  ? labelComparison
                  : left.id.compareTo(right.id);
            });
      final hasVotes = ranked.any(
        (object) => board.votingSession.votesForObject(object.id) > 0,
      );
      final visible = hasVotes
          ? ranked
                .where(
                  (object) => board.votingSession.votesForObject(object.id) > 0,
                )
                .toList()
          : ranked;
      return AlertDialog(
        title: const Text('Voting results'),
        content: SizedBox(
          width: 420,
          child: visible.isEmpty
              ? const Text('No canvas objects to rank.')
              : ListView.separated(
                  key: const ValueKey('workspace-voting-results-list'),
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final object = visible[index];
                    final votes = board.votingSession.votesForObject(object.id);
                    return ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(_canvasVotingLabel(object)),
                      trailing: Text('$votes vote${votes == 1 ? '' : 's'}'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  Future<String?> _promptBoardTitle(String currentTitle) async {
    var title = currentTitle;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename board'),
        content: TextFormField(
          key: const ValueKey('workspace-board-title-field'),
          initialValue: currentTitle,
          autofocus: true,
          maxLength: 120,
          onChanged: (value) => title = value,
          decoration: const InputDecoration(labelText: 'Board title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('workspace-board-rename-confirm'),
            onPressed: () {
              final normalized = title.trim();
              if (normalized.isEmpty) return;
              Navigator.pop(dialogContext, normalized);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  CanvasBoard _duplicateBoard(CanvasBoard source, DateTime now) =>
      CanvasBoard(
        id: '${source.id}:copy:${now.microsecondsSinceEpoch}',
        kind: source.kind,
        title: '${source.title} copy',
        day: source.day,
        workspaceName: source.workspaceName,
        viewport: source.viewport,
        settings: source.settings,
        votingSession: source.votingSession.reset(),
        schemaVersion: source.schemaVersion,
        objects: <CanvasObject>[
          for (final object in source.objects) object.copyWith(updatedAt: now),
        ],
        createdAt: now,
        updatedAt: now,
      ).recordActivity(
        type: CanvasActivityType.boardDuplicated,
        summary: 'Duplicated from ${source.title}',
        now: now,
      );

  Future<void> _persistManagedBoard(
    CanvasBoard board,
    String workspaceName, {
    bool select = false,
  }) async {
    await ref.read(canvasBoardRepositoryProvider).saveBoard(board);
    if (!mounted) return;
    setState(() {
      if (select) {
        _selectedBoardId = board.id;
        _currentBoard = board;
        _history.clear();
      } else if (_selectedBoardId == board.id ||
          _currentBoard?.id == board.id) {
        _currentBoard = board;
      }
    });
    ref.invalidate(projectCanvasBoardProvider(workspaceName));
    ref.invalidate(projectCanvasBoardsProvider(workspaceName));
  }

  void _selectManagedBoard(CanvasBoard board) {
    final boardDay = board.day ?? DateTime.now();
    context.go(
      '/calendar/${dayKey(boardDay)}?board=${Uri.encodeQueryComponent(board.id)}',
    );
  }

  void _openNestedBoard(CanvasBoard board, CanvasObject reference) {
    final current = _currentBoard;
    if (current != null) {
      _nestedBoardHistory.add(
        _NestedBoardNavigationEntry(
          board: current,
          referenceObjectId: reference.id,
          viewport: current.viewport,
        ),
      );
    }
    _selectManagedBoard(board);
    _replaceBoardRoute(board.id);
  }

  void _backFromNestedBoard() {
    if (_nestedBoardHistory.isEmpty) return;
    final entry = _nestedBoardHistory.removeLast();
    _selectManagedBoard(entry.board.copyWith(viewport: entry.viewport));
    _replaceBoardRoute(entry.board.id);
  }

  void _replaceBoardRoute(String boardId) {
    final workspace = widget.workspace;
    final location = Uri(
      path:
          '/workspaces/${workspace.type.name}/${Uri.encodeComponent(workspace.name)}',
      queryParameters: <String, String>{'view': 'canvas', 'board': boardId},
    ).toString();
    context.replace(location);
  }

  Future<_TemplateGalleryChoice?> _showTemplateGallery(
    CanvasBoard parent,
  ) async {
    final workspaceName = parent.workspaceName!;
    final workspaceBoards = await ref.read(
      workspaceBoardGraphProvider(workspaceName).future,
    );
    final storedTemplates = await ref
        .read(canvasBoardTemplateRepositoryProvider)
        .listTemplates();
    final userTemplates = await ref
        .read(boardTemplateServiceProvider)
        .availableUserTemplates(
          workspaceName,
          workspaceBoards: workspaceBoards,
          storedTemplates: storedTemplates,
        );
    if (!mounted) return null;
    if (storedTemplates.length != userTemplates.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template source is unavailable.')),
      );
    }
    final boardsById = <String, CanvasBoard>{
      for (final board in workspaceBoards) board.id: board,
    };
    final sourceBoards = <String, CanvasBoard>{
      for (final template in userTemplates)
        template.id: ?boardsById[template.sourceBoardId],
    };
    return showDialog<_TemplateGalleryChoice>(
      context: context,
      builder: (dialogContext) => _TemplateGalleryDialog(
        builtIns: builtInCanvasBoardTemplates,
        userTemplates: userTemplates
            .map(_UserTemplateGalleryChoice.new)
            .toList(growable: false),
        sourceBoards: sourceBoards,
      ),
    );
  }

  Future<void> _createNestedBoard(
    CanvasBoard parent,
    List<CanvasBoard> boards,
  ) async {
    final choice = await showDialog<_NestedBoardDialogChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Nested board'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _NestedBoardDialogChoice.empty),
            child: const ListTile(
              leading: Icon(Icons.dashboard_customize_outlined),
              title: Text('Board kosong'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _NestedBoardDialogChoice.template),
            child: const ListTile(
              leading: Icon(Icons.auto_awesome_outlined),
              title: Text('Pilih template'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              dialogContext,
              _NestedBoardDialogChoice.copySelection,
            ),
            child: const ListTile(
              leading: Icon(Icons.copy_all_outlined),
              title: Text('Salin selection'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(dialogContext, _NestedBoardDialogChoice.existing),
            child: const ListTile(
              leading: Icon(Icons.add_link_rounded),
              title: Text('Tautkan board existing'),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final selectedTemplate = choice == _NestedBoardDialogChoice.template
        ? await _showTemplateGallery(parent)
        : null;
    if (!mounted) return;
    if (choice == _NestedBoardDialogChoice.template &&
        selectedTemplate == null) {
      return;
    }
    List<CanvasObject>? templateObjects;
    try {
      templateObjects = switch (selectedTemplate) {
        _BuiltInTemplateGalleryChoice(:final template) =>
          ref
              .read(boardTemplateServiceProvider)
              .instantiateBuiltInTemplate(
                template: template,
                now: DateTime.now(),
              ),
        _UserTemplateGalleryChoice() => null,
        null => null,
      };
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (!mounted) return;
    final nested = NestedBoardService(
      repository: ref.read(canvasBoardRepositoryProvider),
    );
    if (choice == _NestedBoardDialogChoice.existing) {
      final candidates = boards
          .where((board) => board.id != parent.id)
          .toList(growable: false);
      if (!mounted) return;
      final target = await showDialog<CanvasBoard>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Pilih board'),
          children: [
            for (final board in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, board),
                child: ListTile(
                  leading: Icon(
                    board.isTrashed
                        ? Icons.delete_outline_rounded
                        : Icons.dashboard_outlined,
                  ),
                  title: Text(board.title),
                  subtitle: board.isTrashed ? const Text('Trash') : null,
                ),
              ),
          ],
        ),
      );
      if (!mounted || target == null) return;
      if (target.isTrashed) {
        await nested.restoreBoard(boardId: target.id, now: DateTime.now());
        if (!mounted) return;
      }
      await nested.linkExistingBoard(
        sourceBoardId: parent.id,
        targetBoardId: target.id,
        now: DateTime.now(),
      );
      if (!mounted) return;
    } else {
      try {
        await nested.createNestedBoard(
          parentBoardId: parent.id,
          title: selectedTemplate?.name ?? 'Untitled board',
          templateObjects: templateObjects,
          sourceBoardId: switch (selectedTemplate) {
            _UserTemplateGalleryChoice(:final template) =>
              template.sourceBoardId,
            _ => null,
          },
          selectedObjectIds: choice == _NestedBoardDialogChoice.copySelection
              ? parent.objects.map((object) => object.id).toSet()
              : const <String>{},
          now: DateTime.now(),
        );
      } on StateError catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
      if (!mounted) return;
    }
    ref.invalidate(projectCanvasBoardProvider(parent.workspaceName!));
    ref.invalidate(projectCanvasBoardsProvider(parent.workspaceName!));
    ref.invalidate(workspaceBoardGraphProvider(parent.workspaceName!));
  }

  Future<void> _deleteNestedBoardReference(
    CanvasBoard source,
    CanvasObject reference,
  ) async {
    final choice = await showDialog<BoardReferenceDeleteChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus nested board?'),
        content: const Text(
          'Pilih apakah hanya kartu atau board ikut dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              BoardReferenceDeleteChoice.referenceOnly,
            ),
            child: const Text('Hapus kartu ini saja'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              BoardReferenceDeleteChoice.boardAndAllReferences,
            ),
            child: const Text('Hapus board dan semua tautan'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await NestedBoardService(
      repository: ref.read(canvasBoardRepositoryProvider),
    ).deleteBoardReference(
      sourceBoardId: source.id,
      referenceObjectId: reference.id,
      choice: choice,
      now: DateTime.now(),
    );
    ref.invalidate(projectCanvasBoardsProvider(source.workspaceName!));
    ref.invalidate(workspaceBoardGraphProvider(source.workspaceName!));
  }

  Future<CanvasBoard?> _createTopLevelBoardFromTemplate(
    CanvasBoard galleryContext,
  ) async {
    final selected = await _showTemplateGallery(galleryContext);
    if (selected == null || !mounted) return null;
    final now = DateTime.now();
    final templateObjects = switch (selected) {
      _BuiltInTemplateGalleryChoice(:final template) =>
        ref
            .read(boardTemplateServiceProvider)
            .instantiateBuiltInTemplate(template: template, now: now),
      _UserTemplateGalleryChoice() => null,
    };
    try {
      return await NestedBoardService(
        repository: ref.read(canvasBoardRepositoryProvider),
      ).createTopLevelBoard(
        workspaceName: galleryContext.workspaceName!,
        title: selected.name,
        templateObjects: templateObjects,
        sourceBoardId: switch (selected) {
          _UserTemplateGalleryChoice(:final template) => template.sourceBoardId,
          _ => null,
        },
        now: now,
      );
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return null;
    }
  }

  Future<void> _showBoardDashboard({
    required String workspaceName,
    required CanvasBoard currentBoard,
    required List<CanvasBoard> initialBoards,
  }) async {
    var boards = <CanvasBoard>[
      if (!initialBoards.any((board) => board.id == currentBoard.id))
        currentBoard,
      ...initialBoards,
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          boards.sort(
            (left, right) => right.updatedAt.compareTo(left.updatedAt),
          );
          final activeCount = boards.where((board) => !board.isArchived).length;
          return AlertDialog(
            title: const Text('Project boards'),
            content: SizedBox(
              width: 680,
              height: 520,
              child: boards.isEmpty
                  ? const Center(child: Text('No project boards yet.'))
                  : ListView.separated(
                      key: const ValueKey('workspace-board-dashboard-list'),
                      itemCount: boards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final board = boards[index];
                        return Card(
                          key: ValueKey('workspace-board-card-${board.id}'),
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            onTap: board.isArchived
                                ? null
                                : () {
                                    Navigator.pop(dialogContext);
                                    _selectManagedBoard(board);
                                  },
                            leading: SizedBox(
                              width: 96,
                              height: 56,
                              child: _CanvasBoardPreview(board: board),
                            ),
                            title: Text(board.title),
                            subtitle: Text(
                              '${board.objects.length} objects • ${board.isArchived ? 'Archived' : 'Updated ${_shortBoardDate(board.updatedAt)}'}',
                            ),
                            selected: board.id == currentBoard.id,
                            trailing: PopupMenuButton<_WorkspaceBoardAction>(
                              key: ValueKey(
                                'workspace-board-actions-${board.id}',
                              ),
                              onSelected: (action) async {
                                switch (action) {
                                  case _WorkspaceBoardAction.rename:
                                    final title = await _promptBoardTitle(
                                      board.title,
                                    );
                                    if (title == null || !mounted) return;
                                    final renamed = board
                                        .copyWith(
                                          title: title,
                                          updatedAt: DateTime.now(),
                                        )
                                        .recordActivity(
                                          type: CanvasActivityType.boardRenamed,
                                          summary: 'Renamed board to $title',
                                          now: DateTime.now(),
                                        );
                                    await _persistManagedBoard(
                                      renamed,
                                      workspaceName,
                                    );
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      boards = <CanvasBoard>[
                                        for (final candidate in boards)
                                          if (candidate.id == board.id)
                                            renamed
                                          else
                                            candidate,
                                      ];
                                    });
                                  case _WorkspaceBoardAction.duplicate:
                                    final duplicate = _duplicateBoard(
                                      board,
                                      DateTime.now(),
                                    );
                                    await _persistManagedBoard(
                                      duplicate,
                                      workspaceName,
                                      select: true,
                                    );
                                    if (!dialogContext.mounted) return;
                                    setDialogState(
                                      () => boards = <CanvasBoard>[
                                        duplicate,
                                        ...boards,
                                      ],
                                    );
                                  case _WorkspaceBoardAction.archive:
                                    if (activeCount <= 1) return;
                                    final archived = board
                                        .copyWith(
                                          isArchived: true,
                                          updatedAt: DateTime.now(),
                                        )
                                        .recordActivity(
                                          type:
                                              CanvasActivityType.boardArchived,
                                          summary: 'Archived board',
                                          now: DateTime.now(),
                                        );
                                    await _persistManagedBoard(
                                      archived,
                                      workspaceName,
                                    );
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      boards = <CanvasBoard>[
                                        for (final candidate in boards)
                                          if (candidate.id == board.id)
                                            archived
                                          else
                                            candidate,
                                      ];
                                    });
                                    final selectedId =
                                        _selectedBoardId ?? currentBoard.id;
                                    if (selectedId == board.id) {
                                      final fallback = boards.firstWhereOrNull(
                                        (candidate) =>
                                            candidate.id != board.id &&
                                            !candidate.isArchived,
                                      );
                                      if (fallback != null) {
                                        _selectManagedBoard(fallback);
                                      }
                                    }
                                  case _WorkspaceBoardAction.restore:
                                    final restored = board
                                        .copyWith(
                                          isArchived: false,
                                          updatedAt: DateTime.now(),
                                        )
                                        .recordActivity(
                                          type:
                                              CanvasActivityType.boardRestored,
                                          summary: 'Restored board',
                                          now: DateTime.now(),
                                        );
                                    await _persistManagedBoard(
                                      restored,
                                      workspaceName,
                                    );
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      boards = <CanvasBoard>[
                                        for (final candidate in boards)
                                          if (candidate.id == board.id)
                                            restored
                                          else
                                            candidate,
                                      ];
                                    });
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: _WorkspaceBoardAction.rename,
                                  child: Text('Rename'),
                                ),
                                const PopupMenuItem(
                                  value: _WorkspaceBoardAction.duplicate,
                                  child: Text('Duplicate'),
                                ),
                                if (board.isArchived)
                                  const PopupMenuItem(
                                    value: _WorkspaceBoardAction.restore,
                                    child: Text('Restore'),
                                  )
                                else
                                  PopupMenuItem(
                                    value: _WorkspaceBoardAction.archive,
                                    enabled: activeCount > 1,
                                    child: const Text('Archive'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              FilledButton.icon(
                key: const ValueKey('workspace-board-dashboard-new'),
                onPressed: () async {
                  final created = await _createTopLevelBoardFromTemplate(
                    currentBoard,
                  );
                  if (created == null || !dialogContext.mounted) return;
                  setDialogState(
                    () => boards = <CanvasBoard>[created, ...boards],
                  );
                  ref.invalidate(projectCanvasBoardsProvider(workspaceName));
                  ref.invalidate(workspaceBoardGraphProvider(workspaceName));
                },
                icon: const Icon(Icons.add),
                label: const Text('New board'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportBoardPackage(CanvasBoard board) async {
    try {
      final attachmentRepository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final bytes = await CanvasBoardPackageService(
        attachmentRepository: attachmentRepository,
      ).exportPackage(board);
      final normalizedTitle = board.title
          .trim()
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-');
      final path = await FilePicker.saveFile(
        dialogTitle: 'Export project board',
        fileName:
            '${normalizedTitle.isEmpty ? 'project-board' : normalizedTitle}.varcanvas',
        type: FileType.custom,
        allowedExtensions: const <String>['varcanvas'],
        bytes: bytes,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project board exported.')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Board export failed: $error')));
    }
  }

  Future<void> _importBoardPackage(String workspaceName) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Import project board',
        type: FileType.custom,
        allowedExtensions: const <String>['varcanvas'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Selected board package is empty.');
      }
      final attachmentRepository = await ref.read(
        nodeAttachmentRepositoryProvider.future,
      );
      final board = await CanvasBoardPackageService(
        attachmentRepository: attachmentRepository,
      ).importPackage(bytes, workspaceName: workspaceName, now: DateTime.now());
      await _persistManagedBoard(board, workspaceName, select: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project board imported.')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Board import failed: $error')));
    }
  }

  Future<void> _shareBoard(CanvasBoard board) async {
    if (_isSharingBoard || board.kind != CanvasBoardKind.project) return;
    final collaboration = ref.read(collaborationProvider);
    if (collaboration.roomId != null &&
        (collaboration.roomTarget?.kind !=
                CollaborationTargetKind.projectBoard ||
            collaboration.roomTarget?.id != board.id)) {
      final switchRoom = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Switch collaboration room?'),
          content: const Text(
            'Current room will close before this project board is shared.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (switchRoom != true || !mounted) return;
      await ref.read(collaborationActionsProvider).leaveRoom();
    }
    if (!mounted) return;
    setState(() => _isSharingBoard = true);
    try {
      await ref.read(canvasBoardRepositoryProvider).saveBoard(board);
      final current = ref.read(collaborationProvider);
      if (current.roomTarget?.kind != CollaborationTargetKind.projectBoard ||
          current.roomTarget?.id != board.id) {
        await ref
            .read(collaborationActionsProvider)
            .createProjectRoom(boardId: board.id, label: board.title);
      }
      if (!mounted) return;
      await showCollaborationShareDialog(context, targetLabel: board.title);
    } on CollaborationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project board could not be shared.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingBoard = false);
    }
  }

  Future<void> _showActivityHistory(CanvasBoard board) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Canvas activity'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: board.activity.isEmpty
            ? const Center(child: Text('Canvas changes will appear here.'))
            : ListView.separated(
                key: const ValueKey('workspace-canvas-activity-list'),
                itemCount: board.activity.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final activity = board.activity[index];
                  return ListTile(
                    leading: Icon(_canvasActivityIcon(activity.type)),
                    title: Text(activity.summary),
                    subtitle: Text(
                      _canvasActivityTimestamp(activity.occurredAt),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  void didUpdateWidget(covariant _WorkspaceCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.type != widget.workspace.type ||
        oldWidget.workspace.name != widget.workspace.name) {
      _currentBoard = null;
      _selectedBoardId = widget.initialBoardId?.trim().isEmpty ?? true
          ? null
          : widget.initialBoardId!.trim();
      _pendingReconciliationSignature = null;
      _history.clear();
    } else if (oldWidget.initialBoardId != widget.initialBoardId &&
        widget.initialBoardId?.trim().isNotEmpty == true) {
      _selectedBoardId = widget.initialBoardId!.trim();
      _currentBoard = null;
      _history.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final boardName = '${workspace.type.name}:${workspace.name}';
    if (_purgedWorkspaceNames.add(boardName)) {
      unawaited(
        NestedBoardService(
          repository: ref.read(canvasBoardRepositoryProvider),
        ).purgeExpiredTrash(DateTime.now().toUtc(), workspaceName: boardName),
      );
    }
    final boardsAsync = ref.watch(projectCanvasBoardsProvider(boardName));

    return boardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: FilledButton.icon(
          onPressed: () =>
              ref.invalidate(projectCanvasBoardsProvider(boardName)),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry canvas'),
        ),
      ),
      data: (boards) {
        final primaryBoardId = projectCanvasBoardId(boardName);
        final selectedBoardId = _selectedBoardId ?? primaryBoardId;
        final persisted = boards
            .where((candidate) => candidate.id == selectedBoardId)
            .firstOrNull;
        final cached = _currentBoard;
        final explicitBoardId = widget.initialBoardId?.trim();
        if (explicitBoardId != null &&
            explicitBoardId.isNotEmpty &&
            persisted == null &&
            cached?.id != explicitBoardId) {
          return Center(
            child: FilledButton.icon(
              onPressed: () =>
                  ref.invalidate(projectCanvasBoardsProvider(boardName)),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Shared board is still loading'),
            ),
          );
        }
        final baseBoard =
            (persisted != null &&
                (cached == null ||
                    cached.id != persisted.id ||
                    persisted.updatedAt.isAfter(cached.updatedAt)))
            ? persisted
            : cached ??
                  CanvasBoard.project(
                    workspaceName: boardName,
                    nodes: workspace.nodes,
                    now: DateTime.now(),
                  );
        final board = baseBoard.reconcileNodeReferences(
          workspace.nodes,
          now: DateTime.now(),
        );
        final collaboration = ref.watch(collaborationProvider);
        final collaborationNotifier = ref.read(collaborationProvider.notifier);
        final isBoardRoom =
            collaboration.roomTarget?.kind ==
                CollaborationTargetKind.projectBoard &&
            collaboration.roomTarget?.id == board.id;
        final canControlWorkshop =
            !isBoardRoom ||
            (collaboration.currentRole?.canControlWorkshop ?? false);
        final canReact =
            isBoardRoom && (collaboration.currentRole?.canReact ?? false);
        final canVote =
            !isBoardRoom || (collaboration.currentRole?.canVote ?? false);
        final canEditBoard =
            !isBoardRoom || (collaboration.currentRole?.canWriteNodes ?? false);
        final presencePrivacyMode =
            isBoardRoom &&
            board.votingSession.isActive &&
            board.votingSession.isAnonymous;
        if (_presencePrivacyMode != presencePrivacyMode) {
          _presencePrivacyMode = presencePrivacyMode;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(
                collaborationNotifier.setPresencePrivacyMode(
                  presencePrivacyMode,
                ),
              );
            }
          });
        }
        final workshopViewerUid = isBoardRoom
            ? collaboration.localUserId
            : 'local';
        final isWorkshopHost =
            board.workshopSession.hostUid == workshopViewerUid;
        final workshopVisibleBoard = board.visibleForWorkshop(
          session: board.workshopSession,
          viewerUid: workshopViewerUid,
          isHost: isWorkshopHost,
        );
        final presenterUid = board.workshopSession.presenterUid;
        if (_followingPresenterUid != null &&
            _followingPresenterUid != presenterUid) {
          _followingPresenterUid = presenterUid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _canvasKey(board.id).currentState?.followCollaborator(presenterUid);
          });
        }
        if (!identical(board, baseBoard)) {
          final signature = <String>[
            for (final object in board.objects)
              if (object.type == CanvasObjectType.nodeReference)
                object.mindmapNodeId ?? '',
          ]..sort();
          final signatureKey = '${board.id}:${signature.join('|')}';
          if (_pendingReconciliationSignature != signatureKey) {
            _pendingReconciliationSignature = signatureKey;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              setState(() => _currentBoard = board);
              await ref.read(canvasBoardRepositoryProvider).saveBoard(board);
              ref.invalidate(projectCanvasBoardProvider(boardName));
              ref.invalidate(projectCanvasBoardsProvider(boardName));
              if (mounted) _pendingReconciliationSignature = null;
            });
          }
        }

        Future<void> save(CanvasBoard next) async {
          if (mounted) setState(() => _currentBoard = next);
          await ref.read(canvasBoardRepositoryProvider).saveBoard(next);
          ref.invalidate(projectCanvasBoardProvider(boardName));
          ref.invalidate(projectCanvasBoardsProvider(boardName));
        }

        Future<void> execute(
          CanvasBoard next, {
          bool recordMutation = true,
        }) async {
          final current = _currentBoard ?? board;
          final tracked = recordMutation
              ? _recordCanvasMutation(current, next)
              : next;
          final applied = _history.execute(
            current,
            ReplaceCanvasBoardCommand(before: current, after: tracked),
          );
          await save(applied);
        }

        Future<void> openCanvasAssistant() async {
          final selectedIds =
              _canvasKey(board.id).currentState?.selectedCanvasObjectIds ??
              const <String>{};
          final result = await showDialog<CanvasAssistantDialogResult>(
            context: context,
            builder: (context) => CanvasAssistantDialog(
              board: workshopVisibleBoard,
              nodes: workspace.nodes,
              selectedObjectIds: selectedIds,
              canApply:
                  canEditBoard &&
                  (!board.workshopSession.isActive || isWorkshopHost),
              workshopAiEndpoint: ref
                  .read(runtimeConfigProvider)
                  .workshopAiEndpoint,
              onPreviewChanged: (objects) {
                if (mounted) {
                  setState(() => _assistantPreviewObjects = objects);
                }
              },
            ),
          );
          if (mounted) {
            setState(() => _assistantPreviewObjects = const <CanvasObject>[]);
          }
          if (result == null || !context.mounted) return;
          final persistedCurrent = await ref
              .read(canvasBoardRepositoryProvider)
              .getBoard(board.id);
          if (!context.mounted) return;
          final candidates = <CanvasBoard>[
            board,
            ?_currentBoard,
            ?persistedCurrent,
          ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
          final current = candidates.first;
          if (!result.analysis.isCurrent(current)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Board changed. Run assistant analysis again.'),
              ),
            );
            return;
          }
          final now = DateTime.now();
          var applied = result.analysis.apply(result.proposalIds, now: now);
          final snapshot = result.aiSummarySnapshot;
          if (snapshot != null) {
            applied = applied.copyWith(
              workshopSession: applied.workshopSession.saveAiSummary(snapshot),
            );
          }
          final next = applied.recordActivity(
            type: CanvasActivityType.assistantApplied,
            summary:
                'Applied ${result.proposalIds.length} canvas assistant suggestion${result.proposalIds.length == 1 ? '' : 's'}',
            now: now,
            objectIds: result.analysis.analyzedObjectIds,
          );
          await execute(next, recordMutation: false);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Canvas assistant suggestions applied.'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  final latest = _currentBoard ?? next;
                  unawaited(save(_history.undo(latest)));
                },
              ),
            ),
          );
        }

        Future<void> handleWorkshopAction(
          _WorkspaceWorkshopAction action,
        ) async {
          final now = DateTime.now();
          switch (action) {
            case _WorkspaceWorkshopAction.start:
              if (!canControlWorkshop) return;
              final minutes = await _promptWorkshopDuration();
              if (minutes == null || !mounted) return;
              var next = _workshop.start(
                board: board,
                sessionId: const Uuid().v4(),
                hostUid: isBoardRoom ? collaboration.localUserId : 'local',
                durationMinutes: minutes,
                now: now,
              );
              if (isBoardRoom) {
                for (final uid in <String>{
                  collaboration.localUserId,
                  ...collaboration.collaborators.keys,
                }) {
                  next = _workshop.join(next, uid, now);
                }
              }
              await execute(next);
            case _WorkspaceWorkshopAction.startFacilitated:
              if (!canControlWorkshop) return;
              final agenda = await _promptWorkshopTemplate();
              if (agenda == null || !mounted) return;
              var next = _workshop.startAgenda(
                board: board,
                sessionId: const Uuid().v4(),
                hostUid: isBoardRoom ? collaboration.localUserId : 'local',
                agenda: agenda,
                now: now,
              );
              if (isBoardRoom) {
                for (final uid in <String>{
                  collaboration.localUserId,
                  ...collaboration.collaborators.keys,
                }) {
                  next = _workshop.join(next, uid, now);
                }
              }
              await execute(next);
            case _WorkspaceWorkshopAction.pause:
              if (canControlWorkshop) {
                await execute(_workshop.pause(board, now));
              }
            case _WorkspaceWorkshopAction.resume:
              if (canControlWorkshop) {
                await execute(_workshop.resume(board, now));
              }
            case _WorkspaceWorkshopAction.advanceStage:
              if (canControlWorkshop) {
                await execute(_workshop.advanceStage(board, now));
              }
            case _WorkspaceWorkshopAction.restartStage:
              if (canControlWorkshop) {
                await execute(_workshop.restartStage(board, now));
              }
            case _WorkspaceWorkshopAction.skipStage:
              if (canControlWorkshop) {
                await execute(_workshop.skipStage(board, now));
              }
            case _WorkspaceWorkshopAction.revealStage:
              if (canControlWorkshop) {
                await execute(_workshop.revealStage(board, now));
              }
            case _WorkspaceWorkshopAction.extend1:
              if (canControlWorkshop) {
                await execute(_workshop.extend(board, 1, now));
              }
            case _WorkspaceWorkshopAction.extend5:
              if (canControlWorkshop) {
                await execute(_workshop.extend(board, 5, now));
              }
            case _WorkspaceWorkshopAction.extend10:
              if (canControlWorkshop) {
                await execute(_workshop.extend(board, 10, now));
              }
            case _WorkspaceWorkshopAction.end:
              if (!canControlWorkshop) return;
              var next = board;
              for (final entry in collaboration.reactionTotals.entries) {
                final recorded =
                    next.workshopSession.reactionTotals[entry.key] ?? 0;
                for (var index = recorded; index < entry.value; index++) {
                  next = _workshop.react(next, entry.key, now);
                }
              }
              await execute(_workshop.end(next, now));
            case _WorkspaceWorkshopAction.participants:
              await _showWorkshopParticipants(
                collaboration,
                board.workshopSession,
              );
            case _WorkspaceWorkshopAction.summary:
              final summary = board.workshopSession.summary;
              if (summary != null) await _showWorkshopSummary(summary);
          }
        }

        if (board.workshopSession.isActive && canControlWorkshop) {
          final participantIds = <String>{
            if (isBoardRoom) collaboration.localUserId else 'local',
            if (isBoardRoom) ...collaboration.collaborators.keys,
          };
          final missing =
              participantIds
                  .difference(board.workshopSession.participantIds)
                  .toList()
                ..sort();
          final maintained = _workshop.maintain(board, DateTime.now());
          final expired =
              !identical(maintained, board) ||
              board.workshopSession.awaitingAdvance;
          final signature =
              '${board.workshopSession.sessionId}:${missing.join(',')}:$expired';
          if ((missing.isNotEmpty || expired) &&
              _workshopMaintenanceSignature != signature) {
            _workshopMaintenanceSignature = signature;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              if (expired) {
                await execute(maintained, recordMutation: false);
                return;
              }
              var next = board;
              final now = DateTime.now();
              for (final uid in missing) {
                next = _workshop.join(next, uid, now);
              }
              await execute(next);
            });
          }
        }

        Future<void> createObjects(List<CanvasObject> objects) async {
          final highestZ = board.objects.fold<int>(
            -1,
            (current, object) =>
                object.zIndex > current ? object.zIndex : current,
          );
          await execute(
            board.copyWith(
              objects: <CanvasObject>[
                ...board.objects,
                for (final (index, object) in objects.indexed)
                  object.copyWith(zIndex: highestZ + index + 1),
              ],
              updatedAt: DateTime.now(),
            ),
          );
        }

        Future<void> updateObjects(List<CanvasObject> objects) async {
          var next = board;
          for (final object in objects) {
            next = next.replaceObject(object);
          }
          await execute(next.copyWith(updatedAt: DateTime.now()));
        }

        Future<void> deleteObjects(List<CanvasObject> objects) => execute(
          board.copyWith(
            objects: board.objects
                .where(
                  (candidate) =>
                      !objects.any((object) => object.id == candidate.id),
                )
                .toList(),
            updatedAt: DateTime.now(),
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: MindmapCanvas(
                key: _canvasKey(board.id),
                nodes: workspace.nodes,
                board: board,
                workshopSession: board.workshopSession,
                workshopViewerUid: workshopViewerUid,
                isWorkshopHost: isWorkshopHost,
                votingParticipantId: workshopViewerUid,
                onViewportChanged: !canEditBoard
                    ? null
                    : (viewport) {
                        final current = _currentBoard ?? board;
                        unawaited(
                          save(
                            current.copyWith(
                              viewport: viewport,
                              updatedAt: DateTime.now(),
                            ),
                          ),
                        );
                      },
                assistantPreviewObjects: _assistantPreviewObjects,
                onCanvasAssistantRequested: () =>
                    unawaited(openCanvasAssistant()),
                collaborationState: isBoardRoom ? collaboration : null,
                onLocalCursorChanged: isBoardRoom
                    ? collaborationNotifier.updateLocalCursor
                    : null,
                onLocalSelectionChanged: isBoardRoom
                    ? collaborationNotifier.updateLocalSelection
                    : null,
                onLocalPingRequested:
                    isBoardRoom && (collaboration.currentRole?.canPing ?? false)
                    ? (position) => unawaited(
                        collaborationNotifier.broadcastPing(position),
                      )
                    : null,
                pingStream: isBoardRoom
                    ? collaborationNotifier.pingStream
                    : null,
                collaborationBoardComments: isBoardRoom
                    ? collaboration.boardComments
                    : const <String, List<CanvasObjectComment>>{},
                onCollaborationBoardCommentsChanged:
                    isBoardRoom &&
                        (collaboration.currentRole?.canComment ?? false)
                    ? collaborationNotifier.saveProjectBoardComments
                    : null,
                canUndo: canEditBoard && _history.canUndo,
                canRedo: canEditBoard && _history.canRedo,
                onUndo: !canEditBoard
                    ? null
                    : () {
                        final current = _currentBoard ?? board;
                        unawaited(save(_history.undo(current)));
                      },
                onRedo: !canEditBoard
                    ? null
                    : () {
                        final current = _currentBoard ?? board;
                        unawaited(save(_history.redo(current)));
                      },
                onNodeMoved: !canEditBoard
                    ? null
                    : (node, position) async {
                        final reference = board.objectById('node:${node.id}');
                        if (reference == null) return;
                        await updateObjects(<CanvasObject>[
                          reference.copyWith(
                            geometry: reference.geometry.copyWith(
                              x: position.dx,
                              y: position.dy,
                            ),
                            updatedAt: DateTime.now(),
                          ),
                        ]);
                      },
                onBoardReferenceOpened: (reference) {
                  final targetId = reference.referencedBoardId;
                  if (targetId == null) return;
                  final target = boards
                      .where((candidate) => candidate.id == targetId)
                      .firstOrNull;
                  if (target == null || target.isTrashed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Board tidak tersedia.')),
                    );
                    return;
                  }
                  _openNestedBoard(target, reference);
                },
                onCanvasObjectCreated: canEditBoard
                    ? (object) => createObjects(<CanvasObject>[object])
                    : null,
                onCanvasObjectUpdated: canEditBoard
                    ? (object) => updateObjects(<CanvasObject>[object])
                    : null,
                onCanvasObjectDeleted: canEditBoard
                    ? (object) => object.type == CanvasObjectType.boardReference
                          ? _deleteNestedBoardReference(board, object)
                          : deleteObjects(<CanvasObject>[object])
                    : null,

                onCanvasObjectsCreated: canEditBoard ? createObjects : null,
                onCanvasObjectsUpdated: canEditBoard ? updateObjects : null,
                onCanvasObjectsDeleted: canEditBoard ? deleteObjects : null,
                onCanvasVoteChanged: !canVote
                    ? null
                    : (objects, delta) async {
                        final session = board.votingSession;
                        if (!session.isActive) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Start voting session before voting.',
                              ),
                            ),
                          );
                          return;
                        }
                        final participantId = isBoardRoom
                            ? collaboration.localUserId
                            : 'local';
                        if (isBoardRoom) {
                          var desired =
                              session.allocations[participantId] ??
                              const <String>{};
                          desired = <String>{...desired};
                          for (final object in objects) {
                            if (delta > 0) {
                              desired.add(object.id);
                            } else {
                              desired.remove(object.id);
                            }
                          }
                          if (desired.length > session.maxVotesPerParticipant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Vote limit reached.'),
                              ),
                            );
                            return;
                          }
                          final roomId = collaboration.roomId;
                          if (roomId == null || session.sessionId.isEmpty) {
                            return;
                          }
                          await enqueueVotingBallot(
                            ref,
                            roomId: roomId,
                            boardId: board.id,
                            sessionId: session.sessionId,
                            uid: participantId,
                            choices: desired,
                          );
                          await ref
                              .read(votingSyncServiceProvider)
                              ?.flush(DateTime.now());
                          final repository = ref.read(
                            canvasBoardRepositoryProvider,
                          );
                          if (repository
                              is CollaborationCanvasBoardRepository) {
                            await repository.applyLocalBallot(
                              board.id,
                              uid: participantId,
                              sessionId: session.sessionId,
                              objectIds: desired,
                            );
                          }
                          ref.invalidate(projectCanvasBoardProvider(boardName));
                          ref.invalidate(
                            projectCanvasBoardsProvider(boardName),
                          );
                          return;
                        }
                        var nextSession = session;
                        for (final object in objects) {
                          nextSession = nextSession.changeVote(
                            participantId: participantId,
                            objectId: object.id,
                            add: delta > 0,
                          );
                        }
                        if (nextSession == session) {
                          final message = delta > 0
                              ? session.hasVote(participantId, objects.first.id)
                                    ? 'Vote already added to this object.'
                                    : 'Vote limit reached.'
                              : 'No vote to remove.';
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                          return;
                        }
                        await execute(
                          _withVotingSession(
                            board,
                            nextSession,
                            DateTime.now(),
                          ),
                        );
                      },
                onCanvasImageImport: () async {
                  final repository = await ref.read(
                    nodeAttachmentRepositoryProvider.future,
                  );
                  final payload = await MediaFileImportService(
                    repository: repository,
                    picker: const FilePickerMediaFilePicker(),
                  ).pickImage();
                  return payload == null
                      ? null
                      : CanvasImageSource(
                          attachmentId: payload.attachmentId,
                          fileName: payload.fileName,
                          mimeType: payload.mimeType,
                          byteLength: payload.byteLength ?? 0,
                        );
                },
                loadCanvasAttachmentBytes: (attachmentId) async {
                  final repository = await ref.read(
                    nodeAttachmentRepositoryProvider.future,
                  );
                  return repository.readBytes(attachmentId);
                },
              ),
            ),
            if (board.workshopSession.activeStage case final stage?)
              Positioned(
                key: const ValueKey('workspace-workshop-stage-banner'),
                top: 12,
                left: 12,
                right: 260,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            stage.contributionsPrivate &&
                                    !board.workshopSession.revealedStageIds
                                        .contains(stage.id)
                                ? Icons.visibility_off_outlined
                                : Icons.flag_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stage ${board.workshopSession.activeStageIndex + 1}/${board.workshopSession.agenda.length}: ${stage.title}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                if (stage.instructions.isNotEmpty)
                                  Text(
                                    stage.instructions,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          if (board.workshopSession.awaitingAdvance &&
                              canControlWorkshop) ...[
                            const SizedBox(width: 12),
                            FilledButton.tonal(
                              key: const ValueKey(
                                'workspace-workshop-confirm-advance',
                              ),
                              onPressed: board.workshopSession.isLastStage
                                  ? () => unawaited(
                                      handleWorkshopAction(
                                        _WorkspaceWorkshopAction.end,
                                      ),
                                    )
                                  : () => unawaited(
                                      handleWorkshopAction(
                                        _WorkspaceWorkshopAction.advanceStage,
                                      ),
                                    ),
                              child: Text(
                                board.workshopSession.isLastStage
                                    ? 'End workshop'
                                    : 'Next stage',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: Card(
                margin: EdgeInsets.zero,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (board.workshopSession.isActive)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              board.workshopSession.status ==
                                      CanvasWorkshopStatus.paused
                                  ? Icons.pause_circle_outline
                                  : Icons.timer_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _workshopTime(board.workshopSession),
                              key: const ValueKey('workspace-workshop-timer'),
                            ),
                          ],
                        ),
                      ),
                    PopupMenuButton<_WorkspaceWorkshopAction>(
                      key: const ValueKey('workspace-workshop-menu'),
                      tooltip: 'Workshop controls',
                      icon: Icon(
                        board.workshopSession.isActive
                            ? Icons.groups
                            : Icons.groups_outlined,
                      ),
                      onSelected: (action) =>
                          unawaited(handleWorkshopAction(action)),
                      itemBuilder: (context) => [
                        if (!board.workshopSession.isActive ||
                            !board.workshopSession.hasAgenda)
                          PopupMenuItem(
                            value: _WorkspaceWorkshopAction.start,
                            enabled: canControlWorkshop,
                            child: Text(
                              board.workshopSession.isActive
                                  ? 'Restart workshop'
                                  : 'Start workshop',
                            ),
                          ),
                        if (!board.workshopSession.isActive)
                          PopupMenuItem(
                            key: const ValueKey(
                              'workspace-workshop-start-facilitated',
                            ),
                            value: _WorkspaceWorkshopAction.startFacilitated,
                            enabled: canControlWorkshop,
                            child: const Text('Start facilitated workshop'),
                          ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.pause,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.status ==
                                  CanvasWorkshopStatus.running,
                          child: const Text('Pause'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.resume,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.status ==
                                  CanvasWorkshopStatus.paused,
                          child: const Text('Resume'),
                        ),
                        if (board.workshopSession.hasAgenda &&
                            board.workshopSession.isActive) ...[
                          PopupMenuItem(
                            value: _WorkspaceWorkshopAction.advanceStage,
                            enabled:
                                canControlWorkshop &&
                                !board.workshopSession.isLastStage,
                            child: const Text('Advance stage'),
                          ),
                          PopupMenuItem(
                            value: _WorkspaceWorkshopAction.restartStage,
                            enabled: canControlWorkshop,
                            child: const Text('Restart stage'),
                          ),
                          PopupMenuItem(
                            value: _WorkspaceWorkshopAction.skipStage,
                            enabled:
                                canControlWorkshop &&
                                !board.workshopSession.isLastStage,
                            child: const Text('Skip stage'),
                          ),
                          PopupMenuItem(
                            key: const ValueKey(
                              'workspace-workshop-reveal-stage-item',
                            ),
                            value: _WorkspaceWorkshopAction.revealStage,
                            enabled:
                                canControlWorkshop &&
                                board.workshopSession.activeStage?.type ==
                                    CanvasWorkshopStageType.brainstorm &&
                                board.workshopSession.activeStage != null &&
                                !board.workshopSession.revealedStageIds
                                    .contains(
                                      board.workshopSession.activeStage!.id,
                                    ),
                            child: const Text('Reveal contributions'),
                          ),
                        ],
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.extend1,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.isActive,
                          child: const Text('Extend 1 minute'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.extend5,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.isActive,
                          child: const Text('Extend 5 minutes'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.extend10,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.isActive,
                          child: const Text('Extend 10 minutes'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.participants,
                          child: Text(
                            'Participants (${board.workshopSession.participantIds.length})',
                          ),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.end,
                          enabled:
                              canControlWorkshop &&
                              board.workshopSession.isActive,
                          child: const Text('End workshop'),
                        ),
                        PopupMenuItem(
                          value: _WorkspaceWorkshopAction.summary,
                          enabled: board.workshopSession.summary != null,
                          child: const Text('Show summary'),
                        ),
                      ],
                    ),
                    if (canReact && board.workshopSession.isActive)
                      PopupMenuButton<String>(
                        key: const ValueKey('workspace-workshop-reactions'),
                        tooltip: 'React',
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onSelected: (emoji) => unawaited(
                          collaborationNotifier.broadcastReaction(emoji),
                        ),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: '👍', child: Text('👍 Like')),
                          PopupMenuItem(value: '❤️', child: Text('❤️ Love')),
                          PopupMenuItem(
                            value: '🎉',
                            child: Text('🎉 Celebrate'),
                          ),
                          PopupMenuItem(value: '💡', child: Text('💡 Idea')),
                          PopupMenuItem(value: '❓', child: Text('❓ Question')),
                        ],
                      ),
                    if (isBoardRoom &&
                        board.workshopSession.isActive &&
                        canControlWorkshop)
                      PopupMenuButton<String?>(
                        key: const ValueKey('workspace-workshop-presenter'),
                        tooltip: 'Choose presenter',
                        icon: const Icon(Icons.present_to_all),
                        onSelected: (uid) => unawaited(
                          execute(
                            _workshop.setPresenter(board, uid, DateTime.now()),
                          ),
                        ),
                        itemBuilder: (context) => [
                          const PopupMenuItem<String?>(
                            value: null,
                            child: Text('No presenter'),
                          ),
                          for (final member in collaboration.members)
                            PopupMenuItem<String?>(
                              value: member.uid,
                              child: Text(member.displayName),
                            ),
                        ],
                      ),
                    if (isBoardRoom &&
                        board.workshopSession.isActive &&
                        presenterUid != null &&
                        presenterUid != collaboration.localUserId)
                      IconButton(
                        key: const ValueKey('workspace-follow-presenter'),
                        tooltip: _followingPresenterUid == presenterUid
                            ? 'Stop following presenter'
                            : 'Follow presenter',
                        icon: Icon(
                          _followingPresenterUid == presenterUid
                              ? Icons.link_off
                              : Icons.center_focus_strong,
                        ),
                        onPressed: () {
                          final follow = _followingPresenterUid != presenterUid;
                          setState(() {
                            _followingPresenterUid = follow
                                ? presenterUid
                                : null;
                          });
                          _canvasKey(board.id).currentState?.followCollaborator(
                            follow ? presenterUid : null,
                          );
                        },
                      ),
                    if (isBoardRoom)
                      ActionChip(
                        key: const ValueKey('workspace-board-shared-chip'),
                        avatar: Icon(
                          collaboration.isConnected
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                        label: Text(
                          '${collaboration.currentRole?.name ?? 'member'} · ${collaboration.members.length}',
                        ),
                        onPressed: _isSharingBoard
                            ? null
                            : () => unawaited(_shareBoard(board)),
                      )
                    else
                      IconButton(
                        key: const ValueKey('workspace-share-board'),
                        tooltip: 'Share board',
                        onPressed: _isSharingBoard || board.isArchived
                            ? null
                            : () => unawaited(_shareBoard(board)),
                        icon: _isSharingBoard
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ios_share_outlined),
                      ),
                    if (_nestedBoardHistory.isNotEmpty)
                      IconButton(
                        key: const ValueKey('workspace-nested-board-back'),
                        tooltip: 'Kembali ke parent board',
                        onPressed: _backFromNestedBoard,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    IconButton(
                      key: const ValueKey('workspace-create-nested-board'),
                      tooltip: 'Nested board',
                      onPressed: !canEditBoard || board.isArchived
                          ? null
                          : () => unawaited(_createNestedBoard(board, boards)),
                      icon: const Icon(Icons.account_tree_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('workspace-board-dashboard-button'),

                      tooltip: 'Manage project boards',
                      icon: const Icon(Icons.dashboard_outlined),
                      onPressed: !canEditBoard
                          ? null
                          : () => unawaited(
                              _showBoardDashboard(
                                workspaceName: boardName,
                                currentBoard: board,
                                initialBoards: boards,
                              ),
                            ),
                    ),
                    PopupMenuButton<_WorkspaceBoardTransferAction>(
                      key: const ValueKey('workspace-board-transfer-menu'),
                      tooltip: 'Import or export board',
                      icon: const Icon(Icons.import_export_rounded),
                      onSelected: (action) {
                        if (!canEditBoard &&
                            action == _WorkspaceBoardTransferAction.import) {
                          return;
                        }
                        switch (action) {
                          case _WorkspaceBoardTransferAction.import:
                            unawaited(_importBoardPackage(boardName));
                          case _WorkspaceBoardTransferAction.export:
                            unawaited(
                              _exportBoardPackage(workshopVisibleBoard),
                            );
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          key: const ValueKey('workspace-board-import'),
                          value: _WorkspaceBoardTransferAction.import,
                          enabled: canEditBoard,
                          child: const Text('Import board package'),
                        ),
                        const PopupMenuItem(
                          key: ValueKey('workspace-board-export'),
                          value: _WorkspaceBoardTransferAction.export,
                          child: Text('Export board package'),
                        ),
                      ],
                    ),
                    IconButton(
                      key: const ValueKey('workspace-canvas-activity-button'),
                      tooltip: 'Canvas activity',
                      icon: Badge(
                        isLabelVisible: board.activity.isNotEmpty,
                        label: Text('${board.activity.length.clamp(0, 99)}'),
                        child: const Icon(Icons.history_rounded),
                      ),
                      onPressed: () => unawaited(_showActivityHistory(board)),
                    ),
                    if (board.votingSession.isActive)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          '${board.votingSession.remainingVotesFor(isBoardRoom ? collaboration.localUserId : 'local')} votes left',
                          key: const ValueKey('workspace-voting-remaining'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    PopupMenuButton<_WorkspaceCanvasVotingAction>(
                      key: const ValueKey('workspace-canvas-voting-menu'),
                      tooltip: 'Voting session',
                      icon: Icon(
                        board.votingSession.isActive
                            ? Icons.how_to_vote
                            : Icons.how_to_vote_outlined,
                      ),
                      onSelected: (action) {
                        if (action != _WorkspaceCanvasVotingAction.results &&
                            !canControlWorkshop) {
                          return;
                        }
                        switch (action) {
                          case _WorkspaceCanvasVotingAction.start:
                            unawaited(_startVoting(board, execute));
                          case _WorkspaceCanvasVotingAction.end:
                            unawaited(
                              execute(
                                _withVotingSession(
                                  board,
                                  board.votingSession.end(),
                                  DateTime.now(),
                                ),
                              ),
                            );
                          case _WorkspaceCanvasVotingAction.reveal:
                            unawaited(
                              execute(
                                _withVotingSession(
                                  board,
                                  board.votingSession.revealResults(),
                                  DateTime.now(),
                                ),
                              ),
                            );
                          case _WorkspaceCanvasVotingAction.reset:
                            unawaited(
                              execute(
                                _withVotingSession(
                                  board,
                                  board.votingSession.reset(),
                                  DateTime.now(),
                                ),
                              ),
                            );
                          case _WorkspaceCanvasVotingAction.results:
                            if (board.votingSession.resultsRevealed) {
                              unawaited(_showVotingResults(board));
                            }
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          key: const ValueKey('workspace-voting-start'),
                          value: _WorkspaceCanvasVotingAction.start,
                          enabled: canControlWorkshop,
                          child: Text(
                            board.votingSession.isActive
                                ? 'Restart voting'
                                : 'Start voting',
                          ),
                        ),
                        PopupMenuItem(
                          key: const ValueKey('workspace-voting-end'),
                          value: _WorkspaceCanvasVotingAction.end,
                          enabled:
                              canControlWorkshop &&
                              board.votingSession.isActive,
                          child: const Text('End voting'),
                        ),
                        PopupMenuItem(
                          key: const ValueKey('workspace-voting-reveal'),
                          value: _WorkspaceCanvasVotingAction.reveal,
                          enabled:
                              canControlWorkshop &&
                              board.votingSession.status !=
                                  CanvasVotingStatus.inactive &&
                              board.votingSession.resultsConcealed,
                          child: const Text('Reveal results'),
                        ),
                        PopupMenuItem(
                          key: const ValueKey('workspace-voting-results'),
                          value: _WorkspaceCanvasVotingAction.results,
                          enabled: board.votingSession.resultsRevealed,
                          child: const Text('Show results'),
                        ),
                        PopupMenuItem(
                          key: const ValueKey('workspace-voting-reset'),
                          value: _WorkspaceCanvasVotingAction.reset,
                          enabled:
                              canControlWorkshop &&
                              (board.votingSession.status !=
                                      CanvasVotingStatus.inactive ||
                                  board.votingSession.allocations.isNotEmpty),
                          child: const Text('Reset voting'),
                        ),
                      ],
                    ),
                    PopupMenuButton<CanvasProjectTemplate>(
                      key: const ValueKey('workspace-canvas-template-menu'),
                      tooltip: 'Board templates',
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      enabled: canEditBoard,
                      onSelected: (template) => unawaited(
                        execute(
                          board.addProjectTemplate(
                            template,
                            now: DateTime.now(),
                          ),
                        ),
                      ),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          key: ValueKey('workspace-template-project-plan'),
                          value: CanvasProjectTemplate.projectPlan,
                          child: Text('Project planning'),
                        ),
                        PopupMenuItem(
                          key: ValueKey('workspace-template-brainstorm'),
                          value: CanvasProjectTemplate.brainstorm,
                          child: Text('Brainstorm'),
                        ),
                        PopupMenuItem(
                          key: ValueKey('workspace-template-kanban'),
                          value: CanvasProjectTemplate.kanban,
                          child: Text('Kanban'),
                        ),
                        PopupMenuItem(
                          key: ValueKey('workspace-template-retrospective'),
                          value: CanvasProjectTemplate.weeklyPlanner,
                          child: Text('Retrospective'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (isBoardRoom && collaboration.recentReactions.isNotEmpty)
              Positioned(
                left: 24,
                bottom: 24,
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final reaction in collaboration.recentReactions)
                      Chip(
                        key: ValueKey('workshop-reaction-${reaction.id}'),
                        label: Text(reaction.emoji),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

String _shortBoardDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _canvasActivityTimestamp(DateTime value) =>
    '${_shortBoardDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

IconData _canvasActivityIcon(CanvasActivityType type) => switch (type) {
  CanvasActivityType.objectsAdded => Icons.add_box_outlined,
  CanvasActivityType.objectsUpdated => Icons.edit_outlined,
  CanvasActivityType.objectsDeleted => Icons.delete_outline,
  CanvasActivityType.votingStarted => Icons.how_to_vote_outlined,
  CanvasActivityType.votingEnded => Icons.stop_circle_outlined,
  CanvasActivityType.votingReset => Icons.restart_alt_rounded,
  CanvasActivityType.votesChanged => Icons.thumb_up_alt_outlined,
  CanvasActivityType.boardRenamed => Icons.drive_file_rename_outline,
  CanvasActivityType.boardDuplicated => Icons.copy_outlined,
  CanvasActivityType.boardArchived => Icons.archive_outlined,
  CanvasActivityType.boardRestored => Icons.unarchive_outlined,
  CanvasActivityType.boardImported => Icons.file_download_outlined,
  CanvasActivityType.workshopStarted => Icons.play_circle_outline,
  CanvasActivityType.workshopPaused => Icons.pause_circle_outline,
  CanvasActivityType.workshopResumed => Icons.play_arrow_rounded,
  CanvasActivityType.workshopStageChanged => Icons.skip_next_outlined,
  CanvasActivityType.workshopStageRevealed => Icons.visibility_outlined,
  CanvasActivityType.workshopEnded => Icons.flag_outlined,
  CanvasActivityType.presenterChanged => Icons.co_present_outlined,
  CanvasActivityType.assistantApplied => Icons.auto_awesome_outlined,
};

class _TemplateGalleryDialog extends StatefulWidget {
  const _TemplateGalleryDialog({
    required this.builtIns,
    required this.userTemplates,
    required this.sourceBoards,
  });

  final List<BuiltInCanvasBoardTemplate> builtIns;
  final List<_UserTemplateGalleryChoice> userTemplates;
  final Map<String, CanvasBoard> sourceBoards;

  @override
  State<_TemplateGalleryDialog> createState() => _TemplateGalleryDialogState();
}

class _TemplateGalleryDialogState extends State<_TemplateGalleryDialog> {
  String _query = '';
  _TemplateGalleryChoice? _selected;

  @override
  Widget build(BuildContext context) {
    final choices = <_TemplateGalleryChoice>[
      ...widget.builtIns.map(_BuiltInTemplateGalleryChoice.new),
      ...widget.userTemplates,
    ].where((choice) => choice.name.toLowerCase().contains(_query)).toList();
    final selected = _selected;
    final selectedObjects = switch (selected) {
      _BuiltInTemplateGalleryChoice(:final template) => template.objects,
      _UserTemplateGalleryChoice(:final template) =>
        widget.sourceBoards[template.id]?.objects ?? const <CanvasObject>[],
      null => const <CanvasObject>[],
    }.where((object) => object.isVisible).toList(growable: false);
    int objectCount(_TemplateGalleryChoice choice) => switch (choice) {
      _BuiltInTemplateGalleryChoice(:final template) => template.objects.length,
      _UserTemplateGalleryChoice(:final template) =>
        widget.sourceBoards[template.id]?.objects.length ?? 0,
    };
    return AlertDialog(
      key: const ValueKey('workspace-template-gallery'),
      title: const Text('Pilih template'),
      content: SizedBox(
        width: 680,
        height: 520,
        child: Column(
          children: [
            Semantics(
              label: 'Search board templates',
              textField: true,
              child: TextField(
                key: const ValueKey('workspace-template-search'),
                decoration: const InputDecoration(
                  labelText: 'Cari template',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.toLowerCase()),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final choice in choices)
                      Semantics(
                        label: 'Template ${choice.name}',
                        button: true,
                        child: Card(
                          key: choice is _BuiltInTemplateGalleryChoice
                              ? ValueKey(
                                  'workspace-template-built-in-${choice.template.template.name}',
                                )
                              : ValueKey(
                                  'workspace-template-user-${(choice as _UserTemplateGalleryChoice).template.id}',
                                ),
                          child: ListTile(
                            title: Text(choice.name),
                            subtitle: Text('${objectCount(choice)} objects'),
                            selected: identical(selected, choice),
                            onTap: () => setState(() => _selected = choice),
                          ),
                        ),
                      ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Preview ${selected.name}',
                        child: SizedBox(
                          key: const ValueKey('workspace-template-preview'),
                          height: 140,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _CanvasBoardPreviewPainter(
                                    objects: selectedObjects,
                                    colorScheme: Theme.of(context).colorScheme,
                                  ),
                                ),
                              ),
                              for (final object in selectedObjects.take(3))
                                if (object.payload['text']
                                    case final String text)
                                  Text(text),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: selected is _UserTemplateGalleryChoice
              ? ValueKey('workspace-template-use-${selected.template.id}')
              : const ValueKey('workspace-template-use-built-in'),
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
          child: const Text('Gunakan template'),
        ),
      ],
    );
  }
}

class _CanvasBoardPreview extends StatelessWidget {
  const _CanvasBoardPreview({required this.board});

  final CanvasBoard board;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: ValueKey('workspace-board-preview-${board.id}'),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: CustomPaint(
      painter: _CanvasBoardPreviewPainter(
        objects: board.objects.where((object) => object.isVisible).toList(),
        colorScheme: Theme.of(context).colorScheme,
      ),
    ),
  );
}

class _CanvasBoardPreviewPainter extends CustomPainter {
  const _CanvasBoardPreviewPainter({
    required this.objects,
    required this.colorScheme,
  });

  final List<CanvasObject> objects;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) {
      final paint = Paint()
        ..color = colorScheme.outlineVariant
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(size.width * 0.3, size.height * 0.5),
        Offset(size.width * 0.7, size.height * 0.5),
        paint,
      );
      return;
    }
    final left = objects.map((object) => object.geometry.x).reduce(math.min);
    final top = objects.map((object) => object.geometry.y).reduce(math.min);
    final right = objects
        .map((object) => object.geometry.x + object.geometry.width)
        .reduce(math.max);
    final bottom = objects
        .map((object) => object.geometry.y + object.geometry.height)
        .reduce(math.max);
    final contentWidth = math.max(right - left, 1.0);
    final contentHeight = math.max(bottom - top, 1.0);
    final scale = math.min(
      (size.width - 8) / contentWidth,
      (size.height - 8) / contentHeight,
    );
    for (final object in objects.take(80)) {
      final geometry = object.geometry;
      final rect = Rect.fromLTWH(
        4 + (geometry.x - left) * scale,
        4 + (geometry.y - top) * scale,
        math.max(geometry.width * scale, 2),
        math.max(geometry.height * scale, 2),
      );
      final paint = Paint()
        ..color = switch (object.type) {
          CanvasObjectType.frame => colorScheme.primaryContainer,
          CanvasObjectType.stickyNote => colorScheme.tertiaryContainer,
          CanvasObjectType.connector => colorScheme.outline,
          _ => colorScheme.secondaryContainer,
        }
        ..style = object.type == CanvasObjectType.connector
            ? PaintingStyle.stroke
            : PaintingStyle.fill
        ..strokeWidth = 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasBoardPreviewPainter oldDelegate) =>
      !const ListEquality<CanvasObject>().equals(
        oldDelegate.objects,
        objects,
      ) ||
      oldDelegate.colorScheme != colorScheme;
}

IconData _workspaceTypeIcon(WorkspaceContextType type) {
  return switch (type) {
    WorkspaceContextType.project => Icons.account_tree_outlined,
    WorkspaceContextType.area => Icons.category_outlined,
    WorkspaceContextType.daily => Icons.today_outlined,
  };
}

class _WorkspaceDetailHeader extends ConsumerWidget {
  const _WorkspaceDetailHeader({required this.workspace});

  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final health = buildWorkspaceHealth(workspace, today);
    final timeline = buildWorkspaceTimeline(workspace, today);
    final goals = buildWorkspaceGoalSummary(workspace, today);
    final relationships = buildWorkspaceRelationshipSummary(
      workspace,
      workspace.nodes,
    );
    final nextActions = buildWorkspaceNextActions(workspace, today);
    final recommendations = buildWorkspaceRecommendations(
      workspace,
      today,
      relationships,
    );
    final completion = (workspace.completionRate * 100).round();
    final progress = (health.progress * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppDesignTokens.of(context).radiusPage,
            ),
            side: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _workspaceTypeIcon(workspace.type),
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  _HeaderChip(
                    icon: Icons.monitor_heart_outlined,
                    label: health.status.label,
                  ),
                  const SizedBox(width: 8),
                  _HeaderChip(
                    icon: Icons.schedule_outlined,
                    label: workspaceLastActivityLabel(
                      health.lastActivity,
                      today,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeaderChip(
                    icon: Icons.radio_button_checked,
                    label: '${health.active} active',
                  ),
                  _HeaderChip(
                    icon: Icons.check_circle_outline,
                    label: '${health.done} done',
                  ),
                  _HeaderChip(
                    icon: Icons.warning_amber_outlined,
                    label: '${health.overdue} overdue',
                  ),
                  _HeaderChip(
                    icon: Icons.priority_high_outlined,
                    label: '${health.highPriority} high',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: health.progress.clamp(0, 1).toDouble(),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$completion% complete • $progress% average progress',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go(_graphUrl(workspace)),
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Graph'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go(_insightsUrl(workspace)),
                    icon: const Icon(Icons.bar_chart_outlined, size: 16),
                    label: const Text('Insights'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final markdown = exportWorkspaceMarkdown(
                        workspace: workspace,
                        today: today,
                        health: health,
                        timeline: timeline,
                        goals: goals,
                        relationships: relationships,
                        nextActions: nextActions,
                        recommendations: recommendations,
                      );
                      await Clipboard.setData(ClipboardData(text: markdown));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Workspace report copied'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('Copy report'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _graphUrl(WorkspaceContext workspace) {
  return Uri(
    path: '/graph',
    queryParameters: {
      if (workspace.type == WorkspaceContextType.project)
        'project': workspace.name,
      if (workspace.type == WorkspaceContextType.area) 'area': workspace.name,
    },
  ).toString();
}

String _insightsUrl(WorkspaceContext workspace) {
  return Uri(
    path: '/insights',
    queryParameters: {
      if (workspace.type == WorkspaceContextType.project)
        'project': workspace.name,
      if (workspace.type == WorkspaceContextType.area) 'area': workspace.name,
    },
  ).toString();
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}

// ---------------------------------------------------------------------------
// LIST VIEW
// ---------------------------------------------------------------------------

class _WorkspaceListView extends StatelessWidget {
  const _WorkspaceListView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = workspace.activeNodes
        .where((n) => !n.isDone && n.status != NodeStatus.done)
        .toList();
    final completed = workspace.activeNodes
        .where((n) => n.isDone || n.status == NodeStatus.done)
        .toList();

    if (workspace.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('No tasks yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add tasks to this workspace from the calendar',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats row
        _StatsRow(workspace: workspace),
        const SizedBox(height: 20),

        if (completed.isNotEmpty) ...[
          Text(
            'Completed (${completed.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppSemanticColors.of(context).success,
            ),
          ),
          const SizedBox(height: 8),
          ...completed.map((node) => _TaskListTile(node: node)),
          const SizedBox(height: 20),
        ],

        if (active.isNotEmpty) ...[
          Text(
            'Active (${active.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...active.map((node) => _TaskListTile(node: node)),
        ],

        const SizedBox(height: 20),
        _WorkspaceDrillPanels(workspace: workspace),
      ],
    );
  }
}

class _WorkspaceDrillPanels extends StatelessWidget {
  const _WorkspaceDrillPanels({required this.workspace});

  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final overdue = workspace.activeNodes
        .where((node) {
          final due = node.dueDate;
          return due != null &&
              due.dateOnly.isBefore(today.dateOnly) &&
              !node.isDone &&
              node.status != NodeStatus.done;
        })
        .toList(growable: false);
    final high = workspace.activeNodes
        .where(
          (node) =>
              node.priority.index >= NodePriority.high.index &&
              !node.isDone &&
              node.status != NodeStatus.done,
        )
        .toList(growable: false);
    final waiting = workspace.activeNodes
        .where((node) => node.status == NodeStatus.waiting)
        .toList(growable: false);
    final goals = workspace.activeNodes
        .where((node) => node.type == NodeType.goal)
        .toList(growable: false);

    return Column(
      children: [
        _DrillExpansion(title: 'Overdue nodes', nodes: overdue),
        _DrillExpansion(title: 'High-priority nodes', nodes: high),
        _DrillExpansion(title: 'Waiting / blocked nodes', nodes: waiting),
        _DrillExpansion(title: 'Goals', nodes: goals),
      ],
    );
  }
}

class _DrillExpansion extends StatelessWidget {
  const _DrillExpansion({required this.title, required this.nodes});

  final String title;
  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      title: Text('$title (${nodes.length})'),
      children: nodes.isEmpty
          ? [const ListTile(dense: true, title: Text('No items'))]
          : [for (final node in nodes) _TaskListTile(node: node)],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final completion = (workspace.completionRate * 100).round();
    final progress = (workspace.averageProgress * 100).round();

    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          side: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: 'Total',
              value: '${workspace.nodes.length}',
              icon: Icons.layers_outlined,
            ),
            _StatItem(
              label: 'Active',
              value: '${workspace.activeNodeCount}',
              icon: Icons.radio_button_checked,
            ),
            _StatItem(
              label: 'Done',
              value: '$completion%',
              icon: Icons.check_circle_outlined,
            ),
            _StatItem(
              label: 'Progress',
              value: '$progress%',
              icon: Icons.trending_up_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _TaskListTile extends StatelessWidget {
  const _TaskListTile({required this.node});
  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isDone = node.isDone || node.status == NodeStatus.done;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
        ),
        leading: Icon(
          isDone ? Icons.check_circle : _statusIcon(node.status),
          color: isDone
              ? semantic.success
              : _statusColor(node.status, theme, semantic),
          size: 20,
        ),
        title: Text(
          node.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isDone
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text(
          [
            node.type.label,
            dayKey(node.day),
            if (node.dueDate != null) 'Due ${dayKey(node.dueDate!)}',
            if (node.priority != NodePriority.none) node.priority.label,
          ].join(' ·'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: node.priority.index >= NodePriority.high.index
            ? Icon(Icons.flag, size: 16, color: theme.colorScheme.error)
            : null,
        onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KANBAN VIEW
// ---------------------------------------------------------------------------

/// Column definitions for the Kanban board.
enum _KanbanColumn {
  inbox('Inbox', NodeStatus.inbox, Icons.inbox_outlined),
  open('To Do', NodeStatus.open, Icons.radio_button_unchecked),
  next('Next', NodeStatus.next, Icons.redo_rounded),
  planned('Planned', NodeStatus.planned, Icons.event_outlined),
  doing('In Progress', NodeStatus.doing, Icons.sync_outlined),
  waiting('Waiting', NodeStatus.waiting, Icons.hourglass_empty_outlined),
  someday('Someday', NodeStatus.someday, Icons.next_plan_outlined),
  done('Done', NodeStatus.done, Icons.check_circle_outlined);

  const _KanbanColumn(this.label, this.targetStatus, this.icon);
  final String label;
  final NodeStatus targetStatus;
  final IconData icon;
}

class _WorkspaceKanbanView extends ConsumerWidget {
  const _WorkspaceKanbanView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = workspace.activeNodes;

    // Bucket nodes into columns
    final buckets = <_KanbanColumn, List<MindmapNode>>{
      for (final col in _KanbanColumn.values) col: [],
    };

    for (final node in active) {
      if (node.isDone || node.status == NodeStatus.done) {
        buckets[_KanbanColumn.done]!.add(node);
      } else {
        final column = _KanbanColumn.values.firstWhere(
          (item) => item.targetStatus == node.status,
          orElse: () => _KanbanColumn.open,
        );
        buckets[column]!.add(node);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = math.max(240.0, (constraints.maxWidth - 72) / 5);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final col in _KanbanColumn.values) ...[
                _KanbanColumnWidget(
                  column: col,
                  nodes: buckets[col]!,
                  width: columnWidth,
                ),
                if (col != _KanbanColumn.done) const SizedBox(width: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KanbanColumnWidget extends ConsumerWidget {
  const _KanbanColumnWidget({
    required this.column,
    required this.nodes,
    required this.width,
  });

  final _KanbanColumn column;
  final List<MindmapNode> nodes;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) async {
        final nodeId = details.data;
        final repo = ref.read(mindmapRepositoryProvider);
        final allNodes = await repo.listNodes();
        final node = allNodes.firstWhere(
          (n) => n.id == nodeId,
          orElse: () => throw StateError('Node $nodeId not found'),
        );

        final newStatus = column.targetStatus;
        final isDone = newStatus == NodeStatus.done;

        final updated = node.copyWith(
          status: newStatus,
          isDone: isDone,
          progress: isDone
              ? 1.0
              : (newStatus == NodeStatus.doing
                    ? math.max(node.progress, 0.1)
                    : node.progress),
          updatedAt: DateTime.now(),
        );

        await repo.saveNode(updated);
        invalidateMindmapState(ref, day: node.day);
      },
      builder: (context, candidateData, rejectedData) {
        final isAccepting = candidateData.isNotEmpty;

        final tokens = AppDesignTokens.of(context);
        return AnimatedContainer(
          duration: tokens.effectiveDuration(context, tokens.motionFast),
          curve: tokens.motionCurve,
          width: width,
          decoration: BoxDecoration(
            color: isAccepting
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(tokens.radiusContainer),
            border: Border.all(
              color: isAccepting
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: isAccepting ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Column header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _columnHeaderColor(
                    column,
                    theme,
                    semantic,
                  ).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      column.icon,
                      size: 18,
                      color: _columnHeaderColor(column, theme, semantic),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _columnHeaderColor(column, theme, semantic),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _columnHeaderColor(
                          column,
                          theme,
                          semantic,
                        ).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${nodes.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _columnHeaderColor(column, theme, semantic),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Cards
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Drop tasks here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      for (final node in nodes) ...[
                        _KanbanCard(node: node, column: column),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanCard extends ConsumerWidget {
  const _KanbanCard({required this.node, required this.column});

  final MindmapNode node;
  final _KanbanColumn column;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = AppDesignTokens.of(context);

    final card = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    NodeVisuals.icon(node.type),
                    size: 14,
                    color: NodeVisuals.color(context, node.type),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: column == _KanbanColumn.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (node.priority.index >= NodePriority.high.index)
                    Icon(Icons.flag, size: 14, color: theme.colorScheme.error),
                  PopupMenuButton<_KanbanColumn>(
                    tooltip: 'Move ${node.title}',
                    onSelected: (target) async {
                      final isDone = target == _KanbanColumn.done;
                      await ref
                          .read(mindmapRepositoryProvider)
                          .saveNode(
                            node.copyWith(
                              status: target.targetStatus,
                              isDone: isDone,
                              progress: isDone
                                  ? 1
                                  : target == _KanbanColumn.doing
                                  ? math.max(node.progress, 0.1)
                                  : node.progress,
                              updatedAt: DateTime.now(),
                            ),
                          );
                      invalidateMindmapState(ref, day: node.day);
                    },
                    itemBuilder: (context) => [
                      for (final target in _KanbanColumn.values)
                        if (target != column)
                          PopupMenuItem(
                            value: target,
                            child: Text('Move to ${target.label}'),
                          ),
                    ],
                    icon: const Icon(Icons.more_vert, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    dayKey(node.day),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (node.dueDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          dayKey(node.dueDate!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (node.checklist.isNotEmpty) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: node.checklistProgress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<String>(
      data: node.id,
      delay: const Duration(milliseconds: 150),
      feedback: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(tokens.radiusContainer),
        child: SizedBox(width: 250, child: Opacity(opacity: 0.85, child: card)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      child: card,
    );
  }
}

// ---------------------------------------------------------------------------
// GANTT VIEW
// ---------------------------------------------------------------------------

class _WorkspaceGanttView extends StatelessWidget {
  const _WorkspaceGanttView({required this.workspace});
  final WorkspaceContext workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = workspace.activeNodes;

    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.waterfall_chart_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text('No tasks to visualize', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    // Compute timeline range
    DateTime earliest = active.first.day;
    DateTime latest = active.first.day;
    for (final node in active) {
      if (node.day.isBefore(earliest)) earliest = node.day;
      final end = node.dueDate ?? node.day;
      if (end.isAfter(latest)) latest = end;
    }
    // Add padding
    earliest = earliest.subtract(const Duration(days: 7));
    latest = latest.add(const Duration(days: 14));

    final totalDays = latest.difference(earliest).inDays + 1;
    const dayWidth = 40.0;
    const rowHeight = 40.0;
    const labelWidth = 180.0;
    final today = DateTime.now().dateOnly;
    final semantic = AppSemanticColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _GanttLegendItem(
                color: theme.colorScheme.primary,
                label: 'Active',
              ),
              _GanttLegendItem(color: semantic.warning, label: 'In Progress'),
              _GanttLegendItem(color: semantic.success, label: 'Done'),
              _GanttLegendItem(
                color: theme.colorScheme.error,
                label: 'Overdue',
              ),
            ],
          ),
        ),

        // Chart area
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: labelWidth + (totalDays * dayWidth),
                height: (active.length * rowHeight) + 32,
                child: Semantics(
                  label: 'Gantt chart, ${active.length} tasks',
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size.infinite,
                        painter: _GanttChartPainter(
                          nodes: active,
                          earliest: earliest,
                          totalDays: totalDays,
                          dayWidth: dayWidth,
                          rowHeight: rowHeight,
                          labelWidth: labelWidth,
                          today: today,
                          theme: theme,
                          semantic: semantic,
                          textScaler: MediaQuery.textScalerOf(context),
                          textDirection: Directionality.of(context),
                        ),
                      ),
                      Positioned.fill(
                        child: ListView(
                          children: [
                            for (final node in active)
                              Semantics(
                                button: true,
                                label:
                                    '${node.title}, ${dayKey(node.day)} to ${dayKey(node.dueDate ?? node.day)}, ${(node.progress * 100).round()} percent',
                                onTap: () => goToDay(
                                  context,
                                  node.day,
                                  highlightNodeId: node.id,
                                ),
                                child: const SizedBox(height: rowHeight),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GanttLegendItem extends StatelessWidget {
  const _GanttLegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _GanttChartPainter extends CustomPainter {
  _GanttChartPainter({
    required this.nodes,
    required this.earliest,
    required this.totalDays,
    required this.dayWidth,
    required this.rowHeight,
    required this.labelWidth,
    required this.today,
    required this.theme,
    required this.semantic,
    required this.textScaler,
    required this.textDirection,
  });

  final List<MindmapNode> nodes;
  final DateTime earliest;
  final int totalDays;
  final double dayWidth;
  final double rowHeight;
  final double labelWidth;
  final DateTime today;
  final ThemeData theme;
  final AppSemanticColors semantic;
  final TextScaler textScaler;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    const headerHeight = 28.0;
    const chartTop = headerHeight;

    // Draw day headers
    final todayPaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: 0.1);
    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.15)
      ..strokeWidth = 0.5;

    for (var i = 0; i < totalDays; i++) {
      final day = earliest.add(Duration(days: i));
      final x = labelWidth + (i * dayWidth);

      // Today highlight
      if (day.year == today.year &&
          day.month == today.month &&
          day.day == today.day) {
        canvas.drawRect(Rect.fromLTWH(x, 0, dayWidth, size.height), todayPaint);
      }

      // Vertical grid line
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Day label (only show for start-of-week or every 3rd day)
      if (day.weekday == DateTime.monday || i % 3 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${day.day}/${day.month}',
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: dayWidth);
        tp.paint(canvas, Offset(x + 2, 4));
      }
    }

    // Horizontal separator under header
    canvas.drawLine(
      const Offset(0, headerHeight),
      Offset(size.width, headerHeight),
      Paint()..color = theme.dividerColor,
    );

    // Draw task rows
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final y = chartTop + (i * rowHeight);

      // Row separator
      if (i > 0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }

      // Alternating row background
      if (i.isEven) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, rowHeight),
          Paint()
            ..color = theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.15,
            ),
        );
      }

      // Title label (truncated)
      final title = node.title.length > 22
          ? '${node.title.substring(0, 20)}…'
          : node.title;
      final tp = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
        ),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: labelWidth - 16);
      tp.paint(canvas, Offset(8, y + (rowHeight - tp.height) / 2));

      // Bar
      final start = node.day;
      final end = node.dueDate ?? node.day;
      final startOffset = start.difference(earliest).inDays;
      final duration = math.max(1, end.difference(start).inDays + 1);

      final barX = labelWidth + (startOffset * dayWidth) + 2;
      final barWidth = (duration * dayWidth) - 4;
      final barY = y + 8;
      final barHeight = rowHeight - 16;

      final barColor = _barColor(node);
      final barTextColor =
          ThemeData.estimateBrightnessForColor(barColor) == Brightness.dark
          ? theme.colorScheme.surface
          : theme.colorScheme.onSurface;
      final barPaint = Paint()..color = barColor;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(barX, barY, barWidth, barHeight),
        const Radius.circular(6),
      );
      canvas.drawRRect(barRect, barPaint);

      // Bar label
      if (barWidth > 30) {
        final barLabel = TextPainter(
          text: TextSpan(
            text: '${(node.progress * 100).round()}%',
            style: TextStyle(
              fontSize: 9,
              color: barTextColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: barWidth - 8);
        barLabel.paint(
          canvas,
          Offset(barX + 4, barY + (barHeight - barLabel.height) / 2),
        );
      }
    }

    // Today indicator line
    final todayOffset = today.difference(earliest).inDays;
    if (todayOffset >= 0 && todayOffset < totalDays) {
      final todayX = labelWidth + (todayOffset * dayWidth) + (dayWidth / 2);
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        Paint()
          ..color = theme.colorScheme.primary
          ..strokeWidth = 2,
      );
    }
  }

  Color _barColor(MindmapNode node) {
    if (node.isDone || node.status == NodeStatus.done) return semantic.success;
    if (node.dueDate != null && node.dueDate!.isBefore(today) && !node.isDone) {
      return theme.colorScheme.error;
    }
    if (node.status == NodeStatus.doing) return semantic.warning;
    return theme.colorScheme.primary;
  }

  @override
  bool shouldRepaint(covariant _GanttChartPainter oldDelegate) {
    return nodes != oldDelegate.nodes || today != oldDelegate.today;
  }
}

// ---------------------------------------------------------------------------
// SHARED HELPERS
// ---------------------------------------------------------------------------

IconData _statusIcon(NodeStatus status) => switch (status) {
  NodeStatus.inbox => Icons.inbox_outlined,
  NodeStatus.open => Icons.radio_button_unchecked,
  NodeStatus.next => Icons.redo_rounded,
  NodeStatus.planned => Icons.event_outlined,
  NodeStatus.doing => Icons.sync_outlined,
  NodeStatus.waiting => Icons.hourglass_empty_outlined,
  NodeStatus.someday => Icons.next_plan_outlined,
  NodeStatus.done => Icons.check_circle,
};

Color _statusColor(
  NodeStatus status,
  ThemeData theme,
  AppSemanticColors semantic,
) => switch (status) {
  NodeStatus.inbox => theme.colorScheme.tertiary,
  NodeStatus.open => theme.colorScheme.onSurfaceVariant,
  NodeStatus.next => semantic.info,
  NodeStatus.planned => semantic.info,
  NodeStatus.doing => semantic.warning,
  NodeStatus.waiting => theme.colorScheme.secondary,
  NodeStatus.someday => theme.colorScheme.outline,
  NodeStatus.done => semantic.success,
};

Color _columnHeaderColor(
  _KanbanColumn column,
  ThemeData theme,
  AppSemanticColors semantic,
) => switch (column) {
  _KanbanColumn.inbox => theme.colorScheme.tertiary,
  _KanbanColumn.open => theme.colorScheme.primary,
  _KanbanColumn.next => semantic.info,
  _KanbanColumn.planned => semantic.info,
  _KanbanColumn.doing => semantic.warning,
  _KanbanColumn.waiting => theme.colorScheme.secondary,
  _KanbanColumn.someday => theme.colorScheme.outline,
  _KanbanColumn.done => semantic.success,
};
