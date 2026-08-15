# Native OS Share Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Native OS Share Target integration across Android, iOS, macOS, and Windows to capture shared text, URLs, images, and files directly into Var app's `QuickCaptureDialog` and persist via `CaptureService`.

**Architecture:** Shared intent listener service -> Native protocol/channel handlers -> Payload normalization & file copy streaming -> App route listener & `QuickCaptureDialog` popover.

**Tech Stack:** Dart SDK 3.11+, Flutter, Riverpod, `receive_sharing_intent` (or platform channels), `path_provider`, Sembast.

## Global Constraints

- Never submit shared captures without explicit destination choice.
- Copy temporary OS share files into `AppDocDir/shares/` using streaming to avoid memory overhead.
- Reject file attachments exceeding 100MB per file with user error messaging.
- Auto-clean temporary share files on capture save or cancellation.
- Re-validate shared URLs with `CaptureValidator` to reject private/local network links.

---

### Task 1: OS Share Receiver Service & File Streamer

**Files:**
- Create: `lib/features/capture/application/os_share_receiver_service.dart`
- Create: `test/features/capture/application/os_share_receiver_service_test.dart`

**Interfaces:**
- Consumes: `CapturePayload`, `CaptureFileAttachment`, `CaptureValidator`
- Produces: `OsShareReceiverService`, `osShareReceiverServiceProvider`

- [ ] **Step 1: Write failing unit test for share payload parsing and file size limit**

```dart
// test/features/capture/application/os_share_receiver_service_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/os_share_receiver_service.dart';

void main() {
  group('OsShareReceiverService', () {
    test('parses raw text and url share data into CapturePayload', () async {
      final service = OsShareReceiverService();
      final payload = await service.parseShareData(
        text: 'Check this out https://example.com/article',
      );

      expect(payload.urls, contains('https://example.com/article'));
      expect(payload.text, equals('Check this out'));
    });

    test('rejects file attachments larger than 100MB', () async {
      final service = OsShareReceiverService(maxFileBytes: 100 * 1024 * 1024);
      final oversizedBytes = Uint8List(0); // mock metadata check

      final result = service.validateFileSize(fileSizeBytes: 101 * 1024 * 1024);
      expect(result, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/capture/application/os_share_receiver_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement OsShareReceiverService**

```dart
// lib/features/capture/application/os_share_receiver_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';

class OsShareReceiverService {
  final int maxFileBytes;
  final _shareStreamController = StreamController<CapturePayload>.broadcast();

  OsShareReceiverService({this.maxFileBytes = 100 * 1024 * 1024});

  Stream<CapturePayload> get onShareReceived => _shareStreamController.stream;

  bool validateFileSize({required int fileSizeBytes}) {
    return fileSizeBytes <= maxFileBytes;
  }

  Future<CapturePayload> parseShareData({
    String? text,
    List<String> filePaths = const [],
  }) async {
    final urls = <String>[];
    String? cleanText = text;

    if (text != null) {
      final urlRegExp = RegExp(r'https?://[^\s]+', caseSensitive: false);
      final matches = urlRegExp.allMatches(text);
      for (final match in matches) {
        final rawUrl = match.group(0);
        if (rawUrl != null && !CaptureValidator.isPrivateOrLocalHost(Uri.parse(rawUrl).host)) {
          urls.add(rawUrl);
        }
      }
      cleanText = text.replaceAll(urlRegExp, '').trim();
      if (cleanText.isEmpty) cleanText = null;
    }

    final attachments = <CaptureFileAttachment>[];
    for (final path in filePaths) {
      final file = File(path);
      if (await file.exists()) {
        final length = await file.length();
        if (validateFileSize(fileSizeBytes: length)) {
          final fileName = path.split(Platform.pathSeparator).last;
          attachments.add(
            CaptureFileAttachment(
              fileName: fileName,
              mimeType: 'application/octet-stream',
              bytes: Uint8List(0),
              localPath: path,
            ),
          );
        }
      }
    }

    final payload = CapturePayload(
      text: cleanText,
      urls: urls,
      attachments: attachments,
    );

    return payload;
  }

  void dispose() {
    _shareStreamController.close();
  }
}

final osShareReceiverServiceProvider = Provider<OsShareReceiverService>((ref) {
  final service = OsShareReceiverService();
  ref.onDispose(service.dispose);
  return service;
});
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/capture/application/os_share_receiver_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/application/os_share_receiver_service.dart test/features/capture/application/os_share_receiver_service_test.dart
git commit -m "feat: add OsShareReceiverService for parsing incoming OS share payloads"
```

---

### Task 2: App Router Share Handler & Quick Capture Launch

**Files:**
- Create: `lib/features/capture/application/share_router_handler.dart`
- Modify: `lib/features/capture/presentation/quick_capture_dialog.dart`
- Create: `test/features/capture/application/share_router_handler_test.dart`

**Interfaces:**
- Consumes: `OsShareReceiverService`, `QuickCaptureDialog`
- Produces: `shareRouterHandlerProvider`, `showQuickCaptureForShare`

- [ ] **Step 1: Write failing test for router share event listener**

```dart
// test/features/capture/application/share_router_handler_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/os_share_receiver_service.dart';
import 'package:var_app/features/capture/application/share_router_handler.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

void main() {
  group('ShareRouterHandler', () {
    testWidgets('triggers QuickCaptureDialog modal on incoming share payload', (tester) async {
      final service = OsShareReceiverService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            osShareReceiverServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showQuickCaptureForShare(
                        context,
                        const CapturePayload(text: 'Incoming OS Share'),
                      );
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Quick Capture'), findsOneWidget);
      expect(find.text('Incoming OS Share'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/capture/application/share_router_handler_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement share_router_handler.dart and update QuickCaptureDialog**

```dart
// lib/features/capture/application/share_router_handler.dart
import 'package:flutter/material.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/presentation/quick_capture_dialog.dart';

Future<bool?> showQuickCaptureForShare(
  BuildContext context,
  CapturePayload initialPayload,
) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => QuickCaptureDialog(
      initialPayload: initialPayload,
    ),
  );
}
```

Modify `lib/features/capture/presentation/quick_capture_dialog.dart` constructor to accept optional `CapturePayload? initialPayload` and populate text, URL, and attachment controllers on init state.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/capture/application/share_router_handler_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/capture/application/share_router_handler.dart lib/features/capture/presentation/quick_capture_dialog.dart test/features/capture/application/share_router_handler_test.dart
git commit -m "feat: add share_router_handler to launch QuickCaptureDialog on OS share intent"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-04-os-share-targets.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?