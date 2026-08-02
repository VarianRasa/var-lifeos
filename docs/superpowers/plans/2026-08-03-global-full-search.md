# Global Full Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build offline global search across nodes, boards, comments, attachment metadata, document text, image OCR, and audio/video transcripts.

**Architecture:** Authoritative repositories feed normalized `SearchDocument` records into a local SQLite FTS5 index. Extraction runs through local-first adapters with permission-gated cloud fallback; Command Palette and dedicated Search page query one Riverpod service. Derived index data is rebuildable and never becomes source of truth.

**Tech Stack:** Flutter, Dart 3.11.4, Riverpod 2.6.1, go_router 14.6.2, `sqlite3`, `sqlite3_web`, SQLite FTS5, existing Sembast source repositories.

## Global Constraints

- Search remains offline after first successful processing.
- Filters: date, type, workspace, board, creator, and status.
- Ranking combines FTS relevance, recency, and active-workspace boost; filters are hard constraints.
- Cloud OCR/transcription is disabled by default and requires one explicit Settings opt-in.
- Local-only content never uploads.
- Extraction failure never rolls back or hides captured source content.
- Search-derived data can be deleted and rebuilt from authoritative sources.
- No semantic/vector search, automatic duplicate merging, or background recrawling.
- Never expose results outside current workspace permissions.

---

### Task 1: Search Domain Contract and Ranking

**Files:**
- Create: `lib/features/search/domain/search_document.dart`
- Create: `lib/features/search/domain/search_query.dart`
- Create: `lib/features/search/domain/search_result.dart`
- Create: `lib/features/search/domain/search_ranking.dart`
- Test: `test/features/search/domain/search_ranking_test.dart`

**Interfaces:**
- Produces: `SearchDocument`, `SearchSourceKind`, `SearchExtractionState`, `SearchQuery`, `SearchFilters`, `SearchResult`, and `rankSearchResult(...)`.
- Consumes: pure Dart only; domain files must not import Flutter or Riverpod.

- [ ] **Step 1: Write failing domain tests**

```dart
void main() {
  test('filters reject mismatched workspace before ranking', () {
    final query = SearchQuery(
      text: 'launch',
      activeWorkspaceId: 'workspace-a',
      filters: const SearchFilters(workspaceIds: {'workspace-b'}),
    );
    final document = SearchDocument.test(
      id: 'node:1',
      workspaceId: 'workspace-a',
      text: 'Launch plan',
    );

    expect(matchesSearchFilters(document, query.filters), isFalse);
  });

  test('ranking boosts active workspace and recent edits', () {
    final now = DateTime.utc(2026, 8, 3);
    final active = rankSearchResult(
      bm25: -2,
      modifiedAt: now.subtract(const Duration(days: 1)),
      workspaceId: 'active',
      activeWorkspaceId: 'active',
      now: now,
    );
    final stale = rankSearchResult(
      bm25: -2,
      modifiedAt: now.subtract(const Duration(days: 90)),
      workspaceId: 'other',
      activeWorkspaceId: 'active',
      now: now,
    );

    expect(active, greaterThan(stale));
  });
}
```

- [ ] **Step 2: Run test and confirm failure**

Run: `flutter test test/features/search/domain/search_ranking_test.dart`
Expected: FAIL because search domain types do not exist.

- [ ] **Step 3: Implement immutable domain types and pure ranking**

Use enums for source/extraction states, typed filter sets, UTC timestamps, stable source IDs formatted `<kind>:<sourceId>:<fragmentId>`, and this ranking contract:

```dart
double rankSearchResult({
  required double bm25,
  required DateTime modifiedAt,
  required String workspaceId,
  required String? activeWorkspaceId,
  required DateTime now,
}) {
  final relevance = -bm25;
  final ageDays = now.difference(modifiedAt).inHours.clamp(0, 87600) / 24;
  final recency = 1 / (1 + ageDays / 30);
  final workspaceBoost = workspaceId == activeWorkspaceId ? 0.35 : 0.0;
  return relevance + recency + workspaceBoost;
}
```

- [ ] **Step 4: Run domain tests**

Run: `flutter test test/features/search/domain/search_ranking_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/search/domain test/features/search/domain
git commit -m "feat: add global search domain"
```

### Task 2: Cross-Platform SQLite FTS5 Repository

**Files:**
- Modify: `pubspec.yaml:32-35`
- Create: `lib/features/search/domain/search_index_repository.dart`
- Create: `lib/features/search/data/search_database.dart`
- Create: `lib/features/search/data/search_database_native.dart`
- Create: `lib/features/search/data/search_database_web.dart`
- Create: `lib/features/search/data/search_database_stub.dart`
- Create: `lib/features/search/data/sqlite_search_index_repository.dart`
- Add generated asset: `web/sqlite3.wasm`
- Test: `test/features/search/data/sqlite_search_index_repository_test.dart`

