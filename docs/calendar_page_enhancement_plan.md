# Calendar page enhancement plan

Goal: evolve `lib/features/calendar/calendar_page.dart` into a tactical planning hub that connects month/week/day navigation with Var's local-first productivity model.

Primary target files:

- `lib/features/calendar/calendar_page.dart`
- `lib/features/calendar/day_page.dart`
- `lib/features/calendar/application/*`
- `lib/features/calendar/domain/*`
- `lib/features/mindmap/application/mindmap_providers.dart`
- `lib/features/mindmap/domain/mindmap_node.dart`
- `lib/core/router/app_router.dart`
- Tests under `test/features/calendar/...`

Design direction:

- Preserve cockpit/space visual language.
- Keep the calendar fast, glanceable, and low-clutter.
- Use collapsible HUD panels and compact chips.
- Every feature must work offline/local-first.
- Prefer derived metadata from existing `MindmapNode` fields first.
- Avoid `MindmapNode` schema changes unless a phase explicitly requires it.
- Calendar should summarize days, not duplicate the Day Page.

## Phase 1 — Calendar mission overview

Purpose: make month/week grid show day load at a glance.

Implement:

- Per-day indicators:
  - total nodes
  - open tasks
  - completed tasks
  - overdue tasks
  - high-priority count
  - habit completion
  - focus minutes
  - journal/review exists
- Visual day status:
  - `Clear` = low load, no overdue
  - `Busy` = many open tasks
  - `Critical` = overdue or high-priority overload
  - `Complete` = all task-like work done
- Add compact legend.
- Selected day summary card below/side of calendar.

Suggested impl:

- Helper:
  - `lib/features/calendar/application/calendar_day_summary.dart`
  - `CalendarDaySummary`
  - `buildCalendarDaySummary(DateTime day, List<MindmapNode> nodes)`
  - `buildCalendarRangeSummaries(...)`
- Reuse logic from Day Page mission stats where possible, but keep helper public/testable.

Validation:

- Unit tests for day summary and status classification.
- `flutter analyze lib/features/calendar/calendar_page.dart`

## Phase 2 — Week strip and workload balance

Purpose: help users see the current week without opening each day.

Implement:

- 7-day workload strip for selected week.
- Bars/dots for:
  - open tasks
  - completed tasks
  - focus minutes
  - habits
- Highlight today and selected day.
- Tap day → select/navigate.
- Show weekly totals:
  - open
  - done
  - overdue
  - focus minutes
  - review count

Suggested impl:

- Helper:
  - `lib/features/calendar/application/calendar_week_summary.dart`
  - `CalendarWeekSummary`
  - `buildCalendarWeekSummary(...)`
- Keep UI in `calendar_page.dart` initially.

Validation:

- Unit tests for week boundaries and totals.

## Phase 3 — Drag/drop day reschedule

Purpose: move tasks between days directly from calendar.

Implement:

- Drag task chip from selected-day agenda to a calendar date.
- Drop → update node day.
- Optional duplicate with modifier/control if platform feasible later.
- Drop feedback:
  - valid day highlight
  - snackbar confirmation
  - undo action
- Refresh derived state for source and target days.

Suggested impl:

- Calendar date cells accept `DragTarget<MindmapNode>`.
- Agenda items are `Draggable<MindmapNode>` for task-like nodes.
- Mutation through existing repository.
- Call `invalidateMindmapState(ref, day: sourceDay, extraDay: targetDay)`.

Validation:

- Widget smoke test for drag/drop if feasible.
- Unit test helper for reschedule metadata if extracted.

## Phase 4 — Quick add from calendar

Purpose: capture work without entering Day Page.

Implement:

- Quick add button on selected date.
- Mini command input:
  - `task bayar listrik p1 #home`
  - `event meeting 14:00-15:00 @work`
  - `habit workout daily`
  - `note idea #product`
- Reuse quick command parser.
- Selected date is default target day.
- Unsupported text creates note/task gracefully.

Suggested impl:

