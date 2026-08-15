import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/mindmap_canvas.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/media_travel_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/productivity_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_shell.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  test('cache parses media payload once across equal node reconstruction', () {
    final cache = MindmapNodePresentationCache();
    final nodes = <MindmapNode>[
      _imageNode(const ImagePayload(url: 'https://example.test/photo.png')),
      _videoNode(const VideoPayload(url: 'https://example.test/video.mp4')),
      _node(
        NodeType.itinerary,
        'Trip',
        ItineraryPayload(
          destination: 'Kyoto',
          startDate: DateTime(2026, 10, 2),
          endDate: DateTime(2026, 10, 3),
          timezone: 'Asia/Tokyo',
        ).toData(),
      ),
    ];

    cache.sizesFor(nodes);
    expect(cache.payloadParseCount, 3);
    expect(cache.typedPayloadFor(nodes[0]), isA<ImagePayload>());
    expect(cache.typedPayloadFor(nodes[1]), isA<VideoPayload>());
    expect(cache.typedPayloadFor(nodes[2]), isA<ItineraryPayload>());
    cache.sizesFor([for (final node in nodes) node.copyWith()]);
    expect(cache.payloadParseCount, 3);
  });

  testWidgets('renderer consumes cached media payload instead of node data', (
    tester,
  ) async {
    final node = _node(NodeType.image, 'Cached photo', const {});
    const cached = ImagePayload(
      url: 'https://example.test/cached.png',
      altText: 'Cached alt',
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: node,
            typedPayload: cached,
            effectivePreset: NodeSizePreset.compact,
          ),
        ),
      ),
    );

    expect(
      find.byKey(
        const ValueKey(
          'image-network-preview-https://example.test/cached.png-0',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Cached alt',
      ),
      findsWidgets,
    );
  });

  testWidgets('node resize and preset controls support keyboard focus', (
    tester,
  ) async {
    final changes = <NodeResizeChange>[];
    await tester.pumpWidget(
      _app(
        NodeShell(
          type: NodeType.note,
          size: const Size(320, 220),
          color: const Color(0xFFD946EF),
          isSelected: true,
          preset: NodeSizePreset.standard,
          onResizeChanged: changes.add,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final preset = find.byKey(NodeShell.presetButtonKey);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(_primaryFocusWithin(preset), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Wide'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Wide'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Wide'), findsOneWidget);
    for (var index = 0; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes.single.preset, NodeSizePreset.wide);

    final resizeSemantics = tester.getSemantics(
      find.byKey(NodeShell.accessibleResizeKey),
    );
    expect(
      resizeSemantics.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      resizeSemantics.getSemanticsData().hasAction(SemanticsAction.decrease),
      isTrue,
    );
    final semantics = tester.widget<Semantics>(
      find.byKey(NodeShell.accessibleResizeKey),
    );
    semantics.properties.onIncrease?.call();
    semantics.properties.onDecrease?.call();
    await tester.pump();
    expect(changes, hasLength(3));
    expect(changes[1].size, isNot(changes[2].size));
  });

  testWidgets('image semantics and bounded decode preserve byte identity', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(_png);
    final node = _imageNode(
      const ImagePayload(
        attachmentId: '12345678-1234-1234-1234-123456789abc',
        mimeType: 'image/png',
        fileName: 'photo.png',
      ),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeContent(
          NodeRenderContext(
            node: node,
            effectivePreset: NodeSizePreset.standard,
            attachmentBytes: bytes,
          ),
        ),
      ),
    );

    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('image-content-standard')))
          .label,
      contains('Photo'),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Image alt text is missing',
      ),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('image-local-preview')),
    );
    final resized = image.image as ResizeImage;
    expect(resized.width, 320);
    expect(resized.height, 320);
    expect((resized.imageProvider as MemoryImage).bytes, same(bytes));
  });

  testWidgets('video fallback actions expose semantic enabled states', (
    tester,
  ) async {
    final actions = <Object>[];
    final local = _videoNode(
      const VideoPayload(
        attachmentId: '12345678-1234-1234-1234-123456789abc',
        mimeType: 'video/mp4',
        fileName: 'clip.mp4',
        durationSeconds: 120,
        playbackPositionSeconds: 30,
      ),
    );
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _editContext(local, VideoPayload.fromNode(local), actions),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('Save position'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Open externally'), findsNothing);
    final export = find.widgetWithText(OutlinedButton, 'Export');
    expect(
      tester.getSemantics(export).getSemanticsData().flagsCollection.isEnabled,
      Tristate.isTrue,
    );
    await tester.tap(export);
    expect(actions.single, isA<ExportVideoAction>());
  });

  testWidgets('itinerary controls activate by keyboard and remain labeled', (
    tester,
  ) async {
    final actions = <Object>[];
    final payload = ItineraryPayload(
      destination: 'Kyoto',
      startDate: DateTime(2026, 10, 2),
      endDate: DateTime(2026, 10, 3),
      timezone: 'Asia/Tokyo',
      agenda: const [
        ItineraryAgendaItem(
          id: 'temple',
          title: 'Temple',
          startMinutes: 540,
          durationMinutes: 60,
        ),
      ],
    );
    final node = _node(NodeType.itinerary, 'Trip', payload.toData());
    await tester.pumpWidget(
      _app(buildNodeTypeInlineEditor(_editContext(node, payload, actions))),
    );

    final toggle = find.byType(Checkbox);
    expect(toggle, findsOneWidget);
    await _tabTo(tester, toggle);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect((actions.last as ItineraryPayload).agenda.single.completed, isTrue);

    final convert = find.byTooltip('Convert Temple to task');
    await tester.ensureVisible(convert);
    await _tabTo(tester, convert);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(actions.last, isA<ConvertItineraryAgendaAction>());
  });
}

bool _primaryFocusWithin(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) return false;
  final targets = finder.evaluate().toSet();
  if (targets.contains(context)) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (targets.contains(element)) found = true;
    return !found;
  });
  return found;
}

Future<void> _tabTo(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 20 && !_primaryFocusWithin(finder); index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_primaryFocusWithin(finder), isTrue);
}

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 760, height: 620, child: child)),
);

NodeEditContext _editContext(
  MindmapNode node,
  Object payload,
  List<Object> actions,
) => NodeEditContext(
  node: node,
  typedDraft: payload,
  effectivePreset: NodeSizePreset.wide,
  validationErrors: const [],
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: actions.add,
  onNodeDraftChanged: (_) {},
  onMediaAction: (Object action) async => actions.add(action),
  onItineraryAction: (Object action) async => actions.add(action),
);

MindmapNode _imageNode(ImagePayload payload) =>
    _node(NodeType.image, 'Photo', payload.toData());

MindmapNode _videoNode(VideoPayload payload) =>
    _node(NodeType.video, 'Video', payload.toData());

MindmapNode _node(NodeType type, String title, Map<String, Object?> data) =>
    MindmapNode.create(
      id: '${type.name}-task18',
      type: type,
      title: title,
      day: DateTime(2026, 7, 14),
      now: DateTime(2026, 7, 14, 8),
      data: data,
    );

const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
];
