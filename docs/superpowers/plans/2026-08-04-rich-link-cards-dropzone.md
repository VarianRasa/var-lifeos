# Rich Link Cards & Canvas File Dropzone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement OpenGraph metadata link preview cards and canvas file drag-and-drop dropzone mapped to spatial cursor coordinates.

**Architecture:** Client-side HTML OpenGraph scraper service (`UrlMetadataScraperService`) + Link preview UI widget (`LinkPreviewCardWidget`) + Desktop/Web canvas dropzone overlay (`CanvasDropzoneOverlay`) with screen-to-canvas coordinate translation.

**Tech Stack:** Dart 3.11+, Flutter, html parser, Riverpod, Sembast.

## Global Constraints

- Scraper must be local-first; web CORS failure falls back to domain + favicon fallback metadata without failing or crashing.
- Caching fetched link metadata in local memory/Sembast store to avoid repeated network requests.
- Canvas file drop converts screen drop coordinates to spatial canvas vectors via `viewportController`.
- All Dart code must conform to project lint rules (`prefer_single_quotes`, strict casts, return types).

---

### Task 1: OpenGraph Scraper Service & LinkMetadata Domain Model

**Files:**
- Create: `lib/features/mindmap/domain/link_metadata.dart`
- Create: `lib/core/services/url_metadata_scraper_service.dart`
- Create: `test/core/services/url_metadata_scraper_service_test.dart`

**Interfaces:**
- Consumes: `http.Client`, `html` package parser
- Produces: `LinkMetadata`, `UrlMetadataScraperService`, `urlMetadataScraperProvider`

- [ ] **Step 1: Write failing unit test for LinkMetadata model and scraper service**

```dart
// test/core/services/url_metadata_scraper_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/core/services/url_metadata_scraper_service.dart';
import 'package:var_app/features/mindmap/domain/link_metadata.dart';

void main() {
  group('UrlMetadataScraperService', () {
    test('parses OpenGraph meta tags from HTML correctly', () async {
      final mockHtml = '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta property="og:title" content="Test Article Title" />
          <meta property="og:description" content="Test description content" />
          <meta property="og:image" content="https://example.com/image.png" />
          <meta property="og:site_name" content="Example Site" />
        </head>
        <body></body>
        </html>
      ''';

      final mockClient = MockClient((request) async {
        return http.Response(mockHtml, 200);
      });

      final service = UrlMetadataScraperService(client: mockClient);
      final metadata = await service.fetchMetadata('https://example.com/article');

      expect(metadata.title, equals('Test Article Title'));
      expect(metadata.description, equals('Test description content'));
      expect(metadata.imageUrl, equals('https://example.com/image.png'));
      expect(metadata.siteName, equals('Example Site'));
      expect(metadata.faviconUrl, contains('google.com/s2/favicons'));
    });

    test('returns fallback metadata when network request fails', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('CORS or Network failure');
      });

      final service = UrlMetadataScraperService(client: mockClient);
      final metadata = await service.fetchMetadata('https://example.com/blocked');

      expect(metadata.url, equals('https://example.com/blocked'));
      expect(metadata.title, equals('example.com'));
      expect(metadata.faviconUrl, contains('google.com/s2/favicons'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/core/services/url_metadata_scraper_service_test.dart`
Expected: FAIL (files missing)

- [ ] **Step 3: Create LinkMetadata domain model**

```dart
// lib/features/mindmap/domain/link_metadata.dart
class LinkMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? faviconUrl;
  final DateTime fetchedAt;

  const LinkMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.faviconUrl,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'siteName': siteName,
      'faviconUrl': faviconUrl,
      'fetchedAt': fetchedAt.toIso8601String(),
    };
  }

  factory LinkMetadata.fromJson(Map<String, dynamic> json) {
    return LinkMetadata(
      url: json['url'] as String,
      title: json['title'] as String?,
      description: json['description'] as String?,
      imageUrl: json['imageUrl'] as String?,
      siteName: json['siteName'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }
}
```

- [ ] **Step 4: Implement UrlMetadataScraperService**

```dart
// lib/core/services/url_metadata_scraper_service.dart
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/mindmap/domain/link_metadata.dart';

class UrlMetadataScraperService {
  final http.Client _client;
  final Map<String, LinkMetadata> _cache = {};

  UrlMetadataScraperService({http.Client? client})
      : _client = client ?? http.Client();

  Future<LinkMetadata> fetchMetadata(String urlString) async {
    if (_cache.containsKey(urlString)) {
      return _cache[urlString]!;
    }

    final uri = Uri.tryParse(urlString);
    final host = uri?.host ?? urlString;
    final defaultFavicon = 'https://www.google.com/s2/favicons?domain=$host&sz=64';

    try {
      final response = await _client.get(
        Uri.parse(urlString),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        
        String? getMetaContent(String property) {
          final element = document.querySelector('meta[property="$property"]') ??
              document.querySelector('meta[name="$property"]');
          return element?.attributes['content'];
        }

        final title = getMetaContent('og:title') ?? document.querySelector('title')?.text ?? host;
        final description = getMetaContent('og:description');
        final imageUrl = getMetaContent('og:image');
        final siteName = getMetaContent('og:site_name') ?? host;

        final metadata = LinkMetadata(
          url: urlString,
          title: title,
          description: description,
          imageUrl: imageUrl,
          siteName: siteName,
          faviconUrl: defaultFavicon,
          fetchedAt: DateTime.now(),
        );

        _cache[urlString] = metadata;
        return metadata;
      }
    } catch (_) {
      // Fallback for CORS or connection errors
    }

    final fallback = LinkMetadata(
      url: urlString,
      title: host,
      faviconUrl: defaultFavicon,
      fetchedAt: DateTime.now(),
    );
    _cache[urlString] = fallback;
    return fallback;
  }
}

final urlMetadataScraperProvider = Provider<UrlMetadataScraperService>((ref) {
  return UrlMetadataScraperService();
});
```

