# Workspaces page enhancement plan

Goal: evolve `WorkspacesPage` and `WorkspaceDetailPage` into a local-first mission control surface for projects, areas, daily contexts, workload, health, goals, graph relations, and next actions.

Primary target files:

- `lib/features/workspace/workspaces_page.dart`
- `lib/features/workspace/workspace_detail_page.dart`
- `lib/features/workspace/application/*`
- `lib/features/workspace/domain/*`
- `lib/features/workspace/data/*`
- `lib/features/mindmap/domain/workspace_context.dart`
- `lib/features/mindmap/application/mindmap_providers.dart`
- Tests under `test/features/workspace/...`

Design direction:

- Preserve cockpit/space visual language used by Graph and Insights.
- Keep summaries readable before adding dense controls.
- Derive everything from local `MindmapNode` fields first.
- Avoid schema changes unless a phase explicitly requires metadata.
- Every workspace marker should answer: what is this context, how healthy is it, what needs action next.
- Prefer compact cards, chips, filters, side panels, drill-downs, and markdown export.

Existing baseline:

- `WorkspacesPage` already shows projects, areas, dailies.
- Search exists.
- Sort/custom titles exist via:
  - `workspace_sort_repository.dart`
  - `workspace_title_repository.dart`
- `WorkspaceDetailPage` already supports List, Kanban, and Gantt views.
- Workspace data derives from `WorkspaceContexts` and `WorkspaceContext`.

## Phase 1 — Workspace mission overview

Purpose: summarize all workspace health before deep exploration.

Implement:

- Top HUD cards:
  - total workspaces
  - projects
  - areas
  - dailies
  - active nodes
  - overdue nodes
  - high-priority open nodes
  - stale workspaces
- Workspace health classification:
  - `Healthy`
  - `Quiet`
  - `Busy`
  - `At risk`
- Empty state for no workspaces.

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_overview.dart`
  - `WorkspaceOverviewSummary`
  - `WorkspaceHealthStatus`
  - `buildWorkspaceOverview(...)`

Validation:

- Unit tests for totals, overdue counts, stale detection, health classification.

## Phase 2 — Workspace filters and saved views

Purpose: inspect focused workspace slices quickly.

Implement filters:

- workspace type:
  - project
  - area
  - daily
- health status
- priority level
- overdue only
- stale only
- active only
- tag
- sort:
  - manual
  - name
  - activity
  - risk
  - progress
- clear filters CTA.

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_filters.dart`
  - `WorkspaceFilterState`
  - `WorkspaceSortMode`
  - `matchesWorkspaceFilter(...)`
  - `sortFilteredWorkspaces(...)`

Validation:

- Unit tests for predicate combinations and stable ordering.

## Phase 3 — Workspace health cards

Purpose: make each workspace card immediately actionable.

Implement per workspace card:

- title/custom title
- type badge
- active/done/overdue counts
- progress/completion
- high-priority count
- stale indicator
- last activity
- top tags
- next action preview
- quick links:
  - open workspace
  - filter graph by context
  - open insights context
  - open today/day if daily

Validation:

- Widget tests for cards and route callbacks where practical.

## Phase 4 — Workspace detail mission header

Purpose: upgrade `WorkspaceDetailPage` header into a command summary.

Implement:

- health classification
- active/done/blocked/waiting/overdue/high-priority counters
- last activity
- progress trend indicator
- context tags
- quick actions:
  - open Graph scoped to workspace
  - open Insights scoped to workspace
  - copy workspace report
  - jump to next action

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_health.dart`
  - `WorkspaceHealthSummary`
  - `buildWorkspaceHealth(...)`

Validation:

- Unit tests for status counts and health classification.

## Phase 5 — Workspace next actions

Purpose: answer what the user should do next in each workspace.

Detect:

- overdue task
- urgent/high-priority open task
- waiting/blocked task
- stale active task
- goal without next task
- workspace with many notes but no task
- project with no recent activity

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_next_actions.dart`
  - `WorkspaceNextAction`
  - `WorkspaceNextActionSeverity`
  - `buildWorkspaceNextActions(...)`

Validation:

- Deterministic unit tests per action type.

## Phase 6 — Workspace workload timeline

Purpose: reveal current and upcoming load.

Implement:

- due today
- due this week
- overdue
- upcoming 30 days
- completed recently
- activity by day mini timeline

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_timeline.dart`
  - `WorkspaceTimelineSummary`
  - `WorkspaceTimelineBucket`

Validation:

- Unit tests for date buckets and local-day handling.

## Phase 7 — Workspace Kanban intelligence

Purpose: make current Kanban view more useful.

Enhance detail Kanban:

- lanes by status:
  - open
  - planned
  - doing
  - waiting
  - done
- lane counters
- overdue/high-priority badges
- compact task metadata
- empty lane states
- quick open node/day actions

Validation:

- Widget smoke tests for lanes, counters, empty state.

## Phase 8 — Workspace Gantt/timeline polish

Purpose: improve planning view readability.

Enhance detail Gantt:

- today marker
- overdue marker
- due date labels
- progress bars
- grouped by status or priority
- empty due-date guidance
- narrow layout fallback list

Validation:

- Widget smoke tests for due-date nodes and empty due-date state.

## Phase 9 — Goals and milestones in workspaces

Purpose: connect projects/areas to longer-term outcomes.

Implement:

- goal summary panel
- goal progress
- related milestones/tasks/notes
- missing next action warning
- stalled goal warning
- milestone checklist preview if available from `data`

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_goal_summary.dart`
  - `WorkspaceGoalSummary`
  - `WorkspaceGoalItem`

Validation:

- Unit tests for goal grouping, progress, stalled detection.

## Phase 10 — Workspace relationship context

