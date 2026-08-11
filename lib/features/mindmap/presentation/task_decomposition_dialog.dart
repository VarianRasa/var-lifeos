import 'package:flutter/material.dart';
import '../data/byok_ai_service.dart';
import '../domain/mindmap_node.dart';
import '../domain/task_decomposition.dart';

Future<List<String>?> showTaskDecompositionDialog(
  BuildContext context, {
  required MindmapNode node,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) => TaskDecompositionDialog(node: node),
  );
}

class TaskDecompositionDialog extends StatefulWidget {
  const TaskDecompositionDialog({super.key, required this.node});

  final MindmapNode node;

  @override
  State<TaskDecompositionDialog> createState() =>
      _TaskDecompositionDialogState();
}

class _TaskDecompositionDialogState extends State<TaskDecompositionDialog> {
  List<DecomposedSubTask> _subTasks = [];
  bool _loadingAi = false;
  bool _isAiGenerated = false;

  @override
  void initState() {
    super.initState();
    _subTasks = decomposeTask(widget.node);
    _attemptAiDecomposition();
  }

  Future<void> _attemptAiDecomposition() async {
    final config = await ByokAiService().loadConfig();
    if (!config.isConfigured) return;

    if (mounted) setState(() => _loadingAi = true);
    try {
      final aiSubtasks = await ByokAiService().decomposeTaskWithAi(
        taskTitle: widget.node.title,
        config: config,
      );
      if (aiSubtasks.isNotEmpty && mounted) {
        setState(() {
          _subTasks = aiSubtasks;
          _isAiGenerated = true;
        });
      }
    } catch (_) {
      // Fallback stays on offline rule-based items
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  void _toggleSelect(int index) {
    setState(() {
      _subTasks[index] = _subTasks[index].copyWith(
        isSelected: !_subTasks[index].isSelected,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _subTasks.where((t) => t.isSelected).length;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI Task Breakdown: ${widget.node.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Select sub-tasks to add to this item\'s checklist:',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_isAiGenerated)
                    const Chip(
                      label: Text(
                        'Live BYOK AI',
                        style: TextStyle(fontSize: 10),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadingAi)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                for (var i = 0; i < _subTasks.length; i++) ...[
                  CheckboxListTile(
                    value: _subTasks[i].isSelected,
                    onChanged: (_) => _toggleSelect(i),
                    dense: true,
                    title: Text(_subTasks[i].title),
                    subtitle: Text('Est: ${_subTasks[i].estimatedMinutes} min'),
                  ),
                ],
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
          onPressed: selectedCount == 0
              ? null
              : () {
                  final result = _subTasks
                      .where((t) => t.isSelected)
                      .map((t) => t.title)
                      .toList();
                  Navigator.of(context).pop(result);
                },
          icon: const Icon(Icons.playlist_add, size: 18),
          label: Text('Add $selectedCount Sub-tasks'),
        ),
      ],
    );
  }
}
