# Decision Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full Decision record with weighted criteria, rich options, manual outcome, recommendation, lifecycle, collapse preview, and expanded auto-sizing.

**Architecture:** Extend `DecisionPayload` with small immutable criterion/option models and keep ranking/progress rules in domain code. Reuse persistent-controller and reconstructed-draft protections from Idea and Question in the knowledge editor. Canvas reads the payload for a bounded preview, while `InlineNodeWorkspacePolicy` computes expanded dimensions from structured content.

**Tech Stack:** Flutter, Dart 3.11, Material 3, flutter_test.

---

### Task 1: Structured Decision domain model

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing structured round-trip test**

Create a Decision payload containing status, question, context, owner, dates, confidence, two criteria, two options, scores, selected option, rationale, assumptions, expected outcome, and review notes. Assert `fromNode(toData(...))` preserves every value and unknown root/nested keys.

- [ ] **Step 2: Write failing legacy compatibility test**

Feed legacy `options`, `criteria`, `selectedOption`, and `reason` keys. Assert generated criteria/options are stable, the selected title resolves to an option ID, and writing retains legacy summary keys.

- [ ] **Step 3: Write failing ranking and lifecycle tests**

Assert normalized weighted score, deterministic tie order, `recommendedOptionId`, five progress checkpoints, and non-destructive suggested status.

- [ ] **Step 4: Write failing validation tests**

Cover invalid status, confidence, empty names/titles, non-positive weights, duplicate IDs, unknown score criterion, score outside `1..10`, unknown selected option, and malformed ISO dates.

- [ ] **Step 5: Run focused domain tests**

Run: `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "decision payload" -r expanded`
Expected: FAIL before implementation.

- [ ] **Step 6: Implement minimal domain model**

Add immutable `DecisionCriterion`, `DecisionOption`, and expanded `DecisionPayload`. Use stable IDs, cleanup helpers for criterion/option deletion, nested `decision` map merging, legacy readers/writers, ranking getters, progress, suggested status, `copyWith`, and validation.

- [ ] **Step 7: Re-run focused domain tests**

Expected: PASS.

### Task 2: Persistent Decision editor state

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing draft-echo tests**

Type progressively into decision question, context, rationale, assumptions, expected outcome, and review notes while parent reconstructs a new equivalent `DecisionPayload` after every character. Assert focus and full text survive.

- [ ] **Step 2: Write failing continuous-drag tests**

Drag confidence and one option score through multiple pointer moves. Assert both values increase during one uninterrupted gesture.

- [ ] **Step 3: Run focused editor stability tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "decision" -r expanded`
Expected: FAIL before implementation.

- [ ] **Step 4: Add persistent controllers and focus nodes**

Extend `_KnowledgeEditorState` with Decision controllers/focus nodes, `_sameTypedDraft` value comparison, external update synchronization, blur synchronization, and disposal. Keep list row state stable with ID-based widget keys.

- [ ] **Step 5: Re-run editor stability tests**

Expected: typing and drag tests PASS.

### Task 3: Decision framing and lifecycle UI

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing workflow test**

Assert lifecycle ChoiceChips, suggested-status panel, Apply action, `Decision X/5`, progress indicator, confidence slider, owner/deadline/review fields, and multiline framing fields.

- [ ] **Step 2: Implement workflow controls**

Replace generic `_decisionFields` with status chips, non-destructive suggestion, progress, framing fields, optional date text fields, and continuous confidence slider.

- [ ] **Step 3: Re-run workflow test**

Expected: PASS.

### Task 4: Criteria and options editing

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing criteria CRUD test**

Add two criteria, edit names/weights, delete one, and assert removed criterion scores disappear from every option.

- [ ] **Step 2: Write failing option CRUD test**

Add two options; edit title/description; add/edit/delete pros, cons, and risks; delete an option; assert deleting selected option clears selection.

- [ ] **Step 3: Implement criteria editor**

Render ID-keyed criterion rows with name, positive numeric weight, local validation, delete, and Add criterion action.

- [ ] **Step 4: Implement option editor**

Render ID-keyed option cards with title, description, reusable string-list editors for pros/cons/risks, delete, and Add option action.

- [ ] **Step 5: Re-run CRUD tests**

Expected: PASS without gesture, focus, or rendering exceptions.

### Task 5: Matrix ranking and outcome UI

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing ranking UI test**

Score every option against each criterion. Assert ranked weighted scores, recommended badge, manual outcome control, mismatch suggestion, and Apply recommendation behavior.

- [ ] **Step 2: Implement compact score matrix**

For each option/criterion pair render a continuous `1..10` slider with criterion label and current score. Emit payload updates using option/criterion IDs.

- [ ] **Step 3: Implement ranking and outcome controls**

Show ranked options, manually selectable outcome, recommended option, and Apply action. Never auto-replace manual selection.

- [ ] **Step 4: Re-run ranking UI test**

Expected: PASS.

### Task 6: Collapse preview

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing preview test**

Render a collapsed structured Decision. Assert status, confidence, progress, question, top two ranked options, selected outcome, and review date. Assert third ranked option is absent and no rendering exception occurs.

- [ ] **Step 2: Implement bounded preview**

Replace generic `_DecisionNodeDetails` with structured payload rendering. Limit question to two lines and ranking to two options. Show selected outcome; otherwise show recommendation. Preserve legacy-only fallback.

- [ ] **Step 3: Re-run preview test**

Run: `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "collapsed decision preview" -r expanded`
Expected: PASS.

### Task 7: Expanded auto-size and resize behavior

**Files:**
- Modify: `lib/features/mindmap/domain/inline_node_workspace_policy.dart`
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/domain/inline_node_workspace_policy_test.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing sizing policy test**

Compare empty and detailed Decision records. Assert width is fixed by policy and height grows with text lines, criteria, options, pros/cons/risks, score matrix rows, and suggestion visibility.

- [ ] **Step 2: Write failing resize behavior tests**

Assert expanded Decision ignores persisted custom dimensions and exposes no resize handle. Assert collapsed Decision retains manual resize callback and bottom-right handle.

- [ ] **Step 3: Implement Decision sizing policy**

Add `NodeType.decision` branch to `expandedSizeForNode` using bounded text line estimates and structured item counts.

- [ ] **Step 4: Disable expanded-only resize**

Add Decision to expanded fixed-policy size branches and expanded NodeShell `onResizeChanged: null` condition. Do not change collapsed branch.

- [ ] **Step 5: Re-run sizing and resize tests**

Expected: PASS.

### Task 8: Verification

**Files:**
- Verify all modified Decision files.

- [ ] **Step 1: Format safe Dart files**

Run: `dart format lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`

Do not format the full `mindmap_canvas.dart`; preserve its historical encoding/line structure and patch it through bounded streaming replacement.

- [ ] **Step 2: Run focused tests**

Run domain Decision tests, editor Decision tests, collapse preview test, sizing test, and expanded/collapsed resize tests. Expected: PASS.

- [ ] **Step 3: Run targeted analyzer**

Run: `flutter analyze --no-pub lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/domain/inline_node_workspace_policy.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/domain/inline_node_workspace_policy_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: no new issues.

- [ ] **Step 4: Check whitespace**

Run: `git diff --check -- <all modified files>`
Expected: no whitespace errors. Existing LF/CRLF warnings are informational.
