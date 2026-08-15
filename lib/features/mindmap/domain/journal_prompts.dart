/// Daily Journaling Contextual Prompts generator (Day One inspired).
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

class JournalPromptGenerator {
  const JournalPromptGenerator._();

  static const List<String> defaultReflectionPrompts = [
    'What was the single most meaningful moment today?',
    'What is one thing you learned or realized today?',
    'What made you feel proud or energized today?',
    'What obstacle did you overcome, and how?',
    'What can you do tomorrow to make the day even better?',
  ];

  /// Generates contextual prompts based on today's nodes activity.
  static List<String> generateContextualPrompts({
    required List<MindmapNode> dayNodes,
  }) {
    final prompts = <String>[];

    final completedTasks = dayNodes
        .where((n) => n.type == NodeType.task && n.isDone)
        .toList();
    if (completedTasks.isNotEmpty) {
      prompts.add(
        'You completed ${completedTasks.length} tasks today! Which one had the biggest impact?',
      );
    }

    final habits = dayNodes.where((n) => n.type == NodeType.habit).toList();
    if (habits.isNotEmpty) {
      prompts.add('How did you feel while executing your habits today?');
    }

    final goals = dayNodes.where((n) => n.type == NodeType.goal).toList();
    if (goals.isNotEmpty) {
      prompts.add(
        'Did your actions today bring you closer to your main goals?',
      );
    }

    prompts.addAll(defaultReflectionPrompts);
    return prompts.take(4).toList();
  }
}
