import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/project_plan.dart';

void main() {
  ProjectTask task(
    String id,
    int order, {
    ProjectTaskStatus status = ProjectTaskStatus.planned,
    List<String> dependencies = const <String>[],
  }) => ProjectTask(
    id: id,
    title: 'Task $id',
    order: order,
    status: status,
    dependencyTaskIds: dependencies,
  );

  ProjectMilestone milestone(String id, int order, List<ProjectTask> tasks) =>
      ProjectMilestone(
        id: id,
        title: 'Milestone $id',
        order: order,
        tasks: tasks,
      );

  ProjectPhase phase(String id, int order, List<ProjectMilestone> milestones) =>
      ProjectPhase(
        id: id,
        title: 'Phase $id',
        order: order,
        milestones: milestones,
      );

  test('rich project plan round trips without losing task metadata', () {
    final project = ProjectPlan(
      status: ProjectPlanStatus.active,
      startDate: DateTime(2026, 7, 16),
      targetDate: DateTime(2026, 8, 16),
      phases: <ProjectPhase>[
        phase('build', 0, <ProjectMilestone>[
          ProjectMilestone(
            id: 'beta',
            title: 'Beta',
            order: 0,
            description: 'Release candidate',
            deadline: DateTime(2026, 8, 1),
            tasks: <ProjectTask>[
              ProjectTask(
                id: 'ship',
                title: 'Ship beta',
                order: 0,
                description: 'Publish package',
                status: ProjectTaskStatus.blocked,
                priority: ProjectTaskPriority.urgent,
                deadline: DateTime(2026, 7, 30),
                labels: const <String>['release'],
                checklist: const <ProjectTaskChecklistItem>[
                  ProjectTaskChecklistItem(
                    id: 'check',
                    title: 'Run tests',
                    isDone: true,
                  ),
                ],
                attachments: const <ProjectPlanAttachmentReference>[
                  ProjectPlanAttachmentReference(
                    id: 'file',
                    fileName: 'release.pdf',
                    mimeType: 'application/pdf',
                    byteLength: 42,
                  ),
                ],
                dependencyTaskIds: const <String>['review'],
                estimatedMinutes: 120,
                actualMinutes: 90,
                blockingReason: 'Waiting approval',
              ),
            ],
          ),
        ]),
      ],
    );

    expect(ProjectPlan.fromJson(project.toJson()), project);
  });

  test('progress counts completed nested tasks', () {
    final project = ProjectPlan(
      phases: <ProjectPhase>[
        phase('one', 0, <ProjectMilestone>[
          milestone('one', 0, <ProjectTask>[
            task('done', 0, status: ProjectTaskStatus.done),
            task('open', 1),
          ]),
        ]),
      ],
    );

    expect(project.taskCount, 2);
    expect(project.completedTaskCount, 1);
    expect(project.progress, 0.5);
  });

  test('task dependency codec removes self and duplicates', () {
    final source = task('a', 0, dependencies: const <String>['a', 'b', 'b']);

    final decoded = ProjectTask.fromJson(source.toJson(), 0);

    expect(decoded.dependencyTaskIds, const <String>['b']);
  });

  test('phase milestone and task moves update hierarchy and order', () {
    final project = ProjectPlan(
      phases: <ProjectPhase>[
        phase('one', 0, <ProjectMilestone>[
          milestone('one', 0, <ProjectTask>[task('a', 0), task('b', 1)]),
        ]),
        phase('two', 1, <ProjectMilestone>[
          milestone('two', 0, <ProjectTask>[task('c', 0)]),
        ]),
      ],
    );

    final moved = project
        .movePhase('two', 0)
        .moveMilestone('one', 'two', 1)
        .moveTask('a', 'two', 1);

    expect(moved.phases.map((item) => item.id), const <String>['two', 'one']);
    expect(moved.phases.first.milestones.map((item) => item.id), const <String>[
      'two',
      'one',
    ]);
    expect(
      moved.phases.first.milestones.first.tasks.map((item) => item.id),
      const <String>['c', 'a'],
    );
    expect(moved.phases.first.milestones.first.tasks.last.order, 1);
  });
}
