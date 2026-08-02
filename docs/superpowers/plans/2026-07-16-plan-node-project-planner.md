# Plan Node Project Planner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the basic Plan node editor with a fully persisted phase → milestone → task project planner, including advanced task metadata, attachments, drag-and-drop, dynamic sizing, and a read-only collapsed preview.

**Architecture:** Add a pure Dart project-plan domain model and extend `PlanPayload` as the migration/persistence boundary. Build a dedicated Plan editor, following the existing Kanban editor pattern, while reusing `NodeAttachmentRepository`, draft merge, and mindmap invalidation flows. Keep expanded mode fully interactive and content-sized; keep collapsed mode responsive and read-only.

**Tech Stack:** Flutter Material 3, Dart 3.11, Riverpod, existing mindmap typed payloads, Sembast-backed attachment repository, `file_picker`, Flutter widget tests.

---

## File Map

- Create `lib/features/mindmap/domain/project_plan.dart`: phase, milestone, task, checklist, attachment-reference, validation, progress, migration-safe JSON, and movement operations.
- Modify `lib/features/mindmap/domain/node_type_payloads.dart`: hierarchical `PlanPayload`, legacy migration, unknown-key preservation.
- Create `lib/features/mindmap/presentation/node_editors/plan_node_editor.dart`: complete project planner UI and interactions.
- Modify `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`: route Plan to dedicated editor and retain quick-action compatibility.
- Modify `lib/features/mindmap/presentation/node_type_content.dart`: compact Plan content summary from hierarchical payload.
- Modify `lib/features/mindmap/presentation/node_editors/node_edit_context.dart` or current `NodeEditContext` declaration file: Plan attachment callbacks.
- Modify `lib/features/mindmap/presentation/inline_node_workspace.dart`: forward Plan attachment callbacks.
- Modify `lib/features/calendar/day_page.dart`: Plan attachment add/open/remove adapters.
- Modify `lib/features/mindmap/presentation/mindmap_canvas.dart`: production Plan attachment adapters, typed save, collapsed preview.
- Modify `lib/features/mindmap/domain/inline_node_workspace_policy.dart`: content-derived Plan expanded size.
- Create `test/features/mindmap/domain/project_plan_test.dart`: domain, progress, migration, movement, validation.
- Modify `test/features/mindmap/domain/node_type_payloads_test.dart`: Plan payload migration and merge safety.
- Modify `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`: Plan content sizing.
- Create `test/features/mindmap/presentation/plan_node_editor_test.dart`: full editor interaction tests.
- Modify `test/features/mindmap/presentation/productivity_node_editors_test.dart`: routing and compatibility.
- Modify `test/features/mindmap/presentation/mindmap_canvas_test.dart`: collapsed preview and persistence integration.

### Task 1: Add Project Plan Domain Model

**Files:**
- Create: `lib/features/mindmap/domain/project_plan.dart`
- Test: `test/features/mindmap/domain/project_plan_test.dart`

- [ ] **Step 1: Write failing model round-trip and progress tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/project_plan.dart';

