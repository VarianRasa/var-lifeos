# Insights page enhancement plan

Goal: evolve `lib/features/insights/insights_page.dart` into a local-first productivity intelligence dashboard that turns Day Page and Calendar data into trends, risks, wins, and next actions.

Primary target files:

- `lib/features/insights/insights_page.dart`
- `lib/features/insights/application/*`
- `lib/features/insights/domain/*`
- `lib/features/mindmap/application/mindmap_providers.dart`
- `lib/features/mindmap/domain/mindmap_node.dart`
- Tests under `test/features/insights/...`

Design direction:

- Preserve cockpit/space visual language.
- Keep insights glanceable, not noisy.
- Prefer deterministic/local derived data from existing `MindmapNode` fields.
- Avoid schema changes unless a phase explicitly requires metadata.
- Every card should answer: what changed, why it matters, what to do next.
- Use compact cards, trend chips, sparklines/bars, and collapsible details.

## Phase 1 — Insights mission dashboard

Purpose: summarize current productivity state at a glance.

Implement:

- Top HUD cards:
  - open tasks
  - completed tasks
  - overdue tasks
  - high-priority open
  - focus minutes
  - habit completion
  - journal/review count
- Time windows:
  - today
  - this week
  - this month
- Compare current window with previous matching window.
- Status classification:
  - `Stable`
  - `Improving`
  - `At risk`
  - `Critical`

Suggested impl:

- Helper:
  - `lib/features/insights/application/insights_summary.dart`
  - `InsightsSummary`
  - `InsightsWindow`
  - `buildInsightsSummary(...)`

Validation:

- Unit tests for window boundaries, totals, and status classification.

## Phase 2 — Completion and workload trends

Purpose: show whether workload is growing or being resolved.

Implement:

- Daily completion trend for selected range.
- Open vs done bars.
- Overdue trend.
- High-priority trend.
- Trend labels:
  - up
  - down
  - flat
  - volatile

Suggested impl:

- Helper:
  - `lib/features/insights/application/insights_trends.dart`
  - `InsightTrendPoint`
  - `InsightTrendSeries`
  - `buildCompletionTrend(...)`

Validation:

- Unit tests for stable sorting and trend direction.

## Phase 3 — Habit and routine intelligence

Purpose: identify habit consistency and routine risk.

Implement:

- Habit completion rate per week/month.
- Current streak and longest streak approximation from node history.
- Missed habits.
- Routine markers:
  - skipped
  - snoozed
  - applied
- Cards:
  - `Streak at risk`
  - `Most consistent habit`
  - `Frequently snoozed routine`

Suggested impl:

- Helper:
  - `lib/features/insights/application/habit_insights.dart`
  - `HabitInsightSummary`
  - `HabitStreak`
  - `RoutineInsightSummary`

Validation:

- Unit tests for streaks, missed habits, routine marker counts.

## Phase 4 — Focus and time investment analytics

Purpose: show where attention is going.

Implement:

- Focus minutes by day/week/month.
- Focus minutes by project/area/tag when available.
- Best focus day.
- Low-focus warning when planned work is high.
- Optional estimate from scheduled time blocks when explicit focus minutes absent.

Suggested impl:

- Helper:
  - `lib/features/insights/application/focus_insights.dart`
  - `FocusInsightSummary`
  - `FocusBucket`

Validation:

- Unit tests for focus minute extraction and grouping.

## Phase 5 — Review and journaling insights

Purpose: encourage reflection cadence.

Implement:

- Journal/review count by week/month.
- Last review date.
- Review gaps.
- Journal keywords/tags summary from titles/body/tags.
- Cards:
  - `No review this week`
  - `Reflection streak`
  - `Recurring themes`

Suggested impl:

- Helper:
  - `lib/features/insights/application/review_insights.dart`
  - `ReviewInsightSummary`
  - `ReviewGap`

Validation:

- Unit tests for review detection and gap ranges.

## Phase 6 — Project and area health

Purpose: reveal which contexts are overloaded, neglected, or progressing.

Implement:

- Project/area summary table:
  - open
  - done
  - overdue
  - high priority
  - last activity
- Health score:
  - good
  - watch
  - stale
  - critical
- Neglected contexts list.
- Hot contexts list.

Suggested impl:

- Helper:
  - `lib/features/insights/application/context_health.dart`
  - `ContextHealthSummary`
  - `ContextHealthItem`

Validation:

- Unit tests for health scoring and last activity.

## Phase 7 — Goal and milestone progress

Purpose: make long-term progress visible.

Implement:

- Goal nodes summary.
- Progress distribution.
- Milestone completion where available in node data.
- Stalled goals.
- Recently progressed goals.
- Cards:
  - `Goal needs next action`
  - `Milestone momentum`

Suggested impl:

- Helper:
  - `lib/features/insights/application/goal_insights.dart`
  - `GoalInsightSummary`
  - `GoalProgressItem`

