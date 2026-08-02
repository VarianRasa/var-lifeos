/// Floating Quick Capture Overlay Dock for rapid Life OS node entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../domain/quick_create_command_parser.dart';

final quickCaptureVisibleProvider = StateProvider<bool>((ref) => false);

class QuickCaptureDock extends ConsumerStatefulWidget {
  const QuickCaptureDock({super.key});

  @override
  ConsumerState<QuickCaptureDock> createState() => _QuickCaptureDockState();
}

class _QuickCaptureDockState extends ConsumerState<QuickCaptureDock> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  NodeType _selectedType = NodeType.task;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitNode() async {
    final rawText = _textController.text.trim();
    if (rawText.isEmpty) return;

    final targetDate = ref.read(currentDateProvider);
    final parsedCmd = quickCreateCommandFromQuery(
      rawText,
      today: targetDate,
      defaultDay: targetDate,
    );

    final nodeType = parsedCmd?.type ?? _selectedType;
    final title = parsedCmd?.title ?? rawText;

    final node = MindmapNode.create(
      id: const Uuid().v4(),
      type: nodeType,
      title: title,
      day: targetDate,
      now: DateTime.now(),
    );

    await ref.read(mindmapMutationControllerProvider).saveNode(node);

    _textController.clear();
    ref.read(quickCaptureVisibleProvider.notifier).state = false;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${nodeType.label} "$title" ditambahkan!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final tokens = AppDesignTokens.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          ref.read(quickCaptureVisibleProvider.notifier).state = false;
        },
      },
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: semantic.popover,
                borderRadius: BorderRadius.circular(tokens.radiusContainer),
                border: Border.all(color: semantic.border),
                boxShadow: tokens.shadowHigh,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Quick Capture Dock',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          ref.read(quickCaptureVisibleProvider.notifier).state =
                              false;
                        },
                        tooltip: 'Tutup (Esc)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _TypeChip(
                        type: NodeType.task,
                        label: 'Task',
                        isSelected: _selectedType == NodeType.task,
                        onSelected: () =>
                            setState(() => _selectedType = NodeType.task),
                      ),
                      _TypeChip(
                        type: NodeType.note,
                        label: 'Note',
                        isSelected: _selectedType == NodeType.note,
                        onSelected: () =>
                            setState(() => _selectedType = NodeType.note),
                      ),
                      _TypeChip(
                        type: NodeType.habit,
                        label: 'Habit',
                        isSelected: _selectedType == NodeType.habit,
                        onSelected: () =>
                            setState(() => _selectedType = NodeType.habit),
                      ),
                      _TypeChip(
                        type: NodeType.goal,
                        label: 'Goal',
                        isSelected: _selectedType == NodeType.goal,
                        onSelected: () =>
                            setState(() => _selectedType = NodeType.goal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onSubmitted: (_) => _submitNode(),
                    decoration: InputDecoration(
                      hintText:
                          'Tulis node... (contoh: "Beli susu @today #task")',
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          tokens.radiusElement,
                        ),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send_rounded, size: 18),
                        onPressed: _submitNode,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.type,
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final NodeType type;
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = NodeVisuals.color(context, type);
    final selectedForeground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: Icon(
        NodeVisuals.icon(type),
        size: 14,
        color: isSelected ? selectedForeground : color,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? selectedForeground : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (_) => onSelected(),
    );
  }
}