**Interfaces:**
- Produces: `SearchIndexRepository.upsertAll`, `deleteSources`, `search`, `reconcile`, `clear`, `close`.
- Consumes: Task 1 domain types.

- [ ] **Step 1: Add dependencies**

```yaml
  sqlite3: ^3.1.1
  sqlite3_web: ^0.3.0
```

Run: `flutter pub get`
Expected: dependency resolution succeeds. If current compatible versions differ, use newest versions compatible with Dart `^3.11.4`, record exact resolved versions in `pubspec.lock`, and keep direct constraints within same current major.

- [ ] **Step 2: Write failing repository tests**

Cover FTS token matching, Unicode, all hard filters, stable ordering, transactional batch upsert, source deletion, idempotent reconciliation, clear/rebuild, and malformed DB recovery. Use temporary native DB and fixed clock.

```dart
test('upsert replaces stale fragments atomically', () async {
  await repository.upsertAll([oldDocument]);
  await repository.upsertAll([newDocument]);

  expect(await repository.search(const SearchQuery(text: 'old')), isEmpty);
  expect(await repository.search(const SearchQuery(text: 'new')), hasLength(1));
});
```

- [ ] **Step 3: Run test and confirm failure**

Run: `flutter test test/features/search/data/sqlite_search_index_repository_test.dart`
Expected: FAIL because repository does not exist.

- [ ] **Step 4: Implement schema and repository**

Create metadata table `search_documents`, external-content FTS5 table `search_documents_fts`, sync triggers, schema-version table, and indexes for workspace, board, creator, status, source kind, date, and source revision. Wrap replacement of all fragments for one source in one transaction. Parameterize every query; never interpolate user query or filters.

Native implementation opens app-support `search-index.sqlite`. Web implementation uses `sqlite3_web` worker/IndexedDB or OPFS backend and bundled `web/sqlite3.wasm`. Stub throws `UnsupportedError` only on unsupported test/runtime targets.

- [ ] **Step 5: Run repository tests**

Run: `flutter test test/features/search/data/sqlite_search_index_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify web build initializes SQLite**

Run: `flutter build web --debug`
Expected: build succeeds and output contains SQLite WASM/worker assets.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock web/sqlite3.wasm lib/features/search test/features/search/data
git commit -m "feat: add offline FTS search index"
```

### Task 3: Source-to-Search Document Projection

**Files:**
- Create: `lib/features/search/application/search_document_projector.dart`
- Create: `lib/features/search/application/search_index_coordinator.dart`
- Modify: `lib/features/mindmap/application/mindmap_providers.dart:91-269`
- Test: `test/features/search/application/search_document_projector_test.dart`
- Test: `test/features/search/application/search_index_coordinator_test.dart`

**Interfaces:**
- Produces: `SearchDocumentProjector.projectNode`, `projectBoard`, `projectCanvasObject`, `projectNodeComment`; `SearchIndexCoordinator.indexAll()` and `indexSource(SearchSourceRef)`.
- Consumes: existing `MindmapNode`, `CanvasBoard`, `CanvasObject`, `NodeComment`, attachment metadata, and Task 2 repository.

- [ ] **Step 1: Write failing projection tests**

Create fixtures proving indexing of node title/body/data/tags/status/creator, board title/workspace, canvas comments, node comments, attachment filename/MIME/URL, and no leakage of internal IDs or secret/config fields into display snippets.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/search/application/search_document_projector_test.dart test/features/search/application/search_index_coordinator_test.dart`
Expected: FAIL because projector/coordinator do not exist.

- [ ] **Step 3: Implement deterministic projection**

Project one source into ordered fragments with stable IDs and normalized whitespace. Keep `displayTitle`, `displaySnippet`, and searchable `text` separate. Explicitly allowlist user-facing `MindmapNode.data` keys rather than recursively indexing every value. Map canvas comments to parent object/board location.

- [ ] **Step 4: Implement coordinator and providers**

Add providers for DB, repository, projector, coordinator, active workspace, and startup reconciliation. `indexAll()` streams repositories in bounded batches of 200. Compare source revision/updated timestamp before reprojecting. Existing mutation invalidation invokes `indexSource` after durable save and deletion invokes `deleteSources`.

- [ ] **Step 5: Run projection/coordinator tests**

Run: `flutter test test/features/search/application/search_document_projector_test.dart test/features/search/application/search_index_coordinator_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/search/application lib/features/mindmap/application/mindmap_providers.dart test/features/search/application
git commit -m "feat: index searchable app content"
```

### Task 4: Extraction Pipeline and Privacy Gate

**Files:**
- Create: `lib/features/search/domain/content_extraction.dart`
- Create: `lib/features/search/application/content_extraction_pipeline.dart`
- Create: `lib/features/search/data/search_privacy_preferences.dart`
- Create: `lib/features/search/data/local_content_extractors.dart`
- Create: `lib/features/search/data/cloud_content_extractor.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Test: `test/features/search/application/content_extraction_pipeline_test.dart`
- Test: `test/features/search/data/search_privacy_preferences_test.dart`
- Modify: `test/features/settings/settings_page_test.dart`

**Interfaces:**
- Produces: `ContentExtractor.supports`, `extract`; `ContentExtractionPipeline.enqueue`, `cancel`, `retry`; `SearchPrivacyPreferences.cloudExtractionEnabled`.
- Consumes: attachment bytes repository and Task 3 coordinator.

- [ ] **Step 1: Write failing pipeline tests**

Test local extractor precedence, cloud fallback only after opt-in, local-only override, estimated bytes, timeout, cancellation, bounded retry, partial output, temp cleanup, and local persistence of successful output.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/search/application/content_extraction_pipeline_test.dart test/features/search/data/search_privacy_preferences_test.dart`
Expected: FAIL because extraction contracts do not exist.

- [ ] **Step 3: Implement minimal provider-neutral pipeline**

Use `ContentExtractionRequest`, `ExtractedContent`, and `ExtractionLocation` value types. Register extractors by MIME support. First release local adapters extract UTF-8 text/Markdown and existing user-authored captions/metadata. OCR, PDF, and transcription adapters return unsupported until platform/provider implementations are installed; pipeline records `partial`, not false `ready`.

Cloud adapter receives bytes only after permission and local-only checks. Queue concurrency is 2, timeout 2 minutes, retries 3 with 2/8/30-second backoff, and every exit path removes temp files.

- [ ] **Step 4: Add Settings privacy controls**

Add disabled-by-default switch, eligible-content explanation, estimated queued upload bytes, active provider/status, and delete-derived-results action. Persist switch through existing SharedPreferences pattern. Deleting results clears extraction fragments and reindexes metadata-only documents.

- [ ] **Step 5: Run pipeline and Settings tests**

Run: `flutter test test/features/search/application/content_extraction_pipeline_test.dart test/features/search/data/search_privacy_preferences_test.dart test/features/settings/settings_page_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/search lib/features/settings/settings_page.dart test/features/search test/features/settings/settings_page_test.dart
git commit -m "feat: add private content extraction pipeline"
```

### Task 5: Search Service and Riverpod State

**Files:**
- Create: `lib/features/search/application/search_service.dart`
- Create: `lib/features/search/application/search_providers.dart`
- Test: `test/features/search/application/search_service_test.dart`
- Test: `test/features/search/application/search_providers_test.dart`

**Interfaces:**
- Produces: `SearchService.search(SearchQuery)`, `searchResultsProvider`, `searchFiltersProvider`, `searchIndexStatusProvider`.
- Consumes: Task 2 index and Task 1 ranking.

- [ ] **Step 1: Write failing service tests**

Test 150 ms debounce, stale-query cancellation, page size 50, next-page cursor, active workspace ranking, every filter, extraction status, and repository error state.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/search/application/search_service_test.dart test/features/search/application/search_providers_test.dart`
Expected: FAIL because service/providers do not exist.

- [ ] **Step 3: Implement service and providers**

Use immutable `SearchQuery`, async notifier state, monotonic request ID for stale response suppression, and repository cursor `(rank, modifiedAt, documentId)`. Empty query returns recent documents constrained by active filters.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/search/application/search_service_test.dart test/features/search/application/search_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/search/application test/features/search/application
git commit -m "feat: add global search service"
```

### Task 6: Command Palette Integration

**Files:**
- Modify: `lib/features/command/global_command_palette.dart:86-466`
- Modify: `lib/features/command/domain/command_palette_entry.dart:8-80`
- Modify: `test/features/command/global_command_palette_test.dart`
- Modify: `test/features/command/domain/command_palette_entry_test.dart`

**Interfaces:**
- Produces: palette entries for every `SearchSourceKind` and source navigation callback.
- Consumes: `searchResultsProvider` from Task 5 and existing command/date/create parsing.

- [ ] **Step 1: Write failing palette tests**

Test node, board, comment, attachment, OCR, and transcript result rendering; keyboard selection; loading/error/empty states; recent query; extraction badge; direct source navigation; and preservation of existing quick-create/date/collaboration commands.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/command/global_command_palette_test.dart test/features/command/domain/command_palette_entry_test.dart`
Expected: FAIL for new search result kinds.

- [ ] **Step 3: Integrate global results**

Keep command parsing local and query global index only for non-command text. Map result locations to existing `goToDay` and workspace board URLs. Highlight parent node/object and matching attachment/comment; seek media timestamp when destination supports it. Preserve `Ctrl/Cmd+K`, focus, semantics, and keyboard navigation.

- [ ] **Step 4: Run palette tests**

Run: `flutter test test/features/command/global_command_palette_test.dart test/features/command/domain/command_palette_entry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/command test/features/command
git commit -m "feat: search all content from command palette"
```

### Task 7: Dedicated Search Page

**Files:**
- Create: `lib/features/search/presentation/search_page.dart`
- Create: `lib/features/search/presentation/search_filter_bar.dart`
- Create: `lib/features/search/presentation/search_result_tile.dart`
- Modify: `lib/core/router/app_router.dart:31-179`
- Modify: `lib/shared/layout/adaptive_scaffold.dart`
- Create: `test/features/search/presentation/search_page_test.dart`
- Modify: `test/core/router/app_router_test.dart`

**Interfaces:**
- Produces: `/search?q=<query>` route and full search/filter UI.
- Consumes: Task 5 providers and Task 6 navigation mapping.

- [ ] **Step 1: Write failing page/router tests**

Test query URL restoration, all filter controls, previews/highlights, pagination, keyboard navigation, OCR region/transcript timestamp labels, retry, source opening, responsive layout, semantics, and permission-filtered results.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/features/search/presentation/search_page_test.dart test/core/router/app_router_test.dart`
Expected: FAIL because `/search` and page do not exist.

- [ ] **Step 3: Implement route and focused widgets**

Add shell route `/search`; synchronize only query text with `q`, keep complex filter state in provider, and use replace navigation while typing. Use separate filter bar/result tile files to avoid enlarging existing monoliths. Show snippets, match emphasis, source context, extraction state, and retry where allowed.

- [ ] **Step 4: Run page/router tests**

Run: `flutter test test/features/search/presentation/search_page_test.dart test/core/router/app_router_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/search/presentation lib/core/router/app_router.dart lib/shared/layout/adaptive_scaffold.dart test/features/search/presentation test/core/router/app_router_test.dart
git commit -m "feat: add global search page"
```

### Task 8: Incremental Mutation Wiring, Recovery, and Verification

**Files:**
- Modify: mutation boundaries found under `lib/features/mindmap/application/`
- Modify: `lib/features/workspace/workspace_detail_page.dart`
- Create: `test/features/search/application/search_index_integration_test.dart`

**Interfaces:**
- Produces: index convergence after every source save/delete and startup recovery.
- Consumes: `SearchIndexCoordinator` from Task 3.

- [ ] **Step 1: Write failing integration tests**

Test create/update/delete for day node, project board, canvas object/comment, attachment metadata, collaboration comment import, stale revision, app restart, interrupted batch, corrupted index, and workspace permission removal.

- [ ] **Step 2: Run test and confirm failure**

Run: `flutter test test/features/search/application/search_index_integration_test.dart`
Expected: FAIL where mutations do not update index.

- [ ] **Step 3: Wire durable mutation boundaries**

Call coordinator only after successful repository writes. Batch transaction changes into one projection request. On failed indexing, persist repair marker; startup reconciliation consumes markers and compares source revisions. Permission removal immediately deletes inaccessible workspace documents before background rebuild.

- [ ] **Step 4: Run targeted suites**

```bash
flutter test test/features/search
flutter test test/features/command
dart format --set-exit-if-changed lib/features/search test/features/search lib/features/command test/features/command
flutter analyze
```

Expected: all tests pass, formatting unchanged, analyzer reports no issues.

- [ ] **Step 5: Run full regression suite**

Run: `flutter test`
Expected: PASS. If known baseline failures remain, record exact pre-existing failures and prove no new failures with targeted suites and before/after comparison.

- [ ] **Step 6: Verify release web build**

Run: `flutter build web --release --dart-define=VAR_DEMO_SEED=false`
Expected: build succeeds and search persists across browser reload.

- [ ] **Step 7: Commit**

```bash
git add lib/features/mindmap/application lib/features/workspace/workspace_detail_page.dart test/features/search/application/search_index_integration_test.dart
git commit -m "feat: keep global search index synchronized"
```

## Follow-Up Plans

After this plan ships and search contracts stabilize, write separate plans for:

1. In-app mixed Quick Capture with destination picker and duplicate detection.
2. Android/iOS/macOS/Windows share targets using same capture contract.
3. Browser extension/web clipper with sanitized article snapshots.
4. Concrete local/cloud PDF, OCR, and transcription providers behind Task 4 interfaces.
