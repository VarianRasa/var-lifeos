/// Task auto-decomposition engine for breaking down broad goals and tasks into actionable steps.
library;

import 'mindmap_node.dart';

final class DecomposedSubTask {
  const DecomposedSubTask({
    required this.title,
    this.estimatedMinutes = 30,
    this.isSelected = true,
  });

  final String title;
  final int estimatedMinutes;
  final bool isSelected;

  DecomposedSubTask copyWith({
    String? title,
    int? estimatedMinutes,
    bool? isSelected,
  }) {
    return DecomposedSubTask(
      title: title ?? this.title,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

List<DecomposedSubTask> decomposeTask(MindmapNode node) {
  final title = node.title.trim();
  if (title.isEmpty) return const [];

  final lowerTitle = title.toLowerCase();

  if (lowerTitle.contains('feature') ||
      lowerTitle.contains('app') ||
      lowerTitle.contains('code') ||
      lowerTitle.contains('dev') ||
      lowerTitle.contains('refactor')) {
    return const [
      DecomposedSubTask(
        title: 'Define technical requirements & spec',
        estimatedMinutes: 30,
      ),
      DecomposedSubTask(
        title: 'Design domain models & state graph',
        estimatedMinutes: 45,
      ),
      DecomposedSubTask(
        title: 'Implement core functionality & widgets',
        estimatedMinutes: 90,
      ),
      DecomposedSubTask(
        title: 'Write unit & widget tests',
        estimatedMinutes: 45,
      ),
      DecomposedSubTask(
        title: 'Run static analysis & verify quality',
        estimatedMinutes: 15,
      ),
    ];
  }

  if (lowerTitle.contains('launch') ||
      lowerTitle.contains('market') ||
      lowerTitle.contains('campaign') ||
      lowerTitle.contains('promo')) {
    return const [
      DecomposedSubTask(
        title: 'Identify target audience & key messaging',
        estimatedMinutes: 30,
      ),
      DecomposedSubTask(
        title: 'Prepare promotional graphics & assets',
        estimatedMinutes: 60,
      ),
      DecomposedSubTask(
        title: 'Draft announcement post & email newsletter',
        estimatedMinutes: 45,
      ),
      DecomposedSubTask(
        title: 'Set up tracking analytics & landing page',
        estimatedMinutes: 45,
      ),
      DecomposedSubTask(
        title: 'Publish campaign & monitor engagement',
        estimatedMinutes: 30,
      ),
    ];
  }

  if (lowerTitle.contains('design') ||
      lowerTitle.contains('ui') ||
      lowerTitle.contains('ux') ||
      lowerTitle.contains('prototype')) {
    return const [
      DecomposedSubTask(
        title: 'Gather user requirements & reference examples',
        estimatedMinutes: 30,
      ),
      DecomposedSubTask(
        title: 'Create low-fidelity wireframes',
        estimatedMinutes: 45,
      ),
      DecomposedSubTask(
        title: 'Develop high-fidelity UI component specs',
        estimatedMinutes: 60,
      ),
      DecomposedSubTask(
        title: 'Conduct design review & incorporate feedback',
        estimatedMinutes: 30,
      ),
    ];
  }

  // Fallback generic decomposition
  return [
    DecomposedSubTask(
      title: 'Clarify core objective for "$title"',
      estimatedMinutes: 15,
    ),
    const DecomposedSubTask(
      title: 'Gather required resources & dependencies',
      estimatedMinutes: 30,
    ),
    const DecomposedSubTask(
      title: 'Execute primary milestone action',
      estimatedMinutes: 60,
    ),
    const DecomposedSubTask(
      title: 'Review output & finalize deliverables',
      estimatedMinutes: 30,
    ),
  ];
}
