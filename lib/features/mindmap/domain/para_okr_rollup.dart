/// Pure Dart domain algorithms for PARA & OKR hierarchy progress rollups.
library;

import '../../../core/constants/app_constants.dart';
import 'mindmap_node.dart';

final class ParaOkrNodeRollup {
  const ParaOkrNodeRollup({
    required this.nodeId,
    required this.title,
    required this.type,
    required this.project,
    required this.area,
    required this.directProgress,
    required this.rollupProgress,
    this.children = const [],
  });

  final String nodeId;
  final String title;
  final NodeType type;
  final String project;
  final String area;
  final double directProgress;
  final double rollupProgress;
  final List<ParaOkrNodeRollup> children;
}

final class ParaOkrRollupSummary {
  const ParaOkrRollupSummary({
    required this.areaProgress,
    required this.goals,
    required this.unlinkedProjects,
  });

  final Map<String, double> areaProgress;
  final List<ParaOkrNodeRollup> goals;
  final List<ParaOkrNodeRollup> unlinkedProjects;

  factory ParaOkrRollupSummary.fromNodes(Iterable<MindmapNode> nodes) {
    final nodeList = nodes.where((n) => !n.isArchived).toList();

    // Group nodes by goal / project
    final goals = nodeList.where((n) => n.type == NodeType.goal).toList();
    final projectNodes = nodeList
        .where((n) => n.type == NodeType.plan || n.type == NodeType.kanban)
        .toList();
    final itemNodes = nodeList
        .where(
          (n) =>
              n.type != NodeType.goal &&
              n.type != NodeType.plan &&
              n.type != NodeType.kanban,
        )
        .toList();

    final goalRollups = <ParaOkrNodeRollup>[];
    final processedProjectIds = <String>{};

    for (final goal in goals) {
      final matchingProjects = projectNodes.where((p) {
        return p.project.toLowerCase() == goal.title.toLowerCase() ||
            p.relatedNodeIds.contains(goal.id) ||
            (goal.project.isNotEmpty &&
                p.project.toLowerCase() == goal.project.toLowerCase());
      }).toList();

      final projectRollups = <ParaOkrNodeRollup>[];
      for (final proj in matchingProjects) {
        processedProjectIds.add(proj.id);
        final projItems = itemNodes.where((item) {
          return item.project.toLowerCase() == proj.title.toLowerCase() ||
              item.relatedNodeIds.contains(proj.id) ||
              (proj.project.isNotEmpty &&
                  item.project.toLowerCase() == proj.project.toLowerCase());
        }).toList();

        final itemRollups = projItems.map((item) {
          return ParaOkrNodeRollup(
            nodeId: item.id,
            title: item.title,
            type: item.type,
            project: item.project,
            area: item.area,
            directProgress: item.progress,
            rollupProgress: item.progress,
          );
        }).toList();

        final projRollup = itemRollups.isEmpty
            ? proj.progress
            : itemRollups.fold(0.0, (sum, i) => sum + i.rollupProgress) /
                  itemRollups.length;

        projectRollups.add(
          ParaOkrNodeRollup(
            nodeId: proj.id,
            title: proj.title,
            type: proj.type,
            project: proj.project,
            area: proj.area,
            directProgress: proj.progress,
            rollupProgress: projRollup,
            children: itemRollups,
          ),
        );
      }

      final goalRollup = projectRollups.isEmpty
          ? goal.progress
          : projectRollups.fold(0.0, (sum, p) => sum + p.rollupProgress) /
                projectRollups.length;

      goalRollups.add(
        ParaOkrNodeRollup(
          nodeId: goal.id,
          title: goal.title,
          type: goal.type,
          project: goal.project,
          area: goal.area,
          directProgress: goal.progress,
          rollupProgress: goalRollup,
          children: projectRollups,
        ),
      );
    }

    // Unlinked projects
    final unlinkedProjects = <ParaOkrNodeRollup>[];
    for (final proj in projectNodes) {
      if (processedProjectIds.contains(proj.id)) continue;
      final projItems = itemNodes.where((item) {
        return item.project.toLowerCase() == proj.title.toLowerCase() ||
            item.relatedNodeIds.contains(proj.id);
      }).toList();

      final itemRollups = projItems.map((item) {
        return ParaOkrNodeRollup(
          nodeId: item.id,
          title: item.title,
          type: item.type,
          project: item.project,
          area: item.area,
          directProgress: item.progress,
          rollupProgress: item.progress,
        );
      }).toList();

      final projRollup = itemRollups.isEmpty
          ? proj.progress
          : itemRollups.fold(0.0, (sum, i) => sum + i.rollupProgress) /
                itemRollups.length;

      unlinkedProjects.add(
        ParaOkrNodeRollup(
          nodeId: proj.id,
          title: proj.title,
          type: proj.type,
          project: proj.project,
          area: proj.area,
          directProgress: proj.progress,
          rollupProgress: projRollup,
          children: itemRollups,
        ),
      );
    }

    // Area rollup progress calculation
    final areaBuckets = <String, List<double>>{};
    for (final node in nodeList) {
      if (node.area.isNotEmpty) {
        areaBuckets.putIfAbsent(node.area, () => []).add(node.progress);
      }
    }

    final areaProgress = areaBuckets.map((area, progressList) {
      final avg = progressList.fold(0.0, (a, b) => a + b) / progressList.length;
      return MapEntry(area, avg);
    });

    return ParaOkrRollupSummary(
      areaProgress: areaProgress,
      goals: goalRollups,
      unlinkedProjects: unlinkedProjects,
    );
  }
}
