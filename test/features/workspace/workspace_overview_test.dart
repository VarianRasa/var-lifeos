import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/workspace_context.dart';
import 'package:var_app/features/workspace/application/workspace_overview.dart';

void main() {
  test('buildWorkspaceOverview counts totals and risk markers', () {
    final today = DateTime(2026, 6, 19);
    final contexts = WorkspaceContexts.fromNodes([
      MindmapNode.create(
        id: 'overdue',
        type: NodeType.task,
        title: 'Overdue',
        day: today,
        project: 'Launch',
        priority: NodePriority.high,
        dueDate: today.subtract(const Duration(days: 1)),
        now: today,
      ),
      MindmapNode.create(
        id: 'done',
        type: NodeType.task,
        title: 'Done',
        day: today,
        project: 'Launch',
        status: NodeStatus.done,
        priority: NodePriority.high,
        now: today,
      ),
      MindmapNode.create(
        id: 'area',
        type: NodeType.note,
        title: 'Area note',
        day: today,
        area: 'Health',
        now: today.subtract(const Duration(days: 20)),
      ),
    ]);

    final summary = buildWorkspaceOverview(contexts, today);

    expect(summary.totalWorkspaces, 3);
    expect(summary.projects, 1);
    expect(summary.areas, 1);
    expect(summary.dailies, 1);
    expect(summary.activeNodes, 3);
    expect(summary.overdueNodes, 1);
    expect(summary.highPriorityOpenNodes, 1);
    expect(
      summary.healthByWorkspace['project:Launch'],
      WorkspaceHealthStatus.atRisk,
    );
  });

  test('classifyWorkspaceHealth returns healthy quiet busy at risk', () {
    final today = DateTime(2026, 6, 19);

    WorkspaceContext workspace(String name, List<MindmapNode> nodes) {
      return WorkspaceContext(
        type: WorkspaceContextType.project,
        name: name,
        nodes: nodes,
      );
    }

    expect(
      classifyWorkspaceHealth(
        workspace('Healthy', [
          MindmapNode.create(
            id: 'healthy',
            type: NodeType.task,
            title: 'Healthy',
            day: today,
            now: today,
          ),
        ]),
        today,
      ),
      WorkspaceHealthStatus.healthy,
    );
    expect(
      classifyWorkspaceHealth(workspace('Quiet', const []), today),
      WorkspaceHealthStatus.quiet,
    );
    expect(
      classifyWorkspaceHealth(
        workspace('Busy', [
          MindmapNode.create(
            id: 'busy',
            type: NodeType.task,
            title: 'Busy',
            day: today,
            priority: NodePriority.high,
            now: today,
          ),
        ]),
        today,
      ),
      WorkspaceHealthStatus.busy,
    );
    expect(
      classifyWorkspaceHealth(
        workspace('Risk', [
          MindmapNode.create(
            id: 'risk',
            type: NodeType.task,
            title: 'Risk',
            day: today,
            dueDate: today.subtract(const Duration(days: 1)),
            now: today,
          ),
        ]),
        today,
      ),
      WorkspaceHealthStatus.atRisk,
    );
  });
}
