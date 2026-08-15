# In-App Quick Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build in-app quick capture to accept mixed text, URLs, images, and files, classify content, detect duplicates by canonical URL/hash, select destination boards, and persist nodes with background indexing.

**Architecture:** Domain payload & validation -> URL classifier & article snapshot -> Duplicate detection engine -> Destination picker provider -> Capture service & atomic persistence -> Quick capture dialog UI.

**Tech Stack:** Dart SDK 3.11+, Flutter, Riverpod, Sembast, `crypto` (SHA-256), `http` / HTML parsing.

## Global Constraints

- Never auto-submit captures without explicit destination choice.
- Separate transactions: durable node storage must succeed before extraction/indexing starts.
- Untrusted URL input: reject private/local network fetches (`localhost`, `127.0.0.1`, `10.*`, `192.168.*`, `172.16-31.*`).
- Article snapshot failure must gracefully fall back to bookmark preview.
- No semantic/vector search; no automatic duplicate merging.

---

### Task 1: Capture Payload, Validation, and Duplicate Detection Engine

**Files:**
- Create: `lib/features/capture/domain/capture_payload.dart`
- Create: `lib/features/capture/domain/capture_validation.dart`
- Create: `lib/features/capture/domain/duplicate_detector.dart`
- Create: `test/features/capture/domain/capture_validation_test.dart`
- Create: `test/features/capture/domain/duplicate_detector_test.dart`

**Interfaces:**
- Consumes: `MindmapNode` from `lib/features/mindmap/domain/mindmap_node.dart`
- Produces: `CapturePayload`, `CaptureValidationResult`, `DuplicateMatchResult`, `DuplicateDetector`

- [ ] **Step 1: Write failing tests for validation and duplicate detection**

```dart
// test/features/capture/domain/capture_validation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';

void main() {
  group('CaptureValidator', () {
    test('rejects private network URLs', () {
      final payload = CapturePayload(
        text: 'test',
        urls: ['http://127.0.0.1/secret', 'http://localhost:8080'],
      );
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Private or local network URL rejected'));
    });

    test('accepts valid public payload', () {
      final payload = CapturePayload(
        text: 'Read this article',
        urls: ['https://example.com/article'],
      );
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isTrue);
    });
  });
}
```

```dart
// test/features/capture/domain/duplicate_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/core/constants/app_constants.dart';

void main() {
  group('DuplicateDetector', () {
    test('detects duplicate by canonical URL', () {
      final existingNodes = [
        MindmapNode(
          id: 'node-1',
          day: '2026-08-04',
          type: NodeType.link,
          label: 'Example',
          data: {'url': 'https://example.com/article?ref=share'},
        ),
      ];

      final payload = CapturePayload(
        urls: ['https://example.com/article#heading'],
      );

      final result = DuplicateDetector.check(payload, existingNodes);
      expect(result.hasDuplicate, isTrue);
      expect(result.existingNodeId, equals('node-1'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `flutter test test/features/capture/domain/capture_validation_test.dart test/features/capture/domain/duplicate_detector_test.dart`
Expected: FAIL (files/classes not found)

- [ ] **Step 3: Implement CapturePayload, CaptureValidator, and DuplicateDetector**

```dart
// lib/features/capture/domain/capture_payload.dart
import 'dart:typed_data';

class CaptureFileAttachment {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String? localPath;

  const CaptureFileAttachment({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.localPath,
  });
}

class CapturePayload {
  final String? text;
  final List<String> urls;
  final List<CaptureFileAttachment> attachments;
  final Map<String, Object?> metadata;

  const CapturePayload({
    this.text,
    this.urls = const [],
    this.attachments = const [],
    this.metadata = const {},
  });

  bool get isEmpty => (text == null || text!.trim().isEmpty) && urls.isEmpty && attachments.isEmpty;
}
```

```dart
// lib/features/capture/domain/capture_validation.dart
import 'package:var_app/features/capture/domain/capture_payload.dart';

class CaptureValidationResult {
  final bool isValid;
  final List<String> errors;

  const CaptureValidationResult({required this.isValid, required this.errors});
}

class CaptureValidator {
  static final _privateHostRegex = RegExp(
    r'^(localhost|127\.\d+\.\d+\.\d+|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$',
    caseSensitive: false,
  );

  static CaptureValidationResult validate(CapturePayload payload) {
    final errors = <String>[];

    if (payload.isEmpty) {
      errors.add('Capture payload cannot be empty');
    }

    for (final urlString in payload.urls) {
      final uri = Uri.tryParse(urlString);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        errors.add('Invalid URL scheme: $urlString');
        continue;
      }

      if (_privateHostRegex.hasMatch(uri.host)) {
        errors.add('Private or local network URL rejected: ${uri.host}');
      }
    }