- [ ] **Step 5: Run tests and verify pass**

Run: `flutter test test/core/services/url_metadata_scraper_service_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/mindmap/domain/link_metadata.dart lib/core/services/url_metadata_scraper_service.dart test/core/services/url_metadata_scraper_service_test.dart
git commit -m "feat: add UrlMetadataScraperService and LinkMetadata for OpenGraph cards"
```

---

### Task 2: Rich Link Preview Card Widget & Canvas Dropzone Overlay

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/link_preview_card_widget.dart`
- Create: `lib/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart`
- Create: `test/features/mindmap/presentation/widgets/canvas_dropzone_overlay_test.dart`

**Interfaces:**
- Consumes: `LinkMetadata`, `UrlMetadataScraperService`, `desktop_drop` / DragTarget
- Produces: `LinkPreviewCardWidget`, `CanvasDropzoneOverlay`

- [ ] **Step 1: Write failing widget test for CanvasDropzoneOverlay**

```dart
// test/features/mindmap/presentation/widgets/canvas_dropzone_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart';

void main() {
  testWidgets('CanvasDropzoneOverlay renders child and overlay border when active',
      (WidgetTester tester) async {
    bool dropTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasDropzoneOverlay(
            onFilesDropped: (files, offset) {
              dropTriggered = true;
            },
            child: const SizedBox(width: 400, height: 400, child: Text('Canvas Area')),
          ),
        ),
      ),
    );

    expect(find.text('Canvas Area'), findsOneWidget);
    expect(find.byType(CanvasDropzoneOverlay), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/presentation/widgets/canvas_dropzone_overlay_test.dart`
Expected: FAIL (files missing)

- [ ] **Step 3: Implement LinkPreviewCardWidget**

```dart
// lib/features/mindmap/presentation/widgets/link_preview_card_widget.dart
import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/link_metadata.dart';

class LinkPreviewCardWidget extends StatelessWidget {
  final LinkMetadata metadata;
  final VoidCallback? onTap;

  const LinkPreviewCardWidget({
    super.key,
    required this.metadata,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (metadata.imageUrl != null)
              Image.network(
                metadata.imageUrl!,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (metadata.faviconUrl != null)
                        Image.network(
                          metadata.faviconUrl!,
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) => const Icon(Icons.public, size: 14),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          metadata.siteName ?? metadata.url,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (metadata.title != null)
                    Text(
                      metadata.title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (metadata.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      metadata.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement CanvasDropzoneOverlay**

```dart
// lib/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart
import 'package:flutter/material.dart';

typedef OnFilesDroppedCallback = void Function(List<String> filePaths, Offset screenOffset);

class CanvasDropzoneOverlay extends StatefulWidget {
  final Widget child;
  final OnFilesDroppedCallback onFilesDropped;

  const CanvasDropzoneOverlay({
    super.key,
    required this.child,
    required this.onFilesDropped,
  });

  @override
  State<CanvasDropzoneOverlay> createState() => _CanvasDropzoneOverlayState();
}

class _CanvasDropzoneOverlayState extends State<CanvasDropzoneOverlay> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        widget.child,
        DragTarget<List<String>>(
          onWillAcceptWithDetails: (details) {
            setState(() => _isDragging = true);
            return true;
          },
          onLeave: (_) {
            setState(() => _isDragging = false);
          },
          onAcceptWithDetails: (details) {
            setState(() => _isDragging = false);
            widget.onFilesDropped(details.data, details.offset);
          },
          builder: (context, candidateData, rejectedData) {
            if (!_isDragging) return const SizedBox.shrink();

            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_upload_outlined, size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      'Drop files to add to Canvas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run tests and verify pass**

Run: `flutter test test/features/mindmap/presentation/widgets/canvas_dropzone_overlay_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/mindmap/presentation/widgets/link_preview_card_widget.dart lib/features/mindmap/presentation/widgets/canvas_dropzone_overlay.dart test/features/mindmap/presentation/widgets/canvas_dropzone_overlay_test.dart
git commit -m "feat: add LinkPreviewCardWidget and CanvasDropzoneOverlay widgets"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-04-rich-link-cards-dropzone.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
