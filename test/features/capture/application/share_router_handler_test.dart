import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/os_share_receiver_service.dart';
import 'package:var_app/features/capture/application/share_router_handler.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

void main() {
  group('ShareRouterHandler', () {
    testWidgets('triggers QuickCaptureDialog modal on incoming share payload', (
      tester,
    ) async {
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
                        CapturePayload(
                          text: 'Incoming OS Share',
                          urls: const ['https://example.com/shared'],
                          attachments: [
                            CaptureFileAttachment(
                              fileName: 'shared.png',
                              mimeType: 'image/png',
                              bytes: Uint8List(0),
                            ),
                          ],
                        ),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Quick Capture'), findsOneWidget);
      expect(find.text('Incoming OS Share'), findsOneWidget);
      expect(find.text('https://example.com/shared'), findsOneWidget);
      expect(find.text('shared.png'), findsOneWidget);
      final saveButton = tester.widget<FilledButton>(
        find.byKey(const Key('quick_capture_save_button')),
      );
      expect(saveButton.onPressed, isNull);
    });
  });
}
