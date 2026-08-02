# Idea Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured incubation, experiment guidance, and useful collapsed preview to Idea nodes without migrating existing data.

**Architecture:** Extend the existing flat `IdeaPayload`, keep derivation methods pure in domain code, render controls through `knowledge_node_editors.dart`, and replace generic canvas details with a structured summary. Existing `maturity`, `evidence`, and `nextAction` keys remain backward compatible.

**Tech Stack:** Flutter, Dart 3.11, Material 3, flutter_test.

---

### Task 1: Extend IdeaPayload

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart:585`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart:444`

- [ ] **Step 1: Add failing payload tests**

Test round-trip for `hypothesis`, `impact`, `effort`, `confidence`, unknown key preservation, progress count, suggested stage, and invalid confidence.

```dart
const payload = IdeaPayload(
  maturity: 'exploring',
  hypothesis: 'Users need faster capture',
  impact: 'high',
  effort: 'medium',
  confidence: 70,
  evidence: 'Five interviews',
  nextAction: 'Build prototype',
);
expect(payload.validationCompleted, 3);
expect(payload.suggestedMaturity, 'validated');
expect(payload.validate(title: 'Capture').isEmpty, isTrue);
expect(payload.copyWith(confidence: 101).validate(title: 'Capture'), isNotEmpty);
```

- [ ] **Step 2: Run payload test and confirm failure**

Run: `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "idea payload" -r expanded`
Expected: FAIL because new fields and derivations do not exist.

- [ ] **Step 3: Implement minimal payload extension**

Add fields, `copyWith`, `fromNode`, `toData`, confidence validation, `validationCompleted`, and `suggestedMaturity`. Use existing flat keys and preserve unknown data.

- [ ] **Step 4: Run payload tests**

Run: `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "idea payload|thinking payloads" -r expanded`
Expected: PASS.

### Task 2: Build Structured Idea Editor

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart:509`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Add failing editor test**

Render an Idea draft and assert lifecycle controls, hypothesis, impact, effort, confidence, evidence, next experiment, progress, and suggestion banner exist. Interact with controls and verify emitted `IdeaPayload`.

- [ ] **Step 2: Run editor test and confirm failure**

Run: `flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "idea editor" -r expanded`
Expected: FAIL because structured controls are absent.

- [ ] **Step 3: Implement editor controls**

Replace free-text maturity with Material segmented/chip controls. Add multiline fields, confidence input, progress indicator, and non-mutating suggestion action. Reuse existing `_field` and `_fields` helpers where possible.

- [ ] **Step 4: Run editor tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "idea editor|field state" -r expanded`
Expected: PASS.

### Task 3: Add Collapsed Idea Preview

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart:10659`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Add failing preview test**

Create an Idea node with all structured fields. Assert stage, impact, effort, hypothesis, `3/3`, and next experiment are visible with no framework exception.

- [ ] **Step 2: Run preview test and confirm failure**

Run: `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "collapsed idea preview" -r expanded`
Expected: FAIL because `_IdeaNodeDetails` only reads body lines.

- [ ] **Step 3: Implement structured summary**

Render compact stage and score badges, two-line hypothesis, validation progress, and two-line next experiment. Fall back to body lines for legacy ideas with no structured fields. Avoid internal scrolling.

- [ ] **Step 4: Run preview tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "collapsed idea preview" -r expanded`
Expected: PASS without overflow.

### Task 4: Verify Integration

**Files:**
- Verify all modified Dart files.

- [ ] **Step 1: Format modified Dart files**

Run: `dart format lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart`

Do not format the full oversized canvas file; format only targeted changes if required.

- [ ] **Step 2: Run focused tests**

Run all payload, editor, and collapsed preview test filters. Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze --no-pub lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: `No issues found!`

- [ ] **Step 4: Check diff hygiene**

Run: `git diff --check --` for modified files. Expected: no whitespace errors.

No commit step: repository policy requires explicit user request before committing.
