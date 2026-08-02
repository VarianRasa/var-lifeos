# Online Quote Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Firebase-backed author and quote discovery to Quote nodes while retaining local manual editing and offline snapshots.

**Architecture:** Pure Dart catalog contracts isolate provider data. A Firebase callable adapter is injected through Riverpod. Quote editor composes a standalone discovery panel. TypeScript Cloud Functions validate requests and proxy a configurable Quotable-compatible upstream.

**Tech Stack:** Flutter, Dart, Riverpod, Firebase Cloud Functions callable API, TypeScript, Node test runner.

---

### Task 1: Catalog domain

**Files:**
- Create: `lib/features/mindmap/domain/quote_catalog.dart`
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/quote_catalog_test.dart`

- [ ] Define author, quote, page, exception, and repository contracts.
- [ ] Add strict map parsers and bounded values.
- [ ] Extend `QuotePayload` with remote attribution fields.
- [ ] Add parsing and payload round-trip tests.

### Task 2: Firebase adapter and providers

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/mindmap/data/firebase_quote_catalog.dart`
- Create: `lib/features/mindmap/application/quote_catalog_providers.dart`
- Test: `test/features/mindmap/data/firebase_quote_catalog_test.dart`

- [ ] Add `cloud_functions` dependency.
- [ ] Wrap callable invocation behind a testable client interface.
- [ ] Map callable payloads into domain pages.
- [ ] Return unsupported repository on non-Firebase desktop platforms.
- [ ] Test request names, arguments, malformed responses, and errors.

### Task 3: Discovery UI

**Files:**
- Create: `lib/features/mindmap/presentation/node_editors/quote_discovery_panel.dart`
- Modify: `lib/features/mindmap/presentation/node_editors/knowledge_node_editors.dart`
- Test: `test/features/mindmap/presentation/quote_discovery_panel_test.dart`

- [ ] Add Discover and Write manually modes.
- [ ] Load popular authors and debounce author search.
- [ ] Load paginated quotes for selected author.
- [ ] Add loading, empty, retry, error, and unsupported states.
- [ ] Apply selected quote through body and typed-draft callbacks.
- [ ] Test selection, search, retry, pagination, and manual fallback.

### Task 4: Firebase Functions proxy

**Files:**
- Modify: `firebase.json`
- Create: `functions/package.json`
- Create: `functions/tsconfig.json`
- Create: `functions/src/index.ts`
- Create: `functions/src/quote_provider.ts`
- Create: `functions/test/quote_provider.test.ts`

- [ ] Configure TypeScript Functions v2 workspace.
- [ ] Implement bounded input parsers and provider adapter.
- [ ] Implement popular authors, author search, and quote listing callables.
- [ ] Add timeout and stable `HttpsError` mapping.
- [ ] Test validation, normalization, pagination, timeout, and partial results.

### Task 5: Integration validation

**Files:**
- Verify all modified files.

- [ ] Run Dart formatting.
- [ ] Run focused Flutter tests.
- [ ] Run Functions tests and build.
- [ ] Run Flutter analyzer on modified files.
- [ ] Preserve manual Quote behavior when Firebase is unavailable.