# Graph page enhancement plan

Goal: evolve `lib/features/graph/graph_page.dart` into an interactive local-first relationship explorer for mindmap nodes, contexts, goals, risks, and dependencies.

Primary target files:

- `lib/features/graph/graph_page.dart`
- `lib/features/graph/application/*`
- `lib/features/graph/domain/*`
- `lib/features/mindmap/domain/node_graph.dart`
- `lib/features/mindmap/application/mindmap_providers.dart`
- Tests under `test/features/graph/...`

Design direction:

- Preserve cockpit/space visual language.
- Keep graph readable before making it dense.
- Prefer deterministic/local derived data from existing `MindmapNode` fields.
- Avoid schema changes unless a phase explicitly needs metadata.
- Every visual marker should answer: what is connected, why it matters, what action is next.
- Use compact controls, graph chips, side panels, badges, and collapsible diagnostics.

## Phase 1 — Graph mission overview

Purpose: summarize graph health before deep exploration.

Implement:

- Top HUD cards:
  - total nodes
  - relation count
  - connected nodes
  - isolated nodes
  - hub nodes
  - stale nodes
  - high-priority open nodes
- Health classification:
  - `Healthy`
  - `Sparse`
  - `Crowded`
  - `At risk`
- Empty state for no nodes / no relations.

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_overview.dart`
  - `GraphOverviewSummary`
  - `GraphHealthStatus`
  - `buildGraphOverview(...)`

Validation:

- Unit tests for totals, relation counts, hub detection, health classification.

## Phase 2 — Interactive graph filters

Purpose: let users inspect focused slices without losing context.

Implement filters:

- node type
- project
- area
- tag
- priority
- status
- relation state:
  - connected
  - isolated
  - hub
  - stale
- clear filters CTA.

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_filters.dart`
  - `GraphFilterState`
  - `matchesGraphFilter(...)`

Validation:

- Unit tests for predicate combinations and stable filtered ordering.

## Phase 3 — Node detail side panel

Purpose: make selecting a node actionable.

Implement:

- Selected node panel:
  - title
  - type/status/priority
  - project/area/tags
  - due date/progress
  - related node count
  - incoming/outgoing relation lists
- Actions:
  - open Day Page
  - open Node Detail
  - filter by project/area/tag
  - focus related nodes
  - clear selection

Validation:

- Widget tests for selection, panel rendering, route callbacks where practical.

## Phase 4 — Relationship intelligence

Purpose: surface graph problems and useful structure.

Detect:

- orphan nodes
- isolated high-priority tasks
- hub nodes
- stale clusters
- one-way dependency chains
- relation gaps for goals/projects

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_relationship_insights.dart`
  - `GraphRelationshipInsight`
  - `GraphRelationshipSeverity`

Validation:

- Deterministic unit tests per insight type.

## Phase 5 — Context graph mode

Purpose: visualize project/area/tag clusters.

Implement:

- Toggle modes:
  - nodes
  - projects
  - areas
  - tags
- Context summary cards:
  - node count
  - open tasks
  - done tasks
  - overdue
  - high priority
  - last activity
- Cluster chips and color accents.

Suggested impl:

- Helper:
  - `lib/features/graph/application/context_graph.dart`
  - `ContextGraphSummary`
  - `ContextGraphCluster`

Validation:

- Unit tests for grouping, counts, last activity, stable sorting.

## Phase 6 — Goal dependency map

Purpose: reveal long-term goal support structure.

Implement:

- Goal nodes as anchors.
- Related milestones/tasks/notes grouped under each goal.
- Missing next action warning.
- Stalled dependency marker.
- Progress badge from existing goal fields/data.

Suggested impl:

- Helper:
  - `lib/features/graph/application/goal_dependency_graph.dart`
  - `GoalDependencyMap`
  - `GoalDependencyItem`

Validation:

- Unit tests for dependency mapping, missing next action, stalled goal detection.

## Phase 7 — Risk overlay

Purpose: make risky nodes visible inside the graph.

Overlay badges:

- overdue
- high priority
- stale
- blocked/waiting
- no relations
- goal needs next action

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_risk_overlay.dart`
  - `GraphRiskBadge`
  - `GraphRiskSeverity`
  - `buildGraphRiskOverlay(...)`

Validation:

- Unit tests for badge assignment and severity ordering.

## Phase 8 — Search and focus controls

Purpose: quickly jump to graph areas.

Implement:

