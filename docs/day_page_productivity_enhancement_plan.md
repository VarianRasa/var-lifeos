# Day page productivity enhancement plan

Goal: evolve `lib/features/calendar/day_page.dart` into a complete daily productivity cockpit while preserving Var's local-first mindmap model.

Primary target files:

- `lib/features/calendar/day_page.dart`
- `lib/features/mindmap/application/mindmap_providers.dart`
- `lib/features/mindmap/domain/mindmap_node.dart`
- `lib/features/mindmap/domain/*progress*.dart`
- `lib/features/mindmap/presentation/mindmap_canvas.dart`
- `lib/features/mindmap/presentation/node_editor_panel.dart`
- Tests under matching `test/features/...` paths

Design direction:

- Keep the existing space/cockpit visual language.
- Avoid clutter. Prefer collapsible HUD panels.
- Every feature should work offline/local-first.
- Prefer rule-based local automation first; AI/remote services optional later.
- Reuse existing `MindmapNode`, `NodeType`, status, priority, tags, project, area, relation fields.

## Phase 1 — Mission dashboard

Purpose: give an at-a-glance daily command center.

Implement:

- Add a top/upper-left collapsible `Mission status` HUD near Smart plan.
- Show:
  - total nodes
  - open tasks
  - completed tasks
  - overdue tasks
  - high-priority count
  - routines available/applied
  - habit completion count
  - day completion percentage
- Add simple status label:
  - `Clear orbit` = low load, no overdue
  - `Busy sector` = many open tasks
  - `Critical` = overdue/high-priority overload
- Derive data from existing node list; avoid new persistence first.

Suggested impl:

- Create private view model in `day_page.dart`:
  - `_DailyMissionStats`
  - `_buildDailyMissionStats(List<MindmapNode> nodes, DateTime day)`
- Widget:
  - `_DailyMissionDashboard`
  - `_MissionMetricChip`
- Use cockpit painter style from current Smart plan HUD.

Validation:

- Add pure unit tests for `_DailyMissionStats` only if moved to testable application/domain file.
- Run `flutter analyze lib/features/calendar/day_page.dart`.

## Phase 2 — Carry-over assistant

Purpose: unfinished work from previous days should be easy to move, reschedule, split, or archive.

Implement:

- Detect unfinished task-like nodes before selected day:
  - `NodeType.task`
  - plans with incomplete steps
  - habits/routines not completed if relevant
- Add Smart plan suggestions:
  - `Carry over N tasks`
  - `Review overdue`
  - `Reschedule low priority`
- Add dialog/bottom sheet:
  - list unfinished nodes
  - actions per node:
    - move to today
    - duplicate to today
    - reschedule date
    - mark done
    - archive/cancel
    - split checklist into child tasks

Suggested impl:

- Application helper:
  - `lib/features/calendar/application/carry_over_planner.dart`
  - `CarryOverCandidate`
  - `CarryOverAction`
- Keep mutation in `day_page.dart` initially using existing repository callbacks/provider invalidation.
- Use `invalidateMindmapState(ref, day: ..., extraDay: ...)` after changes.

Validation:

- Unit tests for candidate detection.
- Widget smoke test for dialog if practical.

## Phase 3 — Daily review journal

Purpose: close the loop at end of day and feed tomorrow planning.

Implement:

- Add `Start daily review` Smart plan action.
- Create or open a `NodeType.journal` node for selected day.
- Review sections:
  - Wins
  - Completed
  - Blocked
  - Lessons
  - Carry to tomorrow
  - Tomorrow top 3
- Auto-prefill summary from day's nodes.
- Add CTA: `Create tomorrow top 3` from review text/checklist.

Suggested impl:

- Helper:
  - `_buildDailyReviewBody(DateTime day, List<MindmapNode> nodes)`
- Node title format:
  - `Daily review — yyyy-mm-dd`
- Position near current canvas center or below existing journal nodes.

