# Rich Link Web Preview Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement client-side HTML OpenGraph scraping to convert basic URL links into rich preview cards with thumbnails, icons, titles, and site names.

**Architecture:** Update `LinkPayload` to support enriched metadata fields, build `LinkMetadataFetcherService` for HTML OpenGraph parsing, and enhance `NodeType.link` rendering in `MindmapCanvas`.

**Tech Stack:** Dart, Flutter, `http` package, `url_launcher`.

---

### Task 1: Extend LinkPayload Domain Model

**Files:**
- Modify: `lib/features/mindmap/domain/node_type_payloads.dart`
- Test: `test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 1: Write failing test for extended LinkPayload**

```dart
test('LinkPayload handles enriched metadata fields', () {
  final payload = LinkPayload(
    url: 'https://example.com',
    title: 'Example Title',
    description: 'Example Description',
    imageUrl: 'https://example.com/image.png',
    faviconUrl: 'https://example.com/favicon.ico',
    siteName: 'Example Site',
    isFetched: true,
  );
  final data = payload.toData();
  final reconstructed = LinkPayload.fromData(data);
  expect(reconstructed.imageUrl, 'https://example.com/image.png');
  expect(reconstructed.siteName, 'Example Site');
  expect(reconstructed.isFetched, isTrue);
});
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 3: Update LinkPayload**

Add `description`, `imageUrl`, `faviconUrl`, `siteName`, `isFetched` to `LinkPayload` in `lib/features/mindmap/domain/node_type_payloads.dart`.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/node_type_payloads.dart test/features/mindmap/domain/mindmap_node_data_test.dart
git commit -m "feat: extend LinkPayload with rich web preview metadata"
```

---

### Task 2: Build LinkMetadataFetcherService

**Files:**
- Create: `lib/features/mindmap/application/link_metadata_fetcher_service.dart`
- Test: `test/features/mindmap/application/link_metadata_fetcher_service_test.dart`

- [ ] **Step 1: Write failing test for OpenGraph HTML parsing**

```dart
test('extracts OpenGraph tags from HTML response', () {
  const html = '''
    <html>
      <head>
        <meta property="og:title" content="Test Page Title" />
        <meta property="og:description" content="Test Page Description" />
        <meta property="og:image" content="https://test.com/og.png" />
        <meta property="og:site_name" content="TestSite" />
      </head>
    </html>
  ''';
  final result = extractOpenGraphMetadata(html, 'https://test.com');
  expect(result['title'], 'Test Page Title');
  expect(result['description'], 'Test Page Description');
  expect(result['imageUrl'], 'https://test.com/og.png');
  expect(result['siteName'], 'TestSite');
});
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/application/link_metadata_fetcher_service_test.dart`

- [ ] **Step 3: Implement LinkMetadataFetcherService**

Implement `extractOpenGraphMetadata` and `fetchLinkMetadata` helper service.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/application/link_metadata_fetcher_service_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/application/link_metadata_fetcher_service.dart test/features/mindmap/application/link_metadata_fetcher_service_test.dart
git commit -m "feat: add client-side OpenGraph HTML parser service"
```

---

### Task 3: Render Rich Link Cards in MindmapCanvas

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

- [ ] **Step 1: Update Link Card UI in MindmapCanvas**

Update `NodeType.link` rendering to display preview thumbnail image, favicon, domain name, title, and description.

- [ ] **Step 2: Run tests and analyzer**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart`
Run: `flutter analyze`

- [ ] **Step 3: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
git commit -m "feat: render rich link preview cards on mindmap canvas"
```