- Shared helper if Day Page quick capture has duplicate logic:
  - `lib/features/calendar/application/calendar_quick_capture.dart`
- Keep UI as bottom sheet/dialog.

Validation:

- Parser integration tests.
- Widget smoke test for quick add button.

## Phase 5 — Agenda sidebar / bottom panel

Purpose: show selected day's actionable nodes without opening Day Page.

Implement:

- Responsive layout:
  - desktop/tablet: right sidebar
  - mobile: bottom expandable panel
- Group nodes by:
  - overdue
  - missions/high priority
  - scheduled
  - tasks
  - habits/routines
  - notes/journals
- Inline actions:
  - mark done
  - move tomorrow
  - start focus
  - archive/cancel
  - open Day Page
- Empty agenda actions:
  - plan day
  - apply template
  - quick capture
  - import leftovers

Suggested impl:

- Helper:
  - `lib/features/calendar/application/calendar_agenda_builder.dart`
  - `CalendarAgendaSection`
  - `CalendarAgendaItem`
- Mutations remain in page/controller first.

Validation:

- Unit tests for grouping.
- Widget test for empty agenda CTAs.

## Phase 6 — Month heatmap modes

Purpose: turn the calendar into a progress dashboard.

Implement heatmap mode selector:

- Workload
- Completion
- Habits
- Focus
- Journaling
- Overdue

Each date cell color/intensity derives from selected metric.

Suggested impl:

- Domain/application:
  - `CalendarHeatmapMode`
  - `CalendarHeatmapScore`
  - `scoreCalendarDay(summary, mode)`
- UI:
  - segmented chips in calendar HUD
  - tooltip/semantics label per day

Validation:

- Unit tests for scoring/clamping.

## Phase 7 — Smart planning suggestions

Purpose: guide weekly/monthly planning from the calendar page.

Implement suggestions:

- `Overloaded tomorrow`
- `3 overdue tasks need scheduling`
- `No review this week`
- `Habit streak at risk`
- `High-priority cluster on Wednesday`
- `Empty weekend — plan reset?`

Suggested impl:

- Helper:
  - `lib/features/calendar/application/calendar_planning_engine.dart`
  - `CalendarPlanningContext`
  - `CalendarPlanningSuggestion`
  - `CalendarPlanningActionType`
  - `CalendarPlanningSeverity`
- Reuse Day Page `daily_planning_engine.dart` models only if clean; avoid tight coupling.

Validation:

- Deterministic unit tests.

## Phase 8 — Templates from calendar

Purpose: set up days/weeks directly from calendar.

Implement:

- Apply day template to selected date.
- Apply template to multiple selected dates.
- Suggested templates based on weekday:
  - workday on weekdays
  - weekend/personal reset on weekends
  - weekly review on Friday/Sunday
- Duplicate protection via existing template marker.

Suggested impl:

- Reuse `day_templates.dart`.
- Add selected-date/multi-date state.
- Mutations through repository.

Validation:

- Unit tests for duplicate detection across selected dates.
- Widget smoke for template picker.

## Phase 9 — Multi-select date planning

Purpose: plan and operate on date ranges.

Implement:

- Shift/long-press range selection.
- Actions for selected range:
  - apply template
  - export summary
  - clear selection
  - balance workload
  - show totals
- Range summary panel:
  - total tasks
  - completed
  - overdue
  - focus minutes
  - journals
  - habit completions

Suggested impl:

- Helper:
  - `CalendarRangeSummary`
  - `buildCalendarRangeSummary(...)`
- UI can start with explicit `Select range` mode for simplicity.

Validation:

- Unit tests for inclusive date ranges.

## Phase 10 — Workload balancing assistant

Purpose: reduce overloaded days.

Implement:

- Detect overloaded days in visible month/week.
- Suggest low-priority movable tasks.
- Find lighter target days.
- Actions:
  - move one task
  - spread all low-priority tasks
  - preview changes
- Keep deterministic/local.

Suggested impl:

- Helper:
  - `lib/features/calendar/application/workload_balancer.dart`
  - `WorkloadBalancePlan`
  - `WorkloadMoveSuggestion`
- Use node priority/status/type and day summary load score.

Validation:

- Unit tests for target-day selection and stable sorting.

## Phase 11 — Calendar search and filters

Purpose: find days/nodes quickly from the calendar.

Implement filters:

- text search
- project
- area
- tag
- type
- status
- priority
- has schedule
- has journal
- has overdue

Behavior:

- Matching dates glow/outline.
- Agenda shows matching nodes first.
- Clear filters CTA.

Suggested impl:

- Reuse Day Page context filters where practical.
- Extract common filter predicate if duplication grows:
  - `lib/features/calendar/application/node_filtering.dart`

Validation:

- Unit tests for predicate combinations.

## Phase 12 — Calendar export/share

Purpose: share weekly/monthly progress.

Implement markdown export:

- selected day
- selected range
- current week
- current month

Include:

- summary stats
- completed tasks
- open tasks
- overdue tasks
- focus minutes
- habit status
- journals/reviews
- planning suggestions

Suggested impl:

- Helper:
  - `lib/features/calendar/application/calendar_markdown_export.dart`
- UI:
  - copy markdown action

Validation:

- Snapshot-style unit tests for markdown sections.

## Phase 13 — Navigation polish and keyboard shortcuts

Purpose: make calendar page efficient on desktop.

Implement shortcuts:

- arrow keys: move selected day
- PageUp/PageDown: previous/next month
- Home/End: start/end of week
- Enter: open Day Page
- `T`: today
- `N`: quick add
- `/`: search/filter

Add visible shortcut hints in command HUD.

Validation:

- Widget tests for core shortcuts if practical.

## Phase 14 — Calendar activity and undo

Purpose: make direct calendar operations safe.

Implement activity log:

- created node
- moved node to date
- completed task
- applied template
- balanced workload
- exported summary

Undo where safe:

- reschedule
- mark done
- archive/cancel
- apply template batch

Suggested impl:

- Reuse or mirror Day Page activity model.
- Keep in-memory first unless existing persistence supports it.

Validation:

- Unit tests for undo records if extracted.

## Phase 15 — Calendar performance/accessibility pass

Purpose: keep enhanced calendar fast and accessible.

Implement:

- Avoid repeated O(days × nodes) recomputation in build.
- Cache summaries per visible range where safe.
- Add semantic labels for date cells and heatmap states.
- Ensure high contrast for heatmap modes.
- Ensure mobile layout does not overflow.
- Add loading/error/empty states for provider data.

Validation:

- `flutter analyze`
- targeted widget tests
- manual smoke on narrow width if feasible

## Implementation rules for agents

- Keep changes small: one phase per turn/PR.
- Add tests for domain/application helpers before complex UI.
- Do not change `MindmapNode` persistence schema unless necessary.
- Reuse existing node fields:
  - `day`
  - `status`
  - `priority`
  - `tags`
  - `project`
  - `area`
  - `data`
  - `relatedNodeIds`
- Use metadata keys in `data` for new lightweight state.
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
  - `dart format lib/features/calendar/calendar_page.dart ...`
  - `flutter analyze lib/features/calendar/calendar_page.dart`
  - targeted tests

## Recommended implementation order

1. Calendar mission overview
2. Agenda sidebar / bottom panel
3. Quick add from calendar
4. Week strip and workload balance
5. Month heatmap modes
6. Calendar search and filters
7. Smart planning suggestions
8. Drag/drop day reschedule
9. Templates from calendar
10. Multi-select date planning
11. Workload balancing assistant
12. Calendar export/share
13. Navigation polish and keyboard shortcuts
14. Calendar activity and undo
15. Performance/accessibility pass

## Definition of done

A phase is done when:

- UI follows cockpit/space visual style.
- Feature works offline/local-first.
- Mutations persist through repository when applicable.
- Derived providers refresh correctly.
- Empty/error states exist.
- Analyzer is clean.
- Relevant tests pass or validation gap is documented.
