/// Eisenhower Matrix classification and actionability priority scoring.
library;

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'mindmap_node.dart';

enum EisenhowerQuadrant {
  doFirst, // Q1: Urgent & Important
  schedule, // Q2: Important, Not Urgent
  delegate, // Q3: Urgent, Not Important
  dontDo, // Q4: Neither
}

extension EisenhowerQuadrantX on EisenhowerQuadrant {
  String get title => switch (this) {
    EisenhowerQuadrant.doFirst => 'Do First (Urgent & Important)',
    EisenhowerQuadrant.schedule => 'Schedule (Important, Not Urgent)',
    EisenhowerQuadrant.delegate => 'Delegate (Urgent, Not Important)',
    EisenhowerQuadrant.dontDo => 'Don\'t Do / Eliminate',
  };

  String get badge => switch (this) {
    EisenhowerQuadrant.doFirst => 'Q1',
    EisenhowerQuadrant.schedule => 'Q2',
    EisenhowerQuadrant.delegate => 'Q3',
    EisenhowerQuadrant.dontDo => 'Q4',
  };
}

final class EisenhowerNodeScore {
  const EisenhowerNodeScore({
    required this.node,
    required this.quadrant,
    required this.score,
    required this.isUrgent,
    required this.isImportant,
  });

  final MindmapNode node;
  final EisenhowerQuadrant quadrant;
  final double score; // 0.0 - 100.0
  final bool isUrgent;
  final bool isImportant;
}

EisenhowerNodeScore scoreEisenhowerNode(MindmapNode node, DateTime today) {
  final normalizedToday = today.dateOnly;

  final isImportant =
      node.priority == NodePriority.high ||
      node.priority == NodePriority.urgent ||
      node.type == NodeType.goal ||
      node.isPinned;

  bool isUrgent = false;
  if (node.priority == NodePriority.urgent) {
    isUrgent = true;
  } else if (node.dueDate != null) {
    final due = node.dueDate!.dateOnly;
    final diffDays = due.difference(normalizedToday).inDays;
    if (diffDays <= 2) {
      isUrgent = true;
    }
  }

  final EisenhowerQuadrant quadrant = switch ((isImportant, isUrgent)) {
    (true, true) => EisenhowerQuadrant.doFirst,
    (true, false) => EisenhowerQuadrant.schedule,
    (false, true) => EisenhowerQuadrant.delegate,
    (false, false) => EisenhowerQuadrant.dontDo,
  };

  double baseScore = switch (quadrant) {
    EisenhowerQuadrant.doFirst => 80.0,
    EisenhowerQuadrant.schedule => 60.0,
    EisenhowerQuadrant.delegate => 40.0,
    EisenhowerQuadrant.dontDo => 20.0,
  };

  if (node.dueDate != null) {
    final due = node.dueDate!.dateOnly;
    final diffDays = due.difference(normalizedToday).inDays;
    if (diffDays < 0) {
      baseScore += 15.0; // Overdue bonus priority
    } else if (diffDays == 0) {
      baseScore += 10.0; // Due today
    } else if (diffDays <= 2) {
      baseScore += 5.0;
    }
  }

  if (node.priority == NodePriority.urgent) baseScore += 5.0;
  if (node.priority == NodePriority.high) baseScore += 3.0;

  return EisenhowerNodeScore(
    node: node,
    quadrant: quadrant,
    score: baseScore.clamp(0.0, 100.0),
    isUrgent: isUrgent,
    isImportant: isImportant,
  );
}

final class EisenhowerMatrixSummary {
  const EisenhowerMatrixSummary({
    required this.q1DoFirst,
    required this.q2Schedule,
    required this.q3Delegate,
    required this.q4DontDo,
  });

  final List<EisenhowerNodeScore> q1DoFirst;
  final List<EisenhowerNodeScore> q2Schedule;
  final List<EisenhowerNodeScore> q3Delegate;
  final List<EisenhowerNodeScore> q4DontDo;

  factory EisenhowerMatrixSummary.fromNodes(
    Iterable<MindmapNode> nodes,
    DateTime today,
  ) {
    final q1 = <EisenhowerNodeScore>[];
    final q2 = <EisenhowerNodeScore>[];
    final q3 = <EisenhowerNodeScore>[];
    final q4 = <EisenhowerNodeScore>[];

    for (final node in nodes) {
      if (node.isArchived || node.isDone || node.status == NodeStatus.done) {
        continue;
      }
      final scored = scoreEisenhowerNode(node, today);
      switch (scored.quadrant) {
        case EisenhowerQuadrant.doFirst:
          q1.add(scored);
        case EisenhowerQuadrant.schedule:
          q2.add(scored);
        case EisenhowerQuadrant.delegate:
          q3.add(scored);
        case EisenhowerQuadrant.dontDo:
          q4.add(scored);
      }
    }

    q1.sort((a, b) => b.score.compareTo(a.score));
    q2.sort((a, b) => b.score.compareTo(a.score));
    q3.sort((a, b) => b.score.compareTo(a.score));
    q4.sort((a, b) => b.score.compareTo(a.score));

    return EisenhowerMatrixSummary(
      q1DoFirst: q1,
      q2Schedule: q2,
      q3Delegate: q3,
      q4DontDo: q4,
    );
  }
}
