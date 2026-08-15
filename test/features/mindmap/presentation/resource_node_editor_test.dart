import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/resource_node_editor.dart';

void main() {
  testWidgets('resource preview renders adaptive asset families', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    const assets = <ResourceAsset>[
      ResourceAsset(
        id: 'image',
        kind: 'file',
        attachmentId: 'image-attachment',
        mimeType: 'image/png',
        fileName: 'image.png',
        extension: 'png',
      ),
      ResourceAsset(
        id: 'url',
        kind: 'url',
        location: 'https://example.com/reference',
      ),
      ResourceAsset(
        id: 'document',
        kind: 'file',
        attachmentId: 'document-attachment',
        fileName: 'manual.pdf',
        extension: 'pdf',
      ),
      ResourceAsset(
        id: 'audio',
        kind: 'file',
        attachmentId: 'audio-attachment',
        fileName: 'voice.mp3',
        extension: 'mp3',
      ),
      ResourceAsset(
        id: 'video',
        kind: 'file',
        attachmentId: 'video-attachment',
        fileName: 'clip.mp4',
        extension: 'mp4',
      ),
      ResourceAsset(
        id: 'generic',
        kind: 'file',
        attachmentId: 'generic-attachment',
        fileName: 'archive.bin',
        extension: 'bin',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                ResourceAssetPreview(asset: assets[0], bytes: png),
                for (final asset in assets.skip(1))
                  ResourceAssetPreview(asset: asset),
                const ResourceAssetPreview(
                  asset: ResourceAsset(
                    id: 'missing',
                    kind: 'file',
                    attachmentId: 'missing',
                    fileName: 'missing.pdf',
                    extension: 'pdf',
                  ),
                  error: 'Unavailable',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('resource-preview-image')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('resource-preview-url')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resource-preview-document')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-preview-audio')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-preview-video')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-preview-generic')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-preview-unavailable')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed resource previews files inside active folder', (
    tester,
  ) async {
    const payload = ResourcePayload(
      folders: <ResourceFolder>[
        ResourceFolder(id: 'research', name: 'Research'),
      ],
      folderPath: <String>['Research'],
      relatedAssets: <ResourceAsset>[
        ResourceAsset(
          id: 'manual',
          kind: 'file',
          attachmentId: 'manual-attachment',
          fileName: 'manual.pdf',
          extension: 'pdf',
          folderId: 'research',
        ),
        ResourceAsset(
          id: 'reference',
          kind: 'url',
          label: 'Reference',
          location: 'https://example.test/reference',
          folderId: 'research',
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 360,
            child: ResourceNodePreview(payload: payload, collapsed: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('resource-collapsed-folder-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-collapsed-asset-manual')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-collapsed-asset-reference')),
      findsOneWidget,
    );
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('manual.pdf'), findsOneWidget);
    expect(find.text('No asset selected'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource editor manages primary folder tags and related URL', (
    tester,
  ) async {
    var payload = const ResourcePayload();
    late StateSetter rebuild;
    const fileAsset = ResourceAsset(
      id: 'file-1',
      kind: 'file',
      label: 'Manual',
      attachmentId: 'attachment-1',
      mimeType: 'application/octet-stream',
      sizeBytes: 2048,
      fileName: 'manual.pdf',
      extension: 'pdf',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SingleChildScrollView(
                child: ResourceNodeEditor(
                  payload: payload,
                  folderSuggestions: const <List<String>>[
                    <String>['Research', 'Flutter'],
                  ],
                  onChooseFile: () async => fileAsset,
                  onOpenAsset: (_) async {},
                  onChanged: (value) {
                    payload = value;
                    rebuild(() {});
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('resource-primary-choose-file')),
    );
    await tester.pumpAndSettle();
    expect(payload.primaryAsset?.id, 'file-1');
    expect(
      find.byKey(const ValueKey('resource-preview-document')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('resource-folder-add')),
    );
    await tester.tap(find.byKey(const ValueKey('resource-folder-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('resource-folder-dialog-field')),
      'Research',
    );
    await tester.tap(find.byKey(const ValueKey('resource-folder-dialog-save')));
    await tester.pumpAndSettle();
    expect(payload.folderPath, const <String>['Research']);
    expect(payload.folders.single.name, 'Research');

    await tester.ensureVisible(find.byKey(const ValueKey('resource-tag-add')));
    await tester.tap(find.byKey(const ValueKey('resource-tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('resource-tag-dialog-field')),
      'flutter',
    );
    await tester.tap(find.byKey(const ValueKey('resource-tag-dialog-save')));
    await tester.pumpAndSettle();
    expect(payload.tags, const <String>['flutter']);

    await tester.ensureVisible(
      find.byKey(const ValueKey('resource-related-add-url')),
    );
    await tester.tap(find.byKey(const ValueKey('resource-related-add-url')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('resource-url-dialog-field')),
      'https://example.com/support',
    );
    await tester.tap(find.byKey(const ValueKey('resource-url-dialog-save')));
    await tester.pumpAndSettle();
    expect(payload.relatedAssets, hasLength(1));
    expect(payload.relatedAssets.single.kind, 'url');
    expect(payload.relatedAssets.single.folderId, payload.folders.single.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource URL dialog keeps invalid input editable', (
    tester,
  ) async {
    var payload = const ResourcePayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourceNodeEditor(
            payload: payload,
            onChanged: (value) => payload = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('resource-primary-paste-url')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('resource-url-dialog-field')),
      'file://unsafe',
    );
    await tester.tap(find.byKey(const ValueKey('resource-url-dialog-save')));
    await tester.pump();

    expect(find.text('Use an absolute HTTP or HTTPS URL.'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('resource-url-dialog-field')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'file://unsafe',
    );
    expect(payload.primaryAsset, isNull);
  });
}
