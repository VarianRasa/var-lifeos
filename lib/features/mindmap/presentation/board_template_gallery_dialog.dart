import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/canvas_board.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';

class BoardTemplateGalleryDialog extends StatelessWidget {
  final ValueChanged<CanvasProjectTemplate>? onSelectTemplate;

  const BoardTemplateGalleryDialog({
    super.key,
    this.onSelectTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templates = builtInCanvasBoardTemplates;

    return AlertDialog(
      title: const Text('Template Gallery'),
      content: SizedBox(
        width: 540,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a ready-to-use template for your mindmap canvas:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelectTemplate?.call(t.template);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _iconForTemplate(t.template),
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Contains ${t.objects.length} elements',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  IconData _iconForTemplate(CanvasProjectTemplate template) {
    switch (template) {
      case CanvasProjectTemplate.projectPlan:
        return Icons.assignment_outlined;
      case CanvasProjectTemplate.kanban:
        return Icons.view_kanban_outlined;
      case CanvasProjectTemplate.brainstorm:
        return Icons.lightbulb_outline;
      case CanvasProjectTemplate.contentCalendar:
        return Icons.calendar_today_outlined;
      case CanvasProjectTemplate.weeklyPlanner:
        return Icons.date_range_outlined;
      case CanvasProjectTemplate.researchBoard:
        return Icons.find_in_page_outlined;
      case CanvasProjectTemplate.moodboard:
        return Icons.palette_outlined;
      case CanvasProjectTemplate.goalTracker:
        return Icons.flag_outlined;
    }
  }
}