void main() {
  test('project plan round trips advanced task fields and progress', () {
    final plan = ProjectPlan(
      status: ProjectPlanStatus.active,
      startDate: DateTime(2026, 7, 16),
      targetDate: DateTime(2026, 8, 16),
      phases: const <ProjectPhase>[
        ProjectPhase(
          id: 'phase-1',
          title: 'Discovery',
          order: 0,
          milestones: <ProjectMilestone>[
            ProjectMilestone(
              id: 'milestone-1',
              title: 'Requirements approved',
              order: 0,
              tasks: <ProjectTask>[
                ProjectTask(
                  id: 'task-1',
                  title: 'Review scope',
                  order: 0,
                  status: ProjectTaskStatus.done,
                  priority: ProjectTaskPriority.high,
                  estimatedMinutes: 60,
                  actualMinutes: 75,
                  labels: <String>['scope'],
                  checklist: <ProjectTaskChecklistItem>[
                    ProjectTaskChecklistItem(
                      id: 'check-1',
                      title: 'Confirm owner',
                      isDone: true,
                    ),
                  ],
                  attachments: <ProjectPlanAttachmentReference>[
                    ProjectPlanAttachmentReference(
                      id: 'file-1',
                      fileName: 'scope.pdf',
                      mimeType: 'application/pdf',
                      byteLength: 42,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final restored = ProjectPlan.fromJson(plan.toJson());

    expect(restored, plan);
    expect(restored.progress, 1);
    expect(restored.taskCount, 1);
  });

  test('project task rejects self dependency and normalizes duplicates', () {
    const task = ProjectTask(
      id: 'task-1',
      title: 'Build',
      order: 0,
      dependencyTaskIds: <String>['task-1', 'task-2', 'task-2'],
    );

    expect(task.normalizedDependencyTaskIds, <String>['task-2']);
  });
}
```

- [ ] **Step 2: Run tests and verify model is missing**

Run:

```powershell
flutter test --no-pub test/features/mindmap/domain/project_plan_test.dart
```

Expected: FAIL because `project_plan.dart` and its types do not exist.

- [ ] **Step 3: Implement immutable domain types and JSON codecs**

Create enums and immutable classes with `const` constructors, `copyWith`, `toJson`, `fromJson`, equality, and derived progress:

```dart
enum ProjectPlanStatus { planning, active, blocked, completed, archived }
enum ProjectTaskStatus { planned, inProgress, blocked, done }
enum ProjectTaskPriority { none, low, medium, high, urgent }

final class ProjectPlan {
  const ProjectPlan({
    this.status = ProjectPlanStatus.planning,
    this.startDate,
    this.targetDate,
    this.phases = const <ProjectPhase>[],
  });

  final ProjectPlanStatus status;
  final DateTime? startDate;
  final DateTime? targetDate;
  final List<ProjectPhase> phases;

  Iterable<ProjectTask> get tasks sync* {
    for (final phase in phases) {
      for (final milestone in phase.milestones) {
        yield* milestone.tasks;
      }
    }
  }

  int get taskCount => tasks.length;
  int get completedTaskCount =>
      tasks.where((task) => task.status == ProjectTaskStatus.done).length;
  double get progress => taskCount == 0 ? 0 : completedTaskCount / taskCount;
}
```

Add `ProjectPhase`, `ProjectMilestone`, `ProjectTask`, `ProjectTaskChecklistItem`, and `ProjectPlanAttachmentReference`. Parse malformed collections defensively and preserve local-day dates using ISO strings.

- [ ] **Step 4: Add movement operations**

Implement operations returning new `ProjectPlan` values:

```dart
ProjectPlan movePhase(String phaseId, int targetIndex);
ProjectPlan moveMilestone(String milestoneId, String phaseId, int targetIndex);
ProjectPlan moveTask(String taskId, String milestoneId, int targetIndex);
ProjectPlan updateTask(ProjectTask updatedTask);
ProjectPlan removeTask(String taskId);
```

Normalize every affected `order` after movement.

- [ ] **Step 5: Run domain tests**

```powershell
flutter test --no-pub test/features/mindmap/domain/project_plan_test.dart
```

Expected: PASS.

### Task 2: Migrate and Persist Hierarchical PlanPayload

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart:145`
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart:23`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing legacy migration and merge tests**

```dart
test('plan payload migrates legacy steps into default hierarchy', () {
  final source = node(NodeType.plan, <String, Object?>{
    'plan': <String, Object?>{
      'owner': 'keep',
      'steps': <String>['Research', 'Ship'],
      'completedSteps': <String>['Research'],
    },
  });

  final payload = PlanPayload.fromNode(source);

  expect(payload.project.phases.single.milestones.single.tasks, hasLength(2));
  expect(
    payload.project.phases.single.milestones.single.tasks.first.status,
    ProjectTaskStatus.done,
  );
  expect((payload.toData(source.data)['plan'] as Map)['owner'], 'keep');
});
```

- [ ] **Step 2: Run focused payload test and verify failure**

```powershell
flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --plain-name 'plan payload migrates legacy steps into default hierarchy'
```

Expected: FAIL because `PlanPayload.project` does not exist.

- [ ] **Step 3: Replace flat PlanPayload internals with ProjectPlan**

Keep compatibility getters and constructor support until all existing callers migrate:

```dart
final class PlanPayload {
  const PlanPayload({
    this.project = const ProjectPlan(),
    this.legacySteps = const <String>[],
    this.legacyCompletedSteps = const <String>[],
  });

  final ProjectPlan project;
  final List<String> legacySteps;
  final List<String> legacyCompletedSteps;

  List<String> get steps => project.tasks.map((task) => task.title).toList();
  List<String> get completedSteps => project.tasks
      .where((task) => task.status == ProjectTaskStatus.done)
      .map((task) => task.title)
      .toList();
}
```

`fromNode` reads hierarchical `project` first, then migrates legacy `steps/completedSteps`. `toData` deep-merges the existing `plan` map and writes `project`, `steps`, and `completedSteps` compatibility fields.

- [ ] **Step 4: Run payload and typed editor tests**

```powershell
flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/productivity_node_editors_test.dart
```

Expected: PASS.

### Task 3: Build Dedicated Plan Project Planner Editor

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/plan_node_editor.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart:800`
- Create: `test/features/mindmap/presentation/plan_node_editor_test.dart`

- [ ] **Step 1: Write failing editor shell test**

```dart
testWidgets('plan editor renders project summary and hierarchy actions', (
  tester,
) async {
  final node = planNode();
  await tester.pumpWidget(planEditorApp(node));

  expect(find.byKey(const ValueKey('plan-project-editor')), findsOneWidget);
  expect(find.byKey(const ValueKey('plan-add-phase')), findsOneWidget);
  expect(find.text('0 phases'), findsOneWidget);
  expect(find.text('0 milestones'), findsOneWidget);
  expect(find.text('0 tasks'), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Run test and verify dedicated editor is missing**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart
```

Expected: FAIL because `PlanNodeEditor` does not exist.

- [ ] **Step 3: Implement project header and summary**

Create `PlanNodeEditor` with:

```dart
final class PlanNodeEditor extends StatefulWidget {
  const PlanNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    this.onAttachmentAdd,
    this.onAttachmentOpen,
    this.onAttachmentRemove,
    super.key,
  });
}
```

Header fields: title, context, project status, start date, target date, progress bar, phase/milestone/task/completed/blocked chips, and `Add phase`.

- [ ] **Step 4: Implement phase and milestone cards**

Each phase and milestone must provide stable keys:

```dart
ValueKey('plan-phase-${phase.id}')
ValueKey('plan-milestone-${milestone.id}')
ValueKey('plan-add-milestone-${phase.id}')
ValueKey('plan-add-task-${milestone.id}')
```

Use dialogs for add/edit with 80-character title limits and deletion confirmation describing nested content count.

- [ ] **Step 5: Route NodeType.plan to PlanNodeEditor**

In `_ProductivityEditor.build`, replace the generic Plan editor branch:

```dart
if (context.node.type == NodeType.plan) {
  return PlanNodeEditor(
    node: context.node,
    payload: context.typedDraft is PlanPayload
        ? context.typedDraft as PlanPayload
        : PlanPayload.fromNode(context.node),
    onTitleChanged: context.onTitleChanged,
    onBodyChanged: context.onBodyChanged,
    onPayloadChanged: context.onDraftChanged,
    onAttachmentAdd: context.onPlanAttachmentAdd,
    onAttachmentOpen: context.onPlanAttachmentOpen,
    onAttachmentRemove: context.onPlanAttachmentRemove,
  );
}
```

- [ ] **Step 6: Run editor shell tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart test/features/mindmap/presentation/productivity_node_editors_test.dart
```

Expected: PASS.

### Task 4: Add Advanced Task Editing and Inline Components

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/plan_node_editor.dart`
- Test: `test/features/mindmap/presentation/plan_node_editor_test.dart`

- [ ] **Step 1: Write failing advanced task interaction test**

```dart
testWidgets('plan task exposes advanced fields and toggles checklist', (
  tester,
) async {
  final payloads = <PlanPayload>[];
  await tester.pumpWidget(planEditorApp(
    advancedPlanNode(),
    onPayloadChanged: payloads.add,
  ));

  expect(find.text('Priority'), findsWidgets);
  expect(find.text('Dependencies'), findsOneWidget);
  expect(find.text('Estimate'), findsOneWidget);
  expect(find.text('Actual'), findsOneWidget);
  expect(find.text('Blocking reason'), findsOneWidget);

  await tester.tap(
    find.byKey(const ValueKey('plan-checklist-task-1-check-1')),
  );
  await tester.pump();

  expect(
    payloads.last.project.tasks.single.checklist.single.isDone,
    isTrue,
  );
});
```

- [ ] **Step 2: Run test and verify advanced controls are missing**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart --plain-name 'plan task exposes advanced fields and toggles checklist'
```

Expected: FAIL.

- [ ] **Step 3: Implement complete task card**

Render all fields directly in the task card:

- completion checkbox and status selector;
- title and description;
- priority and deadline;
- labels;
- estimated and actual minutes;
- dependency task chips;
- blocking reason when status is blocked;
- interactive checklist;
- attachment file rows;
- edit, duplicate, and delete menu.

Use `FilteringTextInputFormatter.digitsOnly` for minute fields and convert empty values to `null`.

- [ ] **Step 4: Validate dependency input**

Exclude current task from dependency choices and normalize duplicates:

```dart
final dependencies = selectedIds
    .where((id) => id != task.id && project.taskById(id) != null)
    .toSet()
    .toList(growable: false);
```

- [ ] **Step 5: Run advanced task tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart
```

Expected: PASS.

### Task 5: Add Free Pointer Drag-and-Drop

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/plan_node_editor.dart`
- Test: `test/features/mindmap/presentation/plan_node_editor_test.dart`

- [ ] **Step 1: Write failing drag tests**

Test phase reorder, milestone movement between phases, and task movement between milestones. Verify task draggable has no axis lock:

```dart
final draggable = tester.widget<Draggable<PlanTaskDragData>>(
  find.byKey(const ValueKey('plan-task-drag-task-1')),
);
expect(draggable.axis, isNull);
```

- [ ] **Step 2: Implement typed drag data**

```dart
sealed class PlanDragData {
  const PlanDragData();
}

final class PlanPhaseDragData extends PlanDragData {
  const PlanPhaseDragData(this.phaseId);
  final String phaseId;
}

final class PlanMilestoneDragData extends PlanDragData {
  const PlanMilestoneDragData(this.milestoneId);
  final String milestoneId;
}

final class PlanTaskDragData extends PlanDragData {
  const PlanTaskDragData(this.taskId);
  final String taskId;
}
```

Use `Draggable` without `axis` for tasks and milestones. Highlight matching `DragTarget` containers with the active palette primary color.

- [ ] **Step 3: Run drag tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart --plain-name 'drag'
```

Expected: PASS.

### Task 6: Integrate Plan Attachments with Existing Backend

**Files:**
- Modify: `lib/features/mindmap/presentation/node_type_inline_editor.dart`
- Modify: `lib/features/mindmap/presentation/inline_node_workspace.dart`
- Modify: `lib/features/calendar/day_page.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/plan_node_editor.dart`
- Test: `test/features/mindmap/presentation/plan_node_editor_test.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Add Plan attachment callback contract**

```dart
typedef PlanAttachmentAddCallback =
    Future<ProjectPlanAttachmentReference?> Function();
typedef PlanAttachmentActionCallback =
    Future<void> Function(ProjectPlanAttachmentReference attachment);
```

Add nullable `onPlanAttachmentAdd`, `onPlanAttachmentOpen`, and `onPlanAttachmentRemove` to `NodeEditContext` and forward them through `InlineNodeWorkspace`.

- [ ] **Step 2: Reuse repository adapters in DayPage**

Convert between Plan references and the existing stored attachment representation exactly as Task/Kanban do:

```dart
Future<ProjectPlanAttachmentReference?> _addPlanAttachment() async {
  final taskReference = await _addTaskAttachment();
  return taskReference == null
      ? null
      : ProjectPlanAttachmentReference(
          id: taskReference.id,
          fileName: taskReference.fileName,
          mimeType: taskReference.mimeType,
          byteLength: taskReference.byteLength,
        );
}
```

Open and remove adapters convert back to the repository-compatible reference before delegating.

- [ ] **Step 3: Add production canvas adapters**

Implement the same wrappers in the production inline editor state in `mindmap_canvas.dart` and pass them only for `NodeType.plan`.

- [ ] **Step 4: Wire attachment UI**

Task attachment rows use:

```dart
ValueKey('plan-attachment-${task.id}-${attachment.id}')
```

Tap calls open/preview. Add uses picker callback. Remove confirms before deleting repository data and payload reference.

- [ ] **Step 5: Run attachment wiring tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/plan_node_editor_test.dart --plain-name 'attachment'
flutter test --no-pub test/features/calendar/day_page_test.dart --plain-name 'Plan attachment'
```

Expected: PASS.

### Task 7: Add Dynamic Plan Workspace Sizing

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart:78`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/inline_node_workspace_test.dart`

- [ ] **Step 1: Write failing content-growth test**

```dart
test('plan expanded size grows with full hierarchy content', () {
  final node = richPlanNode();

  final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);

  expect(size.width, greaterThanOrEqualTo(720));
  expect(size.height, greaterThan(InlineNodeWorkspacePolicy.large.height));
});
```

- [ ] **Step 2: Implement content-derived sizing**

Add a `NodeType.plan` branch before fallback. Compute height from:

```dart
var height = 300.0;
for (final phase in project.phases) {
  height += 90;
  for (final milestone in phase.milestones) {
    height += 84;
    for (final task in milestone.tasks) {
      height += 110;
      if (task.description.isNotEmpty) height += 44;
      if (task.labels.isNotEmpty) height += 30;
      if (task.dependencyTaskIds.isNotEmpty) height += 34;
      if (task.blockingReason.isNotEmpty) height += 44;
      height += task.checklist.length * 30;
      height += task.attachments.length * 34;
    }
  }
}
return InlineNodeWorkspaceSize(720, math.max(560, height));
```

- [ ] **Step 3: Add narrow fallback assertion**

Verify normal policy size has no internal scroll; constrained test hosts may use the existing safety scroll wrapper without overflow.

- [ ] **Step 4: Run sizing tests**

```powershell
flutter test --no-pub test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/inline_node_workspace_test.dart --plain-name 'plan'
```

Expected: PASS.

### Task 8: Replace Collapsed Plan with Read-Only Project Preview

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart:6180`
- Modify: `lib/features/mindmap/presentation/node_type_content.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing collapsed preview test**

```dart
testWidgets('collapsed Plan renders responsive read-only hierarchy', (
  tester,
) async {
  await tester.pumpWidget(canvasWithNode(richPlanNode()));

  expect(find.text('Discovery'), findsOneWidget);
  expect(find.text('Requirements approved'), findsOneWidget);
  expect(find.text('Review scope'), findsOneWidget);
  expect(find.byKey(const ValueKey('plan-add-phase')), findsNothing);
  expect(find.byKey(const ValueKey('plan-task-menu-task-1')), findsNothing);
  expect(tester.takeException(), isNull);
});
```

- [ ] **Step 2: Implement preview-only widgets**

Create private canvas widgets:

```dart
class _PlanProjectPreview extends StatelessWidget { ... }
class _PlanPhasePreview extends StatelessWidget { ... }
class _PlanMilestonePreview extends StatelessWidget { ... }
class _PlanTaskPreview extends StatelessWidget { ... }
```

Display status, overall progress, phase/milestone titles, and compact task completion. Hide metadata below responsive width thresholds, as done for Kanban collapse.

- [ ] **Step 3: Remove collapsed mutation actions**

Do not expose complete-next-step, edit, drag, delete, or attachment controls in collapsed mode. Expanded `Open Inline` remains the sole Plan editor.

- [ ] **Step 4: Run canvas tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --plain-name 'Plan'
```

Expected: PASS with no RenderFlex overflow.

### Task 9: Verify Typed Save, Local Database, and Sync Compatibility

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart:9400`
- Modify: `lib/features/calendar/day_page.dart`
- Test: `test/features/mindmap/presentation/inline_node_workspace_test.dart`
- Test: `test/features/calendar/day_page_test.dart`

- [ ] **Step 1: Add typed save regression test**

Verify an updated `PlanPayload` persists nested hierarchy while preserving unrelated node and Plan keys:

```dart
expect(saved.data['unrelated'], 'keep');
expect((saved.data['plan'] as Map)['owner'], 'keep');
expect(
  (((saved.data['plan'] as Map)['project'] as Map)['phases'] as List),
  isNotEmpty,
);
```

- [ ] **Step 2: Ensure save switch handles PlanPayload**

The typed save switch must include:

```dart
final PlanPayload payload => payload.toData(baseNode.data),
```

Use existing `InlineNodeDraftPatch.between` and `invalidateMindmapStateFromRef`; do not create a separate Plan repository.

- [ ] **Step 3: Run persistence tests**

```powershell
flutter test --no-pub test/features/mindmap/presentation/inline_node_workspace_test.dart --plain-name 'plan'
flutter test --no-pub test/features/calendar/day_page_test.dart --plain-name 'plan'
```

Expected: PASS.

### Task 10: Final Focused Validation

**Files:**
- Verify all files above.

- [ ] **Step 1: Format edited files**

```powershell
dart format lib/features/mindmap/domain/project_plan.dart lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart lib/features/mindmap/presentation/node_editors/plan_node_editor.dart lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart lib/features/mindmap/presentation/node_type_inline_editor.dart lib/features/mindmap/presentation/inline_node_workspace.dart lib/features/mindmap/presentation/node_type_content.dart lib/features/mindmap/presentation/mindmap_canvas.dart lib/features/calendar/day_page.dart test/features/mindmap/domain/project_plan_test.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/plan_node_editor_test.dart test/features/mindmap/presentation/productivity_node_editors_test.dart test/features/mindmap/presentation/inline_node_workspace_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart test/features/calendar/day_page_test.dart
```

Expected: formatted successfully.

- [ ] **Step 2: Run focused Plan suite**

```powershell
flutter test --no-pub test/features/mindmap/domain/project_plan_test.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/plan_node_editor_test.dart test/features/mindmap/presentation/productivity_node_editors_test.dart test/features/mindmap/presentation/inline_node_workspace_test.dart
flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --plain-name 'Plan'
flutter test --no-pub test/features/calendar/day_page_test.dart --plain-name 'plan'
```

Expected: all tests pass.

- [ ] **Step 3: Run analyzer**

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`.

- [ ] **Step 4: Check diff whitespace**

```powershell
git diff --check -- lib/features/mindmap test/features/mindmap lib/features/calendar/day_page.dart test/features/calendar/day_page_test.dart
```

Expected: no whitespace errors. Existing unrelated working-tree changes remain untouched.