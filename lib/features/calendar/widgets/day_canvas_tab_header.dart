import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';

class DayCanvasTabHeader extends StatelessWidget {
  const DayCanvasTabHeader({
    required this.boards,
    required this.activeBoardId,
    required this.onSelectBoard,
    required this.onAddBoard,
    this.onAssistantRequested,
    this.onVotingRequested,
    this.onWorkshopRequested,
    super.key,
  });

  final List<CanvasBoard> boards;
  final String? activeBoardId;
  final ValueChanged<String> onSelectBoard;
  final VoidCallback onAddBoard;
  final VoidCallback? onAssistantRequested;
  final VoidCallback? onVotingRequested;
  final VoidCallback? onWorkshopRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 40,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: boards.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final board = boards[index];
                final isSelected = board.id == activeBoardId;
                return ChoiceChip(
                  label: Text(
                    board.title.isEmpty ? 'Canvas ${index + 1}' : board.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerLow,
                  onSelected: (_) => onSelectBoard(board.id),
                );
              },
            ),
          ),
          if (onAssistantRequested != null)
            IconButton(
              icon: Icon(Icons.auto_awesome_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              tooltip: 'Canvas AI Assistant',
              onPressed: onAssistantRequested,
            ),
          if (onVotingRequested != null)
            IconButton(
              icon: Icon(Icons.how_to_vote_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              tooltip: 'Live Voting',
              onPressed: onVotingRequested,
            ),
          if (onWorkshopRequested != null)
            IconButton(
              icon: Icon(Icons.present_to_all_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              tooltip: 'Workshop Presenter',
              onPressed: onWorkshopRequested,
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.add, size: 18, color: colorScheme.onSurfaceVariant),
            tooltip: 'Add Board',
            onPressed: onAddBoard,
          ),
        ],
      ),
    );
  }
}