Validation:

- Unit tests for progress parsing and stalled goal detection.

## Phase 8 — Smart risk detection

Purpose: surface actionable warnings before work slips.

Implement risks:

- overdue cluster
- high-priority overload
- no review this week
- habit streak at risk
- project stale with open tasks
- many tasks without schedule
- repeated snoozing
- workload increasing while completion drops

Suggested impl:

- Helper:
  - `lib/features/insights/application/insight_risk_engine.dart`
  - `InsightRisk`
  - `InsightRiskSeverity`
  - `InsightRiskActionType`

Validation:

- Deterministic unit tests for each risk.

## Phase 9 — Recommendations and next actions

Purpose: convert insights into specific actions.

Implement actions:

- open Calendar with date/range
- open Day Page for review
- filter by project/area
- create weekly review
- schedule overdue tasks
- apply day template
- balance workload
- export report

Suggested impl:

- Helper:
  - `lib/features/insights/application/insight_recommendations.dart`
  - `InsightRecommendation`
  - `InsightRecommendationAction`
- UI action buttons can route to existing pages first.

Validation:

- Unit tests for recommendation priority and stable ordering.

## Phase 10 — Insight filters and range controls

Purpose: allow users to inspect different periods and scopes.

Implement controls:

- date range selector:
  - today
  - 7 days
  - 30 days
  - this month
  - custom range later
- filters:
  - project
  - area
  - tag
  - node type
  - priority
  - status
- Clear filters CTA.

Suggested impl:

- Helper:
  - `lib/features/insights/application/insight_filters.dart`
  - `InsightFilterState`
  - `matchesInsightFilter(...)`

Validation:

- Unit tests for predicate combinations.

## Phase 11 — Markdown insight report export

Purpose: share progress and reviews.

Implement export scopes:

- current dashboard range
- this week
- this month
- project/area summary

Include:

- summary metrics
- trend highlights
- risks
- recommendations
- completed tasks
- overdue tasks
- focus minutes
- habit/review status

Suggested impl:

- Helper:
  - `lib/features/insights/application/insights_markdown_export.dart`

Validation:

- Snapshot-style unit tests for report sections.

## Phase 12 — Insight drill-down panels

Purpose: keep top dashboard simple while allowing detail.

Implement expandable panels:

- overdue tasks detail
- high-priority tasks detail
- project/area detail
- habit detail
- review detail
- goal detail

Behavior:

- Each item links to Day Page or node detail.
- Preserve selected filters.

Suggested impl:

- UI in `insights_page.dart` first.
- Extract widgets if file grows too large.

Validation:

- Widget smoke tests for expansion and navigation callbacks.

## Phase 13 — Visual polish and empty states

Purpose: make insights useful with sparse data.

Implement:

- Empty state for new users.
- Loading/error states for providers.
- Skeleton cards.
- Low-clutter color coding.
- Responsive layout:
  - desktop grid
  - tablet 2-column
  - mobile stacked cards
- Short helper copy explaining metrics.

Validation:

- Widget tests for empty/loading/error states where practical.

## Phase 14 — Performance and caching pass

Purpose: keep dashboard fast with large local datasets.

Implement:

- Avoid repeated range scans in build.
- Precompute filtered node list once per range/filter.
- Reuse shared summary maps.
- Keep helpers pure/testable.
- Consider provider-level memoization only if needed.

Validation:

- `flutter analyze`
- targeted tests
- manual smoke with large seeded node list if feasible.

## Phase 15 — Accessibility and keyboard shortcuts

Purpose: make insights usable on desktop and assistive tech.

Implement:

- Semantic labels for charts/cards.
- Keyboard shortcuts:
  - `T`: today range
  - `W`: week range
  - `M`: month range
  - `/`: focus filter/search
  - `E`: export report
  - `R`: refresh/recompute
- Visible shortcut hints.
- Contrast check for risk/severity colors.

Validation:

- Widget shortcut tests if practical.
- Manual narrow-width smoke.

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
  - `dart format lib/features/insights ... test/features/insights ...`
  - `flutter analyze lib/features/insights ...`
  - targeted tests

## Recommended implementation order

1. Insights mission dashboard
2. Completion and workload trends
3. Insight filters and range controls
4. Smart risk detection
5. Recommendations and next actions
6. Habit and routine intelligence
7. Focus and time investment analytics
8. Review and journaling insights
9. Project and area health
10. Goal and milestone progress
11. Markdown insight report export
12. Insight drill-down panels
13. Visual polish and empty states
14. Performance and caching pass
15. Accessibility and keyboard shortcuts

## Definition of done

A phase is done when:

- UI follows cockpit/space visual style.
- Feature works offline/local-first.
- Metrics derive from local repository data.
- Empty/error/loading states exist.
- Analyzer is clean.
- Relevant tests pass or validation gap is documented.