    return CaptureValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }
}
```

```dart
// lib/features/capture/domain/duplicate_detector.dart
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

class DuplicateMatchResult {
  final bool hasDuplicate;
  final String? existingNodeId;
  final String? matchedCanonicalUrl;
  final String? matchedContentHash;

  const DuplicateMatchResult({
    required this.hasDuplicate,
    this.existingNodeId,
    this.matchedCanonicalUrl,
    this.matchedContentHash,
  });

  static const none = DuplicateMatchResult(hasDuplicate: false);
}

class DuplicateDetector {
  static String normalizeUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    final normalized = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: (uri.port == 80 || uri.port == 443) ? 0 : uri.port,
      path: uri.path.endsWith('/') && uri.path.length > 1 ? uri.path.substring(0, uri.path.length - 1) : uri.path,
      query: uri.query.isEmpty ? null : uri.query,
    );
    return normalized.toString();
  }

  static String hashContent(String content) {
    return sha256.convert(utf8.encode(content.trim())).toString();
  }

  static DuplicateMatchResult check(CapturePayload payload, List<MindmapNode> existingNodes) {
    if (payload.urls.isNotEmpty) {
      final targetNormalized = normalizeUrl(payload.urls.first);
      for (final node in existingNodes) {
        final nodeUrl = node.data['url'] as String?;
        if (nodeUrl != null && normalizeUrl(nodeUrl) == targetNormalized) {
          return DuplicateMatchResult(
            hasDuplicate: true,
            existingNodeId: node.id,
            matchedCanonicalUrl: targetNormalized,
          );
        }
      }
    }

    if (payload.text != null && payload.text!.trim().isNotEmpty) {
      final targetHash = hashContent(payload.text!);
      for (final node in existingNodes) {
        final nodeContent = node.label ?? (node.data['content'] as String?);
        if (nodeContent != null && hashContent(nodeContent) == targetHash) {
          return DuplicateMatchResult(
            hasDuplicate: true,
            existingNodeId: node.id,
            matchedContentHash: targetHash,
          );
        }
      }
    }

    return DuplicateMatchResult.none;
  }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `flutter test test/features/capture/domain/capture_validation_test.dart test/features/capture/domain/duplicate_detector_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/ test/features/capture/
git commit -m "feat: add capture payload validation and duplicate detector"
```

---

### Task 2: URL Classifier and Offline Article Snapshot Service

**Files:**
- Create: `lib/features/capture/application/url_classifier_service.dart`
- Create: `lib/features/capture/domain/captured_url_result.dart`
- Create: `test/features/capture/application/url_classifier_service_test.dart`

**Interfaces:**
- Consumes: `CaptureValidator` from Task 1, `http.Client`
- Produces: `CapturedUrlResult`, `CapturedUrlType` (`article`, `bookmark`), `UrlClassifierService`

- [ ] **Step 1: Write failing test for URL classifier & fallback**

```dart
// test/features/capture/application/url_classifier_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/captured_url_result.dart';

void main() {
  group('UrlClassifierService', () {
    test('classifies HTML article and builds offline snapshot', () async {
      final client = MockClient((request) async {
        return http.Response(
          '''
          <html>
            <head><title>Test Article Title</title></head>
            <body><article><p>This is readable content for offline capture.</p></article></body>
          </html>
          ''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });

      final service = UrlClassifierService(httpClient: client);
      final result = await service.processUrl('https://example.com/blog/test');

      expect(result.type, equals(CapturedUrlType.article));
      expect(result.title, equals('Test Article Title'));
      expect(result.extractedText, contains('readable content for offline capture'));
    });

    test('falls back to bookmark preview on fetch failure', () async {
      final client = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final service = UrlClassifierService(httpClient: client);
      final result = await service.processUrl('https://example.com/broken');

      expect(result.type, equals(CapturedUrlType.bookmark));
      expect(result.title, equals('https://example.com/broken'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/capture/application/url_classifier_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement UrlClassifierService and CapturedUrlResult**

```dart
// lib/features/capture/domain/captured_url_result.dart
enum CapturedUrlType { article, bookmark }

class CapturedUrlResult {
  final String url;
  final String canonicalUrl;
  final CapturedUrlType type;
  final String title;
  final String? metaDescription;
  final String? extractedText;
  final String? htmlSnapshot;

  const CapturedUrlResult({
    required this.url,
    required this.canonicalUrl,
    required this.type,
    required this.title,
    this.metaDescription,
    this.extractedText,
    this.htmlSnapshot,
  });
}
```

```dart
// lib/features/capture/application/url_classifier_service.dart
import 'package:http/http.dart' as http;
import 'package:var_app/features/capture/domain/captured_url_result.dart';
import 'package:var_app/features/capture/domain/duplicate_detector.dart';

