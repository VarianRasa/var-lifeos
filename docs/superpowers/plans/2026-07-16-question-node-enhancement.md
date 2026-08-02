# Question Node Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membuat node Question sebagai workspace riset terstruktur dengan status, kandidat jawaban, sumber, confidence, progress, dan preview collapse.

**Architecture:** Perluas `QuestionPayload` sebagai sumber aturan domain dan serialisasi flat-key yang kompatibel dengan data lama. Editor memakai controller/focus persisten seperti Idea agar input multiline dan drag slider tidak terputus oleh draft echo. Canvas hanya membaca payload dan merender ringkasan bounded agar tidak overflow.

**Tech Stack:** Flutter, Dart 3.11, Material 3, flutter_test.

---

### Task 1: Question payload domain

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/node_type_payloads_test.dart`

- [ ] **Step 1: Write failing payload tests**

Tambahkan tes round-trip untuk `questionText`, `questionContext`, `possibleAnswers`, `answer`, `evidence`, `questionSources`, `nextResearchAction`, `questionConfidence`, dan `investigationStatus`. Pastikan unknown root key tetap ada setelah `toData`.

- [ ] **Step 2: Write failing rule tests**

Uji `researchCompleted`, `suggestedInvestigationStatus`, status valid, confidence 0..100, dan item list kosong ditolak.

- [ ] **Step 3: Run focused domain tests**

Run: `flutter test --no-pub test/features/mindmap/domain/node_type_payloads_test.dart --name "question payload" -r expanded`
Expected: FAIL sebelum implementasi.

- [ ] **Step 4: Implement minimal payload**

Tambahkan konstanta status, field immutable, `copyWith`, `fromNode`, `toData`, progress empat checkpoint, suggestion non-destruktif, dan validation. Gunakan `_strings`, `_integer`, serta spread `...data` untuk kompatibilitas.

- [ ] **Step 5: Re-run focused domain tests**

Expected: PASS.

### Task 2: Structured Question editor

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/knowledge_node_editors_test.dart`

- [ ] **Step 1: Write failing editor tests**

Tambahkan tes status/suggestion/progress, add-edit-delete possible answers, add-edit-delete sources, accepted answer/evidence/next action emission, multiline typing setelah reconstructed payload echo, dan confidence continuous drag.

- [ ] **Step 2: Run focused editor tests**

Run: `flutter test --no-pub test/features/mindmap/presentation/knowledge_node_editors_test.dart --name "question" -r expanded`
Expected: FAIL sebelum implementasi.

- [ ] **Step 3: Add persistent Question field state**

Tambahkan controller dan focus node untuk question, context, answer, evidence, serta next action. Perluas `_sameTypedDraft`, sync-on-external-update, blur sync, dan disposal mengikuti pola Idea.

- [ ] **Step 4: Build research controls**

Ganti `_questionFields` dengan segmented/status control, suggestion action, progress indicator, multiline fields, editable possible-answer rows, editable source rows, dan slider confidence tanpa `divisions`.

- [ ] **Step 5: Re-run focused editor tests**

Expected: PASS tanpa kehilangan karakter atau putus drag.

### Task 3: Collapsed Question preview

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Write failing collapse test**

Render collapsed Question dan assert status, confidence, progress, question dua baris, maksimal dua possible answers, serta accepted answer atau next research action.

- [ ] **Step 2: Run focused canvas test**

Run: `flutter test --no-pub test/features/mindmap/presentation/mindmap_canvas_test.dart --name "collapsed question preview" -r expanded`
Expected: FAIL sebelum implementasi.

- [ ] **Step 3: Implement bounded preview**

Parse `QuestionPayload.fromNode(node)`, render chip/ringkasan compact, batasi lines/items, pertahankan legacy fallback, dan jangan mengubah resize behavior node.

- [ ] **Step 4: Re-run focused canvas test**

Expected: PASS tanpa rendering exception.

### Task 4: Verification

**Files:**
- Verify all modified files above.

- [ ] **Step 1: Format edited Dart files**

Run: `dart format lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`

Jangan format seluruh `mindmap_canvas.dart`; file besar dan punya histori encoding. Format hanya bila formatter dapat memprosesnya aman.

- [ ] **Step 2: Run all focused tests**

Run tiga perintah test Task 1-3. Expected: PASS.

- [ ] **Step 3: Run targeted analyzer**

Run: `flutter analyze --no-pub lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: no new issues.

- [ ] **Step 4: Check diff whitespace**

Run: `git diff --check -- lib/features/mindmap/domain/node_type_payloads.dart lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/domain/node_type_payloads_test.dart test/features/mindmap/presentation/knowledge_node_editors_test.dart test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: no whitespace errors.
