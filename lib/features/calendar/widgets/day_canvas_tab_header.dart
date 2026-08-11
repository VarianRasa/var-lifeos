import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';

class DayCanvasTabHeader extends StatelessWidget {
  const DayCanvasTabHeader({
    required this.boards,
    required this.activeBoardId,
    required this.onSelectBoard,
    required this.onAddBoard,
    this.onRenameBoard,
    this.onDeleteBoard,
    this.onOpenDashboard,
    this.onAssistantRequested,
    this.onVotingRequested,
    this.onWorkshopRequested,
    this.onWorkshopAction,
    this.workshopSession,
    this.workshopTimeString,
    this.onTemplatesRequested,
    this.onActivityHistoryRequested,
    this.onExportRequested,
    this.votingVotesLeft,
    super.key,
  });

  final List<CanvasBoard> boards;
  final String? activeBoardId;
  final ValueChanged<String> onSelectBoard;
  final VoidCallback onAddBoard;
  final ValueChanged<CanvasBoard>? onRenameBoard;
  final ValueChanged<CanvasBoard>? onDeleteBoard;
  final VoidCallback? onOpenDashboard;
  final VoidCallback? onAssistantRequested;
  final VoidCallback? onVotingRequested;
  final VoidCallback? onWorkshopRequested;
  final ValueChanged<String>? onWorkshopAction;
  final CanvasWorkshopSession? workshopSession;
  final String? workshopTimeString;
  final VoidCallback? onTemplatesRequested;
  final VoidCallback? onActivityHistoryRequested;
  final VoidCallback? onExportRequested;
  final int? votingVotesLeft;

  void _showTabMenu(
    BuildContext context,
    Offset globalPosition,
    CanvasBoard board,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(40, 40),
      Offset.zero & overlay.size,
    );

    final isPrimary = board.isPrimaryDayBoard;

    showMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem<String>(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Rename'),
            ],
          ),
        ),
        if (!isPrimary)
          const PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'rename') {
        onRenameBoard?.call(board);
      } else if (value == 'delete') {
        onDeleteBoard?.call(board);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompactScreen = MediaQuery.sizeOf(context).width < 600;

    return Container(
      height: 44,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (onOpenDashboard != null)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                Icons.dashboard_outlined,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: 'All Boards Dashboard',
              onPressed: onOpenDashboard,
            ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: boards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final board = boards[index];
                final isSelected = board.id == activeBoardId;
                return GestureDetector(
                  onSecondaryTapDown: (details) =>
                      _showTabMenu(context, details.globalPosition, board),
                  onLongPressStart: (details) =>
                      _showTabMenu(context, details.globalPosition, board),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                    label: Text(
                      board.title.isEmpty ? 'Canvas ${index + 1}' : board.title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceContainerLow,
                    onSelected: (_) => onSelectBoard(board.id),
                  ),
                );
              },
            ),
          ),
          if (votingVotesLeft != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$votingVotesLeft votes',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          if (isCompactScreen) ...[
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: 'More actions',
              onSelected: (value) {
                switch (value) {
                  case 'ai':
                    onAssistantRequested?.call();
                  case 'voting':
                    onVotingRequested?.call();
                  case 'workshop':
                    onWorkshopRequested?.call();
                  case 'templates':
                    onTemplatesRequested?.call();
                  case 'history':
                    onActivityHistoryRequested?.call();
                  case 'export':
                    onExportRequested?.call();
                }
              },
              itemBuilder: (context) => [
                if (onAssistantRequested != null)
                  const PopupMenuItem(
                    value: 'ai',
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('AI Assistant'),
                      ],
                    ),
                  ),
                if (onVotingRequested != null)
                  const PopupMenuItem(
                    value: 'voting',
                    child: Row(
                      children: [
                        Icon(Icons.how_to_vote_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Live Voting'),
                      ],
                    ),
                  ),
                if (onWorkshopRequested != null)
                  const PopupMenuItem(
                    value: 'workshop',
                    child: Row(
                      children: [
                        Icon(Icons.present_to_all_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Workshop'),
                      ],
                    ),
                  ),
                if (onTemplatesRequested != null)
                  const PopupMenuItem(
                    value: 'templates',
                    child: Row(
                      children: [
                        Icon(Icons.dashboard_customize_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Templates'),
                      ],
                    ),
                  ),
                if (onActivityHistoryRequested != null)
                  const PopupMenuItem(
                    value: 'history',
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Activity History'),
                      ],
                    ),
                  ),
                if (onExportRequested != null)
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        Icon(Icons.file_download_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Export Board'),
                      ],
                    ),
                  ),
              ],
            ),
          ] else ...[
            if (onAssistantRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Canvas AI Assistant',
                onPressed: onAssistantRequested,
              ),
            if (onVotingRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.how_to_vote_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Live Voting',
                onPressed: onVotingRequested,
              ),
            if (onWorkshopAction != null && workshopSession != null) ...[
              if (workshopSession!.isActive && workshopTimeString != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: Text(
                    workshopTimeString!,
                    key: const ValueKey('day-workshop-timer'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                key: const ValueKey('day-workshop-menu'),
                padding: EdgeInsets.zero,
                tooltip: 'Workshop controls',
                icon: Icon(
                  workshopSession!.isActive
                      ? Icons.groups
                      : Icons.groups_outlined,
                  size: 18,
                  color: workshopSession!.isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                onSelected: onWorkshopAction,
                itemBuilder: (context) => [
                  if (!workshopSession!.isActive) ...[
                    const PopupMenuItem(
                      value: 'brainstorm',
                      child: Text('Start brainstorm'),
                    ),
                    const PopupMenuItem(
                      value: 'retrospective',
                      child: Text('Start retrospective'),
                    ),
                    const PopupMenuItem(
                      value: 'decision',
                      child: Text('Start decision'),
                    ),
                  ],
                  PopupMenuItem(
                    value:
                        workshopSession!.status == CanvasWorkshopStatus.paused
                        ? 'resume'
                        : 'pause',
                    enabled: workshopSession!.isActive,
                    child: Text(
                      workshopSession!.status == CanvasWorkshopStatus.paused
                          ? 'Resume'
                          : 'Pause',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'advance',
                    enabled:
                        workshopSession!.isActive &&
                        !workshopSession!.isLastStage,
                    child: const Text('Advance stage'),
                  ),
                  PopupMenuItem(
                    value: 'reveal',
                    enabled:
                        workshopSession!.isActive &&
                        workshopSession!.activeStage?.contributionsPrivate ==
                            true,
                    child: const Text('Reveal contributions'),
                  ),
                  PopupMenuItem(
                    value: 'end',
                    enabled: workshopSession!.isActive,
                    child: const Text('End workshop'),
                  ),
                  PopupMenuItem(
                    value: 'summary',
                    enabled: workshopSession!.summary != null,
                    child: const Text('Show summary'),
                  ),
                ],
              ),
            ] else if (onWorkshopRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.present_to_all_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Workshop Facilitator',
                onPressed: onWorkshopRequested,
              ),
            if (onTemplatesRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.dashboard_customize_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Board Templates',
                onPressed: onTemplatesRequested,
              ),
            if (onActivityHistoryRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Activity History',
                onPressed: onActivityHistoryRequested,
              ),
            if (onExportRequested != null)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  Icons.file_download_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: 'Export/Import Board',
                onPressed: onExportRequested,
              ),
          ],
          const SizedBox(width: 2),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: Icon(
              Icons.add,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: 'Add Board',
            onPressed: onAddBoard,
          ),
        ],
      ),
    );
  }
}