Validation:

- Unit test review body generation if moved outside widget.

## Phase 4 — Time-block timeline upgrades

Purpose: turn nodes into an actual day schedule.

Current app has Timeline tab; enhance it.

Implement:

- Drag/drop node into timeline slot.
- Add start/end metadata to node `data`:
  - `timeBlockStart`
  - `timeBlockEnd`
  - ISO local strings or minutes-since-midnight
- Timeline visual states:
  - scheduled
  - unscheduled
  - conflict
  - done
- Conflict detection:
  - overlapping event/task blocks
  - too many high-priority tasks in same window
- Quick actions:
  - schedule next available
  - clear schedule
  - extend 15m
  - mark done

Suggested impl:

- Domain helper:
  - `lib/features/calendar/domain/time_block.dart`
  - `DayTimeBlock`
  - `detectTimeBlockConflicts(...)`
- Presentation widgets stay in `day_page.dart` until large enough to extract.

Validation:

- Pure tests for conflict detection.

## Phase 5 — Quick capture command

Purpose: frictionless capture from day page.

Implement:

- Floating cockpit input: `Quick capture`.
- Example commands:
  - `task bayar listrik p1 #home`
  - `event meeting 14:00-15:00 @work`
  - `habit workout daily`
  - `note idea aplikasi baru #product`
- Reuse existing command parsing when possible:
  - `features/command/quick_create_command_parser.dart`
  - `features/command/command_date_parser.dart`
- Create node on selected day by default.

Suggested impl:

- UI:
  - collapsed pill near search/toolbar
  - expanded text field with suggestions
- Parser should return `CalendarNodePayload` or node draft.
- Keep unsupported syntax graceful: create note/task with raw text.

Validation:

- Parser tests.
- Day page smoke test if feasible.

## Phase 6 — Templates per day

Purpose: one-click day setup.

Implement templates:

- Workday
- Weekend
- Study day
- Weekly review
- Sprint planning
- Personal reset

Each template can create:

- tasks
- plan node
- journal node
- habit/routine nodes
- focus goals

Suggested impl:

- Domain/application file:
  - `lib/features/calendar/application/day_templates.dart`
  - `DayTemplate`
  - `DayTemplateNodeDraft`
- Smart plan action: `Apply template`.
- Avoid duplicate spam: detect existing template marker in node tags/data.

Validation:

- Unit tests for template node generation.

## Phase 7 — Focus / mission mode

Purpose: protect attention.

Implement:

- Select 1–3 priority nodes as `Today's mission`.
- Toggle `Mission mode`:
  - dim/hide other nodes
  - show timer/stopwatch
  - show next action
- Store focus sessions locally in node `data` initially:
  - `focusSessions`: list of `{startedAt, endedAt, durationMinutes}`
- Optional Pomodoro presets:
  - 25/5
  - 50/10
  - custom

Suggested impl:

- UI state can start in `day_page.dart`.
- Later extract focus session controller/provider.

Validation:

- Ensure timer lifecycle cancels subscriptions/controllers.

## Phase 8 — Node inbox

Purpose: handle undated/loose capture.

Implement:

- Panel: `Inbox`.
- Show nodes with no day or placeholder day if model supports it.
- If current model requires day, use tag/data marker for inbox until model evolves.
- Actions:
  - assign today
  - assign tomorrow
  - convert type
  - archive
  - link to selected node

Suggested impl:

- First verify whether `MindmapNode.day` can be nullable. If not, do not change schema casually.
- Prefer non-breaking metadata approach first.

Validation:

- Persistence migration only if schema changes.

## Phase 9 — Context switcher and saved day filters

Purpose: manage dense days.

Implement filters:

- project
- area
- tag
- type
- status
- priority
- energy level if added later

Enhance:

- Saved views:
  - `Deep work`
  - `Errands`
  - `Waiting`
  - `Habits`