Purpose: connect Workspace Page to Graph Page.

Implement:

- relation count per workspace
- internal relations
- external relations
- isolated nodes
- hub nodes in workspace
- graph CTA scoped by project/area/tag

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_relationships.dart`
  - `WorkspaceRelationshipSummary`
  - `buildWorkspaceRelationshipSummary(...)`

Validation:

- Unit tests using `NodeGraph.fromNodes(...)`.

## Phase 11 — Workspace drill-down panels

Purpose: keep list cards compact while details remain accessible.

Implement expandable panels:

- overdue nodes
- high-priority nodes
- waiting/blocked nodes
- stale workspaces
- goals
- notes without next action
- recently completed
- relationship gaps

Behavior:

- Each row opens Day Page or Node Detail.
- Filters/search preserved where practical.

Validation:

- Widget tests for expansion and navigation callbacks.

## Phase 12 — Workspace recommendations

Purpose: provide local-first suggestions for improvement.

Suggest:

- add next action to quiet project
- connect isolated priority task to project/goal
- review stale area
- close done-heavy workspace
- split crowded workspace
- schedule overdue task
- promote active tag to area/project if repeated

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_recommendations.dart`
  - `WorkspaceRecommendation`
  - `WorkspaceRecommendationType`

Validation:

- Unit tests for scoring, dedupe, stable ordering.

## Phase 13 — Workspace markdown export

Purpose: share workspace report and review notes.

Implement markdown export:

- overview metrics
- health status
- projects/areas/dailies
- overdue/high-priority/stale sections
- goals and milestones
- timeline buckets
- relationship summary
- recommendations

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_markdown_export.dart`

Validation:

- Snapshot-style unit tests for report sections.

## Phase 14 — Performance and caching pass

Purpose: keep Workspaces responsive with large local datasets.

Implement:

- Avoid repeated full scans in build.
- Precompute workspace index once.
- Precompute counts, tags, health, next actions.
- Keep helpers pure/testable.
- Consider provider-level memoization only if needed.

Suggested impl:

- Helper:
  - `lib/features/workspace/application/workspace_index.dart`
  - `WorkspaceIndex`
  - `buildWorkspaceIndex(...)`

Validation:

- Unit tests for index counts and stable reuse.
- `flutter analyze`
- targeted tests.

## Phase 15 — Accessibility and keyboard pass

Purpose: make workspaces usable on desktop and assistive tech.

Implement:

- semantic labels for workspace cards/counters
- keyboard shortcuts visible in UI
- focus traversal for filters, cards, detail views
- shortcuts:
  - `/`: search
  - `Esc`: clear search/filters
  - `1`: projects mode/filter
  - `2`: areas mode/filter
  - `3`: dailies mode/filter
  - `G`: open Graph scoped to selected workspace
  - `I`: open Insights
  - `R`: reset filters
  - `E`: copy export/report
- text fallback list for dense visual panels

Validation:

- Widget shortcut tests where practical.
- Manual narrow-width smoke.

## Phase 16 — Responsive layout polish

Purpose: make workspace pages excellent across screen sizes.

Implement:

- desktop:
  - overview + filters + multi-column workspace grid
  - detail page with side diagnostics panel
- tablet:
  - two-column cards where possible
  - collapsible diagnostics
- mobile:
  - stacked controls
  - bottom sheet for detail actions
  - reduced chip density
- empty/loading/error states for all major panels

Validation:

- Widget smoke tests for narrow/wide layouts.

## Phase 17 — Final polish and integration

Purpose: connect Workspaces with Calendar, Day, Graph, Insights, and Command Palette.

Implement:

- Route links:
  - Day Page
  - Node Detail
  - Graph scoped by project/area/tag
  - Insights scoped by context
  - Calendar day for daily workspace
- Consistent copy/icon language with Insights and Graph.
- Final empty/loading/error polish.
- Final test + analyze pass.

Validation:

- `dart format lib/features/workspace test/features/workspace`
- `flutter analyze lib/features/workspace test/features/workspace`
- `flutter test test/features/workspace`
- Optional broader `flutter test`.

## Implementation rules for agents

- Keep changes small: one phase per turn/PR when possible.
- Add tests for application/domain helpers before complex UI.
- Do not change `MindmapNode` schema unless necessary.
- Reuse existing node fields:
  - `day`
  - `status`
  - `priority`
  - `tags`
  - `project`
  - `area`
  - `data`
  - `relatedNodeIds`
  - `dueDate`
  - `progress`
  - `updatedAt`
- Prefer lightweight metadata in `data` for derived state markers.
- Respect strict analyzer:
  - explicit return types
  - no raw types
  - avoid dynamic calls
  - trailing commas
  - no unused private code
- Run after each phase:
  - `dart format lib/features/workspace test/features/workspace`
  - `flutter analyze lib/features/workspace test/features/workspace`
  - `flutter test test/features/workspace`

## Recommended implementation order

1. Workspace mission overview
2. Workspace filters and saved views
3. Workspace health cards
4. Workspace detail mission header
5. Workspace next actions
6. Workspace workload timeline
7. Workspace Kanban intelligence
8. Workspace Gantt/timeline polish
9. Goals and milestones in workspaces
10. Workspace relationship context
11. Workspace drill-down panels
12. Workspace recommendations
13. Workspace markdown export
14. Performance and caching pass
15. Accessibility and keyboard pass
16. Responsive layout polish
17. Final polish and integration

## Definition of done

A phase is done when:

- UI follows cockpit/space visual style.
- Feature works offline/local-first.
- Metrics derive from local repository data.
- Empty/error/loading states exist where relevant.
- Analyzer is clean.
- Relevant tests pass or validation gap is documented.