class UrlClassifierService {
  final http.Client _httpClient;

  UrlClassifierService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  Future<CapturedUrlResult> processUrl(String rawUrl) async {
    final canonicalUrl = DuplicateDetector.normalizeUrl(rawUrl);

    try {
      final response = await _httpClient.get(Uri.parse(rawUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return _fallbackBookmark(rawUrl, canonicalUrl);
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/html')) {
        return _fallbackBookmark(rawUrl, canonicalUrl);
      }

      final body = response.body;
      final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(body);
      final title = titleMatch?.group(1)?.trim() ?? rawUrl;

      // Extract text content from html body
      final cleanText = body
          .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final isArticle = cleanText.length > 200 || body.contains('<article');

      return CapturedUrlResult(
        url: rawUrl,
        canonicalUrl: canonicalUrl,
        type: isArticle ? CapturedUrlType.article : CapturedUrlType.bookmark,
        title: title,
        extractedText: cleanText,
        htmlSnapshot: body,
      );
    } catch (_) {
      return _fallbackBookmark(rawUrl, canonicalUrl);
    }
  }

  CapturedUrlResult _fallbackBookmark(String rawUrl, String canonicalUrl) {
    return CapturedUrlResult(
      url: rawUrl,
      canonicalUrl: canonicalUrl,
      type: CapturedUrlType.bookmark,
      title: rawUrl,
    );
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/capture/application/url_classifier_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/ test/features/capture/
git commit -m "feat: add URL classifier and offline article snapshot extractor"
```

---

### Task 3: Capture Service and Destination Selection

**Files:**
- Create: `lib/features/capture/domain/capture_destination.dart`
- Create: `lib/features/capture/application/capture_service.dart`
- Create: `test/features/capture/application/capture_service_test.dart`

**Interfaces:**
- Consumes: `CapturePayload`, `CapturedUrlResult`, `MindmapNodeDatabase`, `ContentExtractionPipeline`, `SearchIndexCoordinator`
- Produces: `CaptureDestination`, `CaptureService`

- [ ] **Step 1: Write failing test for atomic node persistence and background indexing trigger**

```dart
// test/features/capture/application/capture_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';

void main() {
  group('CaptureService', () {
    test('persists captured note to destination board', () async {
      final repository = InMemoryMindmapRepository();
      final captureService = CaptureService(mindmapRepository: repository);

      final payload = CapturePayload(
        text: 'Captured quick thought',
      );
      final destination = CaptureDestination(
        boardId: 'board-main',
        boardTitle: 'Main Board',
        workspaceId: 'ws-1',
      );

      final node = await captureService.saveCapture(
        payload: payload,
        destination: destination,
      );

      expect(node.id, isNotEmpty);
      expect(node.label, equals('Captured quick thought'));
      expect(node.data['boardId'], equals('board-main'));

      final storedNodes = await repository.loadNodes('2026-08-04');
      expect(storedNodes.any((n) => n.id == node.id), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/capture/application/capture_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement CaptureDestination and CaptureService**

```dart
// lib/features/capture/domain/capture_destination.dart
class CaptureDestination {
  final String boardId;
  final String boardTitle;
  final String workspaceId;

  const CaptureDestination({
    required this.boardId,
    required this.boardTitle,
    required this.workspaceId,
  });
}
```

```dart
// lib/features/capture/application/capture_service.dart
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';
import 'package:var_app/features/capture/domain/captured_url_result.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/search/application/content_extraction_pipeline.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';

class CaptureService {
  final MindmapRepository _mindmapRepository;
  final UrlClassifierService _urlClassifierService;
  final ContentExtractionPipeline? _extractionPipeline;
  final SearchIndexCoordinator? _indexCoordinator;

  CaptureService({
    required MindmapRepository mindmapRepository,
    UrlClassifierService? urlClassifierService,
    ContentExtractionPipeline? extractionPipeline,
    SearchIndexCoordinator? indexCoordinator,
  })  : _mindmapRepository = mindmapRepository,
        _urlClassifierService = urlClassifierService ?? UrlClassifierService(),
        _extractionPipeline = extractionPipeline,
        _indexCoordinator = indexCoordinator;

  Future<MindmapNode> saveCapture({
    required CapturePayload payload,
    required CaptureDestination destination,
  }) async {
    final validation = CaptureValidator.validate(payload);
    if (!validation.isValid) {
      throw ArgumentError(validation.errors.join('; '));
    }

    final today = dayKey(DateTime.now());
    NodeType nodeType = NodeType.note;
    String label = payload.text ?? 'Captured item';
    final nodeData = <String, Object?>{
      'boardId': destination.boardId,
      'workspaceId': destination.workspaceId,
      'capturedAt': DateTime.now().toIso8601String(),
    };

    if (payload.urls.isNotEmpty) {
      final urlResult = await _urlClassifierService.processUrl(payload.urls.first);
      nodeType = urlResult.type == CapturedUrlType.article ? NodeType.article : NodeType.link;
      label = urlResult.title;
      nodeData['url'] = urlResult.url;
      nodeData['canonicalUrl'] = urlResult.canonicalUrl;
      if (urlResult.extractedText != null) {
        nodeData['extractedText'] = urlResult.extractedText;
      }
      if (urlResult.htmlSnapshot != null) {
        nodeData['htmlSnapshot'] = urlResult.htmlSnapshot;
      }
    }

    final node = MindmapNode(
      id: 'capture-${DateTime.now().millisecondsSinceEpoch}',
      day: today,
      type: nodeType,
      label: label,
      data: nodeData,
    );

    // Durable atomic save
    await _mindmapRepository.saveNode(node);

    // Background indexing (fire and forget / separate transaction)
    if (_indexCoordinator != null) {
      _indexCoordinator!.indexNode(node);
    }

    return node;
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/capture/application/capture_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/ test/features/capture/
git commit -m "feat: add CaptureService with atomic node save and background indexing"
```

---

### Task 4: Quick Capture Modal UI & Providers

**Files:**
- Create: `lib/features/capture/application/capture_providers.dart`
- Create: `lib/features/capture/presentation/quick_capture_dialog.dart`
- Create: `test/features/capture/presentation/quick_capture_dialog_test.dart`

**Interfaces:**
- Consumes: `CaptureService`, `DuplicateDetector`, `CaptureDestination`
- Produces: `quickCaptureControllerProvider`, `QuickCaptureDialog`

- [ ] **Step 1: Write failing widget test for QuickCaptureDialog**

```dart
// test/features/capture/presentation/quick_capture_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/presentation/quick_capture_dialog.dart';

void main() {
  group('QuickCaptureDialog', () {
    testWidgets('renders input field and requires destination before save', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: QuickCaptureDialog(),
            ),
          ),
        ),
      );

      expect(find.text('Quick Capture'), findsOneWidget);
      expect(find.text('Save Capture'), findsOneWidget);

      final saveButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(saveButton.onPressed, isNull); // disabled when destination empty
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/capture/presentation/quick_capture_dialog_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement capture_providers.dart and QuickCaptureDialog**

```dart
// lib/features/capture/application/capture_providers.dart
import 'package0/flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/application/capture_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';

final captureServiceProvider = Provider<CaptureService>((ref) {
  final repo = ref.watch(mindmapRepositoryProvider);
  return CaptureService(mindmapRepository: repo);
});
```

```dart
// lib/features/capture/presentation/quick_capture_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/application/capture_providers.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

class QuickCaptureDialog extends ConsumerStatefulWidget {
  const QuickCaptureDialog({super.key});

  @override
  ConsumerState<QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends ConsumerState<QuickCaptureDialog> {
  final _textController = TextEditingController();
  final _urlController = TextEditingController();
  CaptureDestination? _selectedDestination;
  bool _isSaving = false;

  @override
  void dispose() {
    _textController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_selectedDestination == null) return;
    setState(() => _isSaving = true);

    try {
      final payload = CapturePayload(
        text: _textController.text.trim().isEmpty ? null : _textController.text.trim(),
        urls: _urlController.text.trim().isEmpty ? [] : [_urlController.text.trim()],
      );

      final service = ref.read(captureServiceProvider);
      await service.saveCapture(
        payload: payload,
        destination: _selectedDestination!,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedDestination != null &&
        (_textController.text.trim().isNotEmpty || _urlController.text.trim().isNotEmpty);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Quick Capture', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(labelText: 'Note / Content'),
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'URL (optional)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<CaptureDestination>(
              value: _selectedDestination,
              hint: const Text('Select Destination Board *'),
              items: const [
                DropdownMenuItem(
                  value: CaptureDestination(boardId: 'default', boardTitle: 'Inbox Board', workspaceId: 'default'),
                  child: Text('Inbox Board'),
                ),
              ],
              onChanged: (dest) => setState(() => _selectedDestination = dest),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: canSave && !_isSaving ? _handleSave : null,
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save Capture'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/capture/presentation/quick_capture_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/ test/features/capture/
git commit -m "feat: add QuickCaptureDialog UI component with mandatory destination selection"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-04-inapp-quick-capture.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?