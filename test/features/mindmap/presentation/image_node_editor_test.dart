import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/media_travel_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  test('payload preserves metadata and never stores bytes', () {
    const payload = ImagePayload(
      attachmentId: '12345678-1234-1234-1234-123456789abc',
      mimeType: 'image/png',
      fileName: 'photo.png',
      caption: 'Trip',
      altText: 'Mountain',
      width: 800,
      height: 600,
    );
    final data = payload.toData({
      'keep': true,
      'bytes': Uint8List.fromList([1]),
    });
    expect(data['keep'], isTrue);
    expect(data.containsKey('bytes'), isFalse);
    expect(
      (data['image']! as Map<String, Object?>).containsKey('bytes'),
      isFalse,
    );
    expect(payload.validate(title: 'Photo'), isEmpty);
    expect(
      const ImagePayload(url: 'file:///tmp/a.png').validate(title: 'Photo'),
      contains('Image URL must use http or https.'),
    );
    expect(
      const ImagePayload(
        attachmentId: '12345678-1234-1234-1234-123456789abc',
        mimeType: 'image/svg+xml',
      ).validate(title: 'Photo'),
      contains('Image MIME type is invalid.'),
    );
  });

  test('external image URL safety rejects local and malformed targets', () {
    expect(isValidExternalImageUrl('file:///tmp/photo.png'), isFalse);
    expect(isValidExternalImageUrl('not a URL'), isFalse);
    expect(isValidExternalImageUrl('https:///missing-host.png'), isFalse);
    expect(isValidExternalImageUrl('https://example.test/photo.png'), isTrue);
  });

  for (final preset in const [
    NodeSizePreset.compact,
    NodeSizePreset.standard,
    NodeSizePreset.large,
    NodeSizePreset.wide,
  ]) {
    testWidgets('renders distinct ${preset.name} image content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          buildNodeTypeContent(
            NodeRenderContext(
              node: _node(),
              effectivePreset: preset,
              attachmentBytes: _png,
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('image-content-${preset.name}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('image-local-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renders URL, semantic alt, caption and missing-alt warning', (
    tester,
  ) async {
    final remote = _node(
      payload: const ImagePayload(
        url: 'https://example.test/photo.png',
        caption: 'Remote caption',
        altText: 'Remote landscape',
        fitMode: ImageFitMode.cover,
      ),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: remote,
            effectivePreset: NodeSizePreset.large,
          ),
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey(
          'image-network-preview-https://example.test/photo.png-0',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Remote caption'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Remote landscape',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: _node(
              payload: const ImagePayload(url: 'https://example.test/a.png'),
            ),
            effectivePreset: NodeSizePreset.standard,
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Image alt text is missing',
      ),
      findsOneWidget,
    );
  });

  testWidgets('editor keeps sequential edits and emits media actions', (
    tester,
  ) async {
    final drafts = <Object>[];
    final actions = <Object>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(drafts, actions, error: 'Load failed'),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('image-caption-image-0')),
      'First caption',
    );
    await tester.enterText(
      find.byKey(const ValueKey('image-alt-image-0')),
      'Useful alt',
    );
    expect((drafts.last as ImagePayload).caption, 'First caption');
    expect((drafts.last as ImagePayload).altText, 'Useful alt');
    await tester.tap(find.text('Replace'));
    await tester.tap(find.text('Export'));
    await tester.tap(find.text('Retry'));
    expect(actions, hasLength(3));
    expect(actions[0], isA<ReplaceImageAction>());
    expect(actions[1], isA<ExportImageAction>());
    expect(actions[2], isA<RetryImageAction>());
  });

  testWidgets('remote editor emits open action and fit change', (tester) async {
    final drafts = <Object>[];
    final actions = <Object>[];
    const payload = ImagePayload(
      url: 'https://example.test/a.png',
      altText: 'A',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(_context(drafts, actions, payload: payload)),
      ),
    );
    await tester.tap(find.text('contain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cover').last);
    await tester.pumpAndSettle();
    expect((drafts.last as ImagePayload).fitMode, ImageFitMode.cover);
    await tester.tap(find.text('Open externally'));
    expect(actions.last, isA<OpenImageExternallyAction>());
  });

  testWidgets('switching source and removing image clear stale file metadata', (
    tester,
  ) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            drafts,
            <Object>[],
            payload: const ImagePayload(
              attachmentId: '12345678-1234-1234-1234-123456789abc',
              mimeType: 'image/png',
              fileName: 'old.png',
              width: 640,
              height: 480,
              byteLength: 1024,
              originalAttachmentId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              altText: 'Image',
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('image-url-image-0')),
      'https://example.test/replacement.png',
    );
    var payload = drafts.last as ImagePayload;
    expect(payload.attachmentId, isEmpty);
    expect(payload.mimeType, isEmpty);
    expect(payload.fileName, isEmpty);
    expect(payload.width, isNull);
    expect(payload.height, isNull);
    expect(payload.byteLength, isNull);
    expect(payload.originalAttachmentId, isEmpty);

    await tester.tap(find.text('Remove from node'));
    payload = drafts.last as ImagePayload;
    expect(payload.attachmentId, isEmpty);
    expect(payload.url, isEmpty);
    expect(payload.mimeType, isEmpty);
    expect(payload.fileName, isEmpty);
    expect(payload.width, isNull);
    expect(payload.height, isNull);
    expect(payload.byteLength, isNull);
    expect(payload.originalAttachmentId, isEmpty);
  });

  testWidgets('editor autosaves tags transforms filters and annotations', (
    tester,
  ) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _context(
            drafts,
            <Object>[],
            payload: const ImagePayload(
              url: 'https://example.test/a.png',
              altText: 'Image',
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('image-tag-input')),
      'reference',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byTooltip('Rotate right'));
    await tester.ensureVisible(find.byKey(const ValueKey('image-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('none'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('warm').last);
    await tester.pumpAndSettle();
    final rectangle = find.byKey(
      const ValueKey('image-annotation-add-rectangle'),
      skipOffstage: false,
    );
    await tester.drag(
      find.byKey(const ValueKey('image-editor-fields')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(rectangle);
    await tester.pump();
    final rectangleSurface = find.byKey(
      const ValueKey('image-annotation-draw-rectangle'),
    );
    await tester.drag(rectangleSurface, const Offset(70, 50));
    await tester.pump();

    final payload = drafts.last as ImagePayload;
    expect(payload.tags, contains('reference'));
    expect(payload.rotationQuarterTurns, 1);
    expect(payload.filter, ImageFilterPreset.warm);
    expect(payload.annotations.single.type, ImageAnnotationType.rectangle);
  });

  testWidgets('annotation can be selected dragged resized and edited', (
    tester,
  ) async {
    final drafts = <Object>[];
    const annotation = ImageAnnotation(
      id: 'editable-annotation',
      type: ImageAnnotationType.rectangle,
      text: 'Draft',
      positionX: 0.1,
      positionY: 0.1,
      width: 0.25,
      height: 0.14,
    );
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(
          _context(
            drafts,
            <Object>[],
            payload: const ImagePayload(
              attachmentId: '12345678-1234-1234-1234-123456789abc',
              mimeType: 'image/png',
              fileName: 'photo.png',
              altText: 'Image',
              annotations: <ImageAnnotation>[annotation],
            ),
          ),
        ),
        const Size(900, 820),
      ),
    );

    final overlay = find.byKey(
      const ValueKey('image-annotation-overlay-editable-annotation'),
    );
    await tester.tap(overlay);
    await tester.drag(overlay, const Offset(36, 24));
    await tester.pump();
    var updated = drafts.last as ImagePayload;
    expect(updated.annotations.single.positionX, greaterThan(0.1));
    expect(updated.annotations.single.positionY, greaterThan(0.1));

    await tester.drag(
      find.byKey(const ValueKey('image-annotation-resize-editable-annotation')),
      const Offset(30, 20),
    );
    await tester.pump();
    updated = drafts.last as ImagePayload;
    expect(updated.annotations.single.width, greaterThan(0.25));
    expect(updated.annotations.single.height, greaterThan(0.14));

    final color = find.byKey(const ValueKey('image-annotation-color-ff40c4ff'));
    await tester.ensureVisible(color);
    await tester.pumpAndSettle();
    await tester.tap(color);
    await tester.pump();
    updated = drafts.last as ImagePayload;
    expect(updated.annotations.single.color, 0xFF40C4FF);

    final stroke = find.byKey(const ValueKey('image-annotation-stroke'));
    await tester.ensureVisible(stroke);
    await tester.pumpAndSettle();
    tester.widget<Slider>(stroke).onChanged!(8);
    await tester.pump();

    updated = drafts.last as ImagePayload;
    expect(updated.annotations.single.text, 'Draft');
    expect(updated.annotations.single.color, 0xFF40C4FF);
    expect(updated.annotations.single.strokeWidth, 8);
  });

  testWidgets('text annotation can be placed and typed on preview', (
    tester,
  ) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(_context(drafts, <Object>[])),
        const Size(900, 820),
      ),
    );

    final textTool = find.byKey(
      const ValueKey('image-annotation-add-text'),
      skipOffstage: false,
    );
    await tester.drag(
      find.byKey(const ValueKey('image-editor-fields')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(textTool);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-annotation-draw-text')));
    await tester.pump();

    var payload = drafts.last as ImagePayload;
    expect(payload.annotations.single.type, ImageAnnotationType.text);
    final textField = find.byKey(
      ValueKey('image-annotation-inline-text-${payload.annotations.single.id}'),
    );
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Caption on image');
    await tester.pump();

    payload = drafts.last as ImagePayload;
    expect(payload.annotations.single.text, 'Caption on image');
  });

  testWidgets('arrow drag preserves start and end direction', (tester) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(_context(drafts, <Object>[])),
        const Size(900, 820),
      ),
    );

    final arrowTool = find.byKey(
      const ValueKey('image-annotation-add-arrow'),
      skipOffstage: false,
    );
    await tester.drag(
      find.byKey(const ValueKey('image-editor-fields')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(arrowTool);
    await tester.pump();
    final surface = find.byKey(const ValueKey('image-annotation-draw-arrow'));
    await tester.drag(surface, const Offset(-90, 70));
    await tester.pump();

    final annotation = (drafts.last as ImagePayload).annotations.single;
    expect(annotation.type, ImageAnnotationType.arrow);
    expect(annotation.points, hasLength(greaterThanOrEqualTo(2)));
    expect(annotation.points.first.x, greaterThan(annotation.points.last.x));
    expect(annotation.points.first.y, lessThan(annotation.points.last.y));
  });

  testWidgets('freehand drag stores drawn path', (tester) async {
    final drafts = <Object>[];
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(_context(drafts, <Object>[])),
        const Size(900, 820),
      ),
    );

    final freehandTool = find.byKey(
      const ValueKey('image-annotation-add-freehand'),
      skipOffstage: false,
    );
    await tester.drag(
      find.byKey(const ValueKey('image-editor-fields')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.tap(freehandTool);
    await tester.pump();
    final surface = find.byKey(
      const ValueKey('image-annotation-draw-freehand'),
    );
    final center = tester.getCenter(surface);
    final gesture = await tester.startGesture(center - const Offset(50, 30));
    await gesture.moveBy(const Offset(25, 40));
    await gesture.moveBy(const Offset(45, -15));
    await gesture.up();
    await tester.pump();

    final annotation = (drafts.last as ImagePayload).annotations.single;
    expect(annotation.type, ImageAnnotationType.freehand);
    expect(annotation.points, hasLength(greaterThanOrEqualTo(3)));
    expect(annotation.points.toSet(), hasLength(greaterThan(1)));
  });

  testWidgets('unsafe image targets hide external open actions', (
    tester,
  ) async {
    for (final target in const ['file:///tmp/photo.png', 'not a URL']) {
      final actions = <Object>[];
      final node = _node(
        payload: ImagePayload(url: target, altText: 'Unsafe image'),
      );
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              Expanded(
                child: buildNodeTypeContent(
                  NodeRenderContext(
                    node: node,
                    effectivePreset: NodeSizePreset.large,
                    onMediaAction: (Object action) async => actions.add(action),
                  ),
                ),
              ),
              Expanded(
                child: buildNodeTypeInlineEditor(
                  _context(
                    <Object>[],
                    actions,
                    payload: ImagePayload(url: target, altText: 'Unsafe image'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Open externally'), findsNothing);
      expect(find.byKey(const ValueKey('image-network-open')), findsNothing);
      expect(actions, isEmpty);
    }
  });

  testWidgets('remote failure exposes retry and rebuilds network revision', (
    tester,
  ) async {
    final actions = <Object>[];
    final node = _node(
      payload: const ImagePayload(
        url: 'https://invalid.example.test/photo.png',
        altText: 'Remote',
      ),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: node,
            effectivePreset: NodeSizePreset.large,
            onMediaAction: (Object action) async => actions.add(action),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-network-retry')), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'image-network-preview-https://invalid.example.test/photo.png-0',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('image-network-retry')));
    await tester.pump();
    expect(
      find.byKey(
        const ValueKey(
          'image-network-preview-https://invalid.example.test/photo.png-1',
        ),
      ),
      findsOneWidget,
    );
    expect(actions.last, isA<RetryImageAction>());
  });

  testWidgets('image editor resets fields when selected node changes', (
    tester,
  ) async {
    const first = ImagePayload(
      url: 'https://example.test/first.png',
      caption: 'First',
      altText: 'First alt',
    );
    const second = ImagePayload(
      url: 'https://example.test/second.png',
      caption: 'Second',
      altText: 'Second alt',
    );
    NodeEditContext contextFor(String id, ImagePayload payload) =>
        NodeEditContext(
          node: _node(id: id, payload: payload),
          typedDraft: payload,
          effectivePreset: NodeSizePreset.large,
          validationErrors: const [],
          onTitleChanged: (_) {},
          onBodyChanged: (_) {},
          onDraftChanged: (_) {},
          onNodeDraftChanged: (_) {},
        );
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(contextFor('first', first))),
    );
    await tester.enterText(
      find.byKey(const ValueKey('image-caption-first-0')),
      'Local edit',
    );
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(contextFor('second', second))),
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('image-caption-second-1')),
          )
          .initialValue,
      'Second',
    );
  });

  testWidgets('image fields keep focus across autosave echo rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(const _ImageDraftEchoHarness());

    const entries = <(ValueKey<String>, String)>[
      (
        ValueKey<String>('image-url-image-echo-0'),
        'https://example.test/assets/photo/a-b.png?x=1&y=2#preview',
      ),
      (ValueKey<String>('image-caption-image-echo-0'), 'Caption / copied'),
      (ValueKey<String>('image-alt-image-echo-0'), 'Alt text & symbols'),
      (
        ValueKey<String>('image-source-url-image-echo-0'),
        'https://source.example.test/library/item/42',
      ),
    ];

    for (final entry in entries) {
      final field = find.byKey(entry.$1);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.enterText(field, entry.$2);
      await tester.pump();

      expect(field, findsOneWidget, reason: entry.$1.value);
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.controller.text, entry.$2);
      expect(editable.focusNode.hasFocus, isTrue, reason: entry.$1.value);
    }

    final tagField = find.byKey(const ValueKey('image-tag-input'));
    await tester.ensureVisible(tagField);
    await tester.tap(tagField);
    await tester.enterText(tagField, 'reference/copied');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('reference/copied'), findsOneWidget);
  });

  testWidgets('image editor uses professional two-column studio', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(_context(<Object>[], <Object>[])),
        const Size(900, 820),
      ),
    );

    expect(
      find.byKey(const ValueKey('image-editor-two-column')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('image-preview-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('image-inspector-source')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('image-inspector-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('image-inspector-adjustments')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('image-inspector-annotations')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('image-editor-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image editor stacks without overflow on narrow width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appAtSize(
        buildNodeTypeInlineEditor(_context(<Object>[], <Object>[])),
        const Size(640, 820),
      ),
    );

    expect(find.byKey(const ValueKey('image-editor-stacked')), findsOneWidget);
    expect(find.byKey(const ValueKey('image-editor-footer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ImageDraftEchoHarness extends StatefulWidget {
  const _ImageDraftEchoHarness();

  @override
  State<_ImageDraftEchoHarness> createState() => _ImageDraftEchoHarnessState();
}

class _ImageDraftEchoHarnessState extends State<_ImageDraftEchoHarness> {
  ImagePayload _payload = const ImagePayload(
    attachmentId: '12345678-1234-1234-1234-123456789abc',
    mimeType: 'image/png',
    fileName: 'photo.png',
  );

  @override
  Widget build(BuildContext context) => _app(
    buildNodeTypeInlineEditor(
      NodeEditContext(
        node: _node(id: 'image-echo', payload: _payload),
        typedDraft: _payload,
        effectivePreset: NodeSizePreset.wide,
        validationErrors: _payload.validate(title: 'Photo'),
        onTitleChanged: (_) {},
        onBodyChanged: (_) {},
        onDraftChanged: (value) {
          if (value is! ImagePayload) return;
          setState(() {
            _payload = ImagePayload.fromNode(
              _node(id: 'image-echo', payload: value),
            );
          });
        },
        onNodeDraftChanged: (_) {},
        attachmentBytes: _png,
      ),
    ),
  );
}

final _png = Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);
Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 720, height: 560, child: child)),
);

Widget _appAtSize(Widget child, Size size) => MaterialApp(
  home: Scaffold(
    body: SizedBox.fromSize(size: size, child: child),
  ),
);
MindmapNode _node({
  String id = 'image',
  ImagePayload payload = const ImagePayload(
    attachmentId: '12345678-1234-1234-1234-123456789abc',
    mimeType: 'image/png',
    fileName: 'photo.png',
    caption: 'Caption',
    altText: 'Mountain',
  ),
}) {
  final now = DateTime(2026, 7, 13);
  return MindmapNode.create(
    id: id,
    type: NodeType.image,
    title: 'Photo',
    day: now,
    now: now,
    data: payload.toData(),
  );
}

NodeEditContext _context(
  List<Object> drafts,
  List<Object> actions, {
  ImagePayload payload = const ImagePayload(
    attachmentId: '12345678-1234-1234-1234-123456789abc',
    mimeType: 'image/png',
    fileName: 'photo.png',
  ),
  String? error,
}) => NodeEditContext(
  node: _node(payload: payload),
  typedDraft: payload,
  effectivePreset: NodeSizePreset.wide,
  validationErrors: payload.validate(title: 'Photo'),
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: drafts.add,
  onNodeDraftChanged: (_) {},
  attachmentBytes: _png,
  attachmentError: error,
  onMediaAction: (Object action) async => actions.add(action),
);
