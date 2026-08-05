import 'package:flutter/material.dart';

class BoardVotingReactionWidget extends StatefulWidget {
  final int initialVotes;
  final Map<String, int> initialReactions;
  final ValueChanged<int>? onVoteChanged;
  final ValueChanged<String>? onReactionAdded;

  const BoardVotingReactionWidget({
    super.key,
    this.initialVotes = 0,
    this.initialReactions = const {'👍': 0, '❤️': 0, '🚀': 0},
    this.onVoteChanged,
    this.onReactionAdded,
  });

  @override
  State<BoardVotingReactionWidget> createState() =>
      _BoardVotingReactionWidgetState();
}

class _BoardVotingReactionWidgetState
    extends State<BoardVotingReactionWidget> {
  late int _votes;
  late Map<String, int> _reactions;

  @override
  void initState() {
    super.initState();
    _votes = widget.initialVotes;
    _reactions = Map.from(widget.initialReactions);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() => _votes++);
              widget.onVoteChanged?.call(_votes);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_votes',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Row(
            children: _reactions.entries.map((entry) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _reactions[entry.key] = (entry.value) + 1;
                  });
                  widget.onReactionAdded?.call(entry.key);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${entry.key} ${entry.value > 0 ? entry.value : ""}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