- Search by title/body/project/area/tag.
- Focus node by query.
- Focus connected component.
- Show `n matches` count.
- Keyboard shortcuts:
  - `/`: search
  - `Esc`: clear selection/search
  - `F`: focus selected
  - `C`: toggle connected-only
  - `R`: reset viewport/filters

Validation:

- Widget tests for search filter, focus command, shortcut behavior where practical.

## Phase 9 — Layout and viewport polish

Purpose: make the graph usable across screen sizes.

Implement:

- Responsive layout:
  - desktop: graph + side panel
  - tablet: graph + collapsible panel
  - mobile: stacked controls + detail sheet
- Zoom/pan controls if graph view supports it.
- Fit-to-screen action.
- Reduced clutter labels at small widths.
- Empty/loading/error states.

Validation:

- Widget smoke tests for narrow/wide layouts and empty/loading/error states.

## Phase 10 — Graph drill-down panels

Purpose: keep graph visual simple while details remain accessible.

Implement expandable panels:

- isolated nodes
- hub nodes
- overdue cluster
- high-priority nodes
- stale contexts
- goal dependencies
- relation suggestions

Behavior:

- Each row opens Day Page or Node Detail.
- Filter/selection preserved where practical.

Validation:

- Widget tests for expansion and navigation callbacks.

## Phase 11 — Relationship suggestions

Purpose: help users connect useful nodes.

Suggest links based on:

- same project
- same area
- shared tags
- goal/task title similarity
- notes near same day/context
- isolated high-priority tasks

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_relation_suggestions.dart`
  - `GraphRelationSuggestion`
  - `buildGraphRelationSuggestions(...)`

Validation:

- Unit tests for scoring, dedupe, stable ordering.

## Phase 12 — Graph report export

Purpose: share graph health and relationship diagnostics.

Implement markdown export:

- overview metrics
- health status
- hubs
- isolated nodes
- risky nodes
- contexts
- goals/dependencies
- suggestions

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_markdown_export.dart`

Validation:

- Snapshot-style unit tests for report sections.

## Phase 13 — Performance and caching pass

Purpose: keep graph responsive with large local datasets.

Implement:

- Avoid repeated full scans in build.
- Precompute adjacency maps once.
- Precompute incoming/outgoing relation lists.
- Precompute filtered node list once per filter/search.
- Keep helpers pure/testable.
- Consider provider-level memoization only if needed.

Suggested impl:

- Helper:
  - `lib/features/graph/application/graph_index.dart`
  - `GraphIndex`
  - `buildGraphIndex(...)`

Validation:

- Unit tests for adjacency maps and filtered reuse.
- `flutter analyze`
- targeted tests.

## Phase 14 — Accessibility and keyboard pass

Purpose: make graph usable on desktop and assistive tech.

Implement:

- Semantic labels for graph nodes/cards.
- Keyboard shortcuts visible in UI.
- Focus traversal for filters, graph list, side panel.
- Contrast check for risk/priority colors.
- Text fallback list for graph nodes.

Validation:

- Widget shortcut tests if practical.
- Manual narrow-width smoke.

## Phase 15 — Final polish and integration

Purpose: make Graph Page feel connected to Calendar, Day, Insights, and Workspaces.

Implement:

- Route links:
  - Day Page
  - Node Detail
  - Insights filtered by context
  - Workspace detail
- Consistent copy and icon language with Insights.
- Final empty/loading/error polish.
- Final test + analyze pass.

Validation:

- `dart format lib/features/graph test/features/graph`
- `flutter analyze lib/features/graph test/features/graph`
- `flutter test test/features/graph`
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
- Prefer lightweight metadata in `data` for derived state markers.
- Respect strict analyzer:
  - explicit return types
  - no raw types
  - avoid dynamic calls
  - trailing commas
  - no unused private code
- Run after each phase:
  - `dart format lib/features/graph test/features/graph`
  - `flutter analyze lib/features/graph test/features/graph`
  - `flutter test test/features/graph`

## Recommended implementation order

1. Graph mission overview
2. Interactive graph filters
3. Node detail side panel
4. Relationship intelligence
5. Context graph mode
6. Goal dependency map
7. Risk overlay
8. Search and focus controls
9. Layout and viewport polish
10. Graph drill-down panels
11. Relationship suggestions
12. Graph report export
13. Performance and caching pass
14. Accessibility and keyboard pass
15. Final polish and integration

## Definition of done

A phase is done when:

- UI follows cockpit/space visual style.
- Feature works offline/local-first.
- Metrics derive from local repository data.
- Empty/error/loading states exist where relevant.
- Analyzer is clean.
- Relevant tests pass or validation gap is documented.