- Apply to canvas, timeline, board, table consistently.

Suggested impl:

- Reuse existing search/filter state in `mindmap_canvas.dart` where possible.
- Add day-level filter state in `day_page.dart` for non-canvas tabs.

## Phase 10 — Command suggestions for selected node

Purpose: make every selected node actionable.

Implement command chips based on node type/status:

- Convert to task
- Schedule
- Split into checklist
- Create follow-up
- Link related
- Move to tomorrow
- Mark done
- Start focus session
- Create review note

Suggested impl:

- Helper:
  - `_selectedNodeActions(MindmapNode node)`
- Show in editor side panel or Smart plan area.

## Phase 11 — Better empty state

Purpose: zero-friction start for empty days.

When no nodes:

- `Plan my day`
- `Import yesterday leftovers`
- `Start journal`
- `Apply routine`
- `Use template`
- `Quick capture`

Use cockpit cards, not plain text.

## Phase 12 — Smart automation engine

Purpose: centralize all local suggestions.

Implement:

- `lib/features/calendar/application/daily_planning_engine.dart`
- Models:
  - `DailyPlanningContext`
  - `DailyPlanningSuggestionModel`
  - `DailyPlanningActionType`
  - `DailyPlanningSeverity`
- Inputs:
  - selected day
  - today's nodes
  - previous unfinished nodes
  - active goals
  - routines
  - habits
- Outputs suggestions used by Smart plan UI.

Rules:

- no remote calls
- deterministic
- test heavily
- UI maps model actions to callbacks

Later AI can plug in behind same interface.

## Phase 13 — Heatmap mini insights

Purpose: show progress trends without leaving day page.

Implement:

- 7-day strip:
  - task completion
  - habits
  - focus sessions
  - journal/review done
- Use compact cockpit mini panel.
- Click a day → navigate.

## Phase 14 — Undo/history activity polish

Purpose: confidence and recoverability.

Implement:

- Activity log panel:
  - created node
  - moved node
  - edited status
  - completed task
  - applied template
  - carried over task
- Reuse existing undo stack if present in `day_page.dart`.
- Add restore/action-specific undo where safe.

## Phase 15 — Export/share day

Purpose: useful output for review/reporting.

Implement export Markdown:

- Day summary
- Mission stats
- Completed tasks
- Open tasks
- Notes/journal
- Links/resources
- Decisions
- Tomorrow carry-over

Suggested actions:

- Copy markdown
- Save file later per platform support

## Implementation rules for agents

- Keep changes small per PR/turn: one phase at a time.
- Add tests for domain/application logic before complex UI when possible.
- Do not change `MindmapNode` persistence schema unless necessary.
- If schema changes are needed, add migration and backward compatibility.
- Always refresh derived state after mutations:
  - `invalidateMindmapState(ref, day: ..., extraDay: ...)`
  - or `invalidateMindmapStateFromRef(...)`
- Respect strict analyzer:
  - explicit return types
  - no raw types
  - avoid dynamic calls
  - trailing commas
  - no unused private code
- Run after each phase:
  - `dart format lib/features/calendar/day_page.dart ...`
  - `flutter analyze lib/features/calendar/day_page.dart`
  - targeted tests

## Recommended implementation order

1. Mission dashboard
2. Daily planning engine foundation
3. Carry-over assistant
4. Daily review journal
5. Quick capture command
6. Templates per day
7. Time-block timeline upgrades
8. Focus / mission mode
9. Context switcher/saved filters
10. Empty state polish
11. Node inbox
12. Command suggestions
13. Heatmap mini insights
14. Undo/history activity polish
15. Export/share day

## Definition of done

A phase is done when:

- UI follows cockpit/space visual style.
- Feature works offline.
- Mutations persist through repository.
- Derived providers refresh correctly.
- Empty/error states exist.
- Analyzer is clean.
- Relevant tests pass or validation gap is documented.
