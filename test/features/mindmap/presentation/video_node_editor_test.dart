import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/media_travel_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/productivity_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  test('VideoPayload round-trips metadata, clamps position, removes bytes', () {
    const payload = VideoPayload(
      attachmentId: '12345678-1234-1234-1234-123456789abc',
      mimeType: 'video/mp4',
      fileName: 'clip.mp4',
      durationSeconds: 60,
      playbackPositionSeconds: 90,
      thumbnailUrl: 'https://example.test/poster.png',
      muted: true,
      caption: 'Demo',
      altText: 'Product demo',
    );
    final data = payload.toData({
      'keep': true,
      'videoBytes': [1, 2, 3],
    });
    final decoded = VideoPayload.fromNode(_node(data: data));
    expect(data['keep'], isTrue);
    expect(data.containsKey('videoBytes'), isFalse);
    expect(
      (data['video']! as Map<String, Object?>).containsKey('bytes'),
      isFalse,
    );
    expect(decoded.playbackPositionSeconds, 60);
    expect(decoded.muted, isTrue);
  });

  test('VideoPayload validates source, MIME, duration and thumbnail', () {
    expect(
      const VideoPayload(url: 'file:///clip.mp4').validate(title: 'Video'),
      contains('Video URL must use HTTPS, or HTTP localhost.'),
    );
    expect(
      const VideoPayload(
        url: 'https://example.test/clip.avi',
        mimeType: 'video/avi',
      ).validate(title: 'Video'),
      contains('Video MIME type is invalid.'),
    );
    expect(
      const VideoPayload(
        url: 'https://example.test/clip.mp4',
        durationSeconds: -1,
      ).validate(title: 'Video'),
      contains('Video duration is invalid.'),
    );
    expect(
      const VideoPayload(
        url: 'https://example.test/clip.mp4',
        thumbnailUrl: 'file:///poster.png',
      ).validate(title: 'Video'),
      contains('Thumbnail URL must use http or https.'),
    );
    expect(
      const VideoPayload(
        attachmentId: '12345678-1234-1234-1234-123456789abc',
      ).validate(title: 'Video'),
      contains('Local video MIME type is required.'),
    );
    expect(
      const VideoPayload(
        url: 'https://example.test/clip.mp4',
      ).validate(title: 'Video'),
      isEmpty,
    );
  });

  for (final preset in const [
    NodeSizePreset.compact,
    NodeSizePreset.standard,
    NodeSizePreset.large,
    NodeSizePreset.wide,
  ]) {
    testWidgets('renders overflow-safe ${preset.name} video content', (
      tester,
    ) async {
      final presentation = NodePresentationSpec.forType(
        NodeType.video,
      ).resolve(preset: preset);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: presentation.width,
              height: presentation.height,
              child: buildNodeTypeContent(
                NodeRenderContext(node: _node(), effectivePreset: preset),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('video-content-${preset.name}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('auto preset renders complete video editor', (tester) async {
    final node = _node();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 720,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: VideoPayload.fromNode(node),
                effectivePreset: NodeSizePreset.auto,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('video-editor-wide')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-url-video-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('video-preview-video-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded editor exposes every video detail without scrolling', (
    tester,
  ) async {
    final node = _node();
    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);
    expect(size, const InlineNodeWorkspaceSize(900, 820));
    await tester.binding.setSurfaceSize(
      Size(size.width + 40, size.height + 40),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: VideoPayload.fromNode(node),
                effectivePreset: NodeSizePreset.wide,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (_) {},
                onNodeDraftChanged: (_) {},
                onMediaAction: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    for (final key in <String>[
      'video-preview-video-0',
      'video-url-video-0',
      'video-caption-video-0',
      'video-alt-video-0',
      'video-muted-video-0',
      'video-fit-video-0',
      'video-save-position-video-0',
      'video-actions-video-0',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    await tester.ensureVisible(
      find.byKey(const ValueKey('video-actions-video-0')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('video-actions-video-0')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('video-editor-wide')),
        matching: find.byType(ListView),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor emits sequential drafts and open/export actions', (
    tester,
  ) async {
    final drafts = <Object>[];
    final actions = <Object>[];
    final node = _node(
      data: const VideoPayload(
        attachmentId: '12345678-1234-1234-1234-123456789abc',
        mimeType: 'video/mp4',
        fileName: 'clip.mp4',
      ).toData(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 420,
            child: buildNodeTypeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: VideoPayload.fromNode(node),
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const [],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: drafts.add,
                onNodeDraftChanged: (_) {},
                onMediaAction: (Object action) async => actions.add(action),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('video-caption-video-0')),
      'Caption',
    );
    await tester.enterText(
      find.byKey(const ValueKey('video-alt-video-0')),
      'Alt',
    );
    expect((drafts.last as VideoPayload).caption, 'Caption');
    expect((drafts.last as VideoPayload).altText, 'Alt');
    await tester.tap(find.text('Export'));
    expect(actions.single, isA<ExportVideoAction>());
  });

  testWidgets('production editor debounces slider and pause flushes', (
    tester,
  ) async {
    final scheduler = _FakeScheduler();
    final drafts = <Object>[];
    final node = _node();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 520,
            child: buildNodeTypeInlineEditor(
              _videoContext(
                node: node,
                drafts: drafts,
                scheduler: scheduler.schedule,
              ),
            ),
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('video-position-video-0')),
    );
    slider.onChanged?.call(10);
    slider.onChanged?.call(20);
    slider.onChanged?.call(30);
    await tester.pump();
    expect(drafts, isEmpty);
    scheduler.fire();
    await tester.pump();
    expect(drafts, hasLength(1));
    expect((drafts.single as VideoPayload).playbackPositionSeconds, 30);
    tester
        .widget<Slider>(find.byKey(const ValueKey('video-position-video-0')))
        .onChanged
        ?.call(40);
    tester
        .widget<TextButton>(
          find.byKey(const ValueKey('video-save-position-video-0')),
        )
        .onPressed
        ?.call();
    await tester.pump();
    expect(drafts, hasLength(2));
    expect((drafts.last as VideoPayload).playbackPositionSeconds, 40);
  });

  testWidgets('lifecycle and node switch flush pending session safely', (
    tester,
  ) async {
    final firstScheduler = _FakeScheduler();
    final secondScheduler = _FakeScheduler();
    final firstDrafts = <Object>[];
    final secondDrafts = <Object>[];
    final first = _node();
    final second = _nodeWithId('video-1');
    Widget app(NodeEditContext context) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 700,
          height: 520,
          child: buildNodeTypeInlineEditor(context),
        ),
      ),
    );
    await tester.pumpWidget(
      app(
        _videoContext(
          node: first,
          drafts: firstDrafts,
          scheduler: firstScheduler.schedule,
        ),
      ),
    );
    tester
        .widget<Slider>(find.byKey(const ValueKey('video-position-video-0')))
        .onChanged
        ?.call(25);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect((firstDrafts.single as VideoPayload).playbackPositionSeconds, 25);
    tester
        .widget<Slider>(find.byKey(const ValueKey('video-position-video-0')))
        .onChanged
        ?.call(35);
    await tester.pumpWidget(
      app(
        _videoContext(
          node: second,
          drafts: secondDrafts,
          scheduler: secondScheduler.schedule,
        ),
      ),
    );
    await tester.pump();
    expect((firstDrafts.last as VideoPayload).playbackPositionSeconds, 25);
    expect(secondDrafts, isEmpty);
    tester
        .widget<Slider>(find.byKey(const ValueKey('video-position-video-1')))
        .onChanged
        ?.call(50);
    final externallyUpdated = second.copyWith(
      data: VideoPayload.fromNode(
        second,
      ).copyWith(caption: 'Latest caption', muted: true).toData(second.data),
      updatedAt: DateTime(2026, 7, 13, 1),
    );
    await tester.pumpWidget(
      app(
        _videoContext(
          node: externallyUpdated,
          drafts: secondDrafts,
          scheduler: secondScheduler.schedule,
        ),
      ),
    );
    await tester.pump();
    final merged = secondDrafts.single as VideoPayload;
    expect(merged.playbackPositionSeconds, 50);
    expect(merged.caption, 'Latest caption');
    expect(merged.muted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test(
    'playback draft debounce is single-flight and lifecycle flushes',
    () async {
      final scheduler = _FakeScheduler();
      final persisted = <double>[];
      final firstWrite = Completer<void>();
      var writes = 0;
      final controller = VideoPlaybackDraftController(
        scheduler: scheduler.schedule,
        onPersist: (value) {
          persisted.add(value);
          writes++;
          return writes == 1 ? firstWrite.future : Future.value();
        },
      );
      controller.update(10, durationSeconds: 100);
      controller.update(20, durationSeconds: 100);
      scheduler.fire();
      await Future<void>.delayed(Duration.zero);
      controller.update(150, durationSeconds: 100);
      final flush = controller.onPause();
      firstWrite.complete();
      await flush;
      expect(persisted, [20, 100]);
      controller.update(40, durationSeconds: 100);
      await controller.onLifecycleInactive();
      expect(persisted, [20, 100, 40]);
      await controller.close();
    },
  );

  test(
    'timer persistence errors are reported without uncaught futures',
    () async {
      final scheduler = _FakeScheduler();
      final errors = <Object>[];
      final controller = VideoPlaybackDraftController(
        scheduler: scheduler.schedule,
        onPersist: (_) => Future<void>.error(StateError('save failed')),
        onError: (error, _) => errors.add(error),
      );
      controller.update(10, durationSeconds: 20);
      scheduler.fire();
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<StateError>());
      expect(controller.lastError, isA<StateError>());
      controller.discard();
    },
  );
}

MindmapNode _node({Map<String, Object?>? data}) => MindmapNode.create(
  id: 'video-0',
  type: NodeType.video,
  title: 'Video',
  body: '',
  day: DateTime(2026, 7, 13),
  data:
      data ??
      const VideoPayload(
        url: 'https://example.test/clip.mp4',
        durationSeconds: 90,
        caption: 'Demo clip',
        altText: 'Demo video',
      ).toData(),
  now: DateTime(2026, 7, 13),
);

MindmapNode _nodeWithId(String id) => MindmapNode.create(
  id: id,
  type: NodeType.video,
  title: 'Video',
  day: DateTime(2026, 7, 13),
  data: const VideoPayload(
    url: 'https://example.test/second.mp4',
    durationSeconds: 120,
  ).toData(),
  now: DateTime(2026, 7, 13),
);

NodeEditContext _videoContext({
  required MindmapNode node,
  required List<Object> drafts,
  required VideoPlaybackSchedule scheduler,
}) => NodeEditContext(
  node: node,
  typedDraft: VideoPayload.fromNode(node),
  effectivePreset: NodeSizePreset.large,
  validationErrors: const [],
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: drafts.add,
  onNodeDraftChanged: (_) {},
  videoPlaybackScheduler: scheduler,
  videoPlaybackDebounce: const Duration(seconds: 1),
);

final class _FakeScheduler {
  void Function()? callback;
  VideoPlaybackTimer schedule(Duration _, void Function() value) {
    callback = value;
    return _FakeTimer(() => callback = null);
  }

  void fire() {
    final value = callback;
    callback = null;
    value?.call();
  }
}

final class _FakeTimer implements VideoPlaybackTimer {
  const _FakeTimer(this.onCancel);
  final void Function() onCancel;
  @override
  void cancel() => onCancel();
}
