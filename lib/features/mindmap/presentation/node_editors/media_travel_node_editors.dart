import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/node_presentation.dart';
import '../../domain/node_type_payloads.dart';
import '../video_playback/video_playback.dart';
import 'life_data_node_editors.dart';
import 'productivity_node_editors.dart';

enum ItineraryConversionTarget { task, event }

final class ConvertItineraryAgendaAction {
  const ConvertItineraryAgendaAction({
    required this.item,
    required this.target,
  });
  final ItineraryAgendaItem item;
  final ItineraryConversionTarget target;
}

sealed class ImageNodeAction {
  const ImageNodeAction();
}

final class ReplaceImageAction extends ImageNodeAction {
  const ReplaceImageAction();
}

final class ExportImageAction extends ImageNodeAction {
  const ExportImageAction(this.attachmentId);
  final String attachmentId;
}

final class RetryImageAction extends ImageNodeAction {
  const RetryImageAction();
}

final class OpenImageExternallyAction extends ImageNodeAction {
  const OpenImageExternallyAction(this.target);
  final String target;
}

final class SaveEditedImageAction extends ImageNodeAction {
  SaveEditedImageAction({required this.bytes, required this.existing});
  final Uint8List bytes;
  final ImagePayload existing;
  final Completer<ImagePayload?> result = Completer<ImagePayload?>();
}

final class RestoreOriginalImageAction extends ImageNodeAction {
  RestoreOriginalImageAction(this.existing);
  final ImagePayload existing;
  final Completer<ImagePayload?> result = Completer<ImagePayload?>();
}

sealed class VideoNodeAction {
  const VideoNodeAction();
}

final class OpenVideoExternallyAction extends VideoNodeAction {
  const OpenVideoExternallyAction(this.target);
  final String target;
}

final class ExportVideoAction extends VideoNodeAction {
  const ExportVideoAction(this.attachmentId);
  final String attachmentId;
}

final class ReplaceVideoAction extends VideoNodeAction {
  const ReplaceVideoAction();
}

bool isValidExternalVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && isAllowedVideoRemoteUri(uri);
}

typedef VideoPlaybackTimer = NodeDraftTimer;
typedef VideoPlaybackSchedule = NodeDraftSchedule;

final class VideoPlaybackDraftController {
  VideoPlaybackDraftController({
    required this.onPersist,
    this.debounce = const Duration(milliseconds: 750),
    VideoPlaybackSchedule? scheduler,
    this.onError,
  }) : _scheduler = scheduler ?? _defaultSchedule;

  final Future<void> Function(double positionSeconds) onPersist;
  final Duration debounce;
  final VideoPlaybackSchedule _scheduler;
  final void Function(Object error, StackTrace stackTrace)? onError;
  VideoPlaybackTimer? _timer;
  double? _pending;
  Future<void>? _write;
  bool _disposed = false;
  Object? lastError;

  void update(double positionSeconds, {required double durationSeconds}) {
    if (_disposed) return;
    _pending = positionSeconds.clamp(
      0,
      durationSeconds > 0 ? durationSeconds : double.infinity,
    );
    _timer?.cancel();
    _timer = _scheduler(debounce, () {
      unawaited(flush().catchError(_handleError));
    });
  }

  FutureOr<void> _handleError(Object error, StackTrace stackTrace) {
    lastError = error;
    onError?.call(error, stackTrace);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final active = _write;
    if (active != null) await active;
    final value = _pending;
    if (value == null || _disposed) return;
    _pending = null;
    final write = onPersist(value);
    _write = write;
    try {
      await write;
    } finally {
      if (identical(_write, write)) _write = null;
    }
    if (_pending != null) await flush();
  }

  Future<void> onPause() => flush();
  Future<void> onLifecycleInactive() => flush();

  Future<void> close() async {
    await flush();
    _disposed = true;
    _timer?.cancel();
  }

  void discard() {
    _pending = null;
    _timer?.cancel();
    _timer = null;
    _disposed = true;
  }

  static VideoPlaybackTimer _defaultSchedule(
    Duration duration,
    void Function() callback,
  ) => _DartVideoPlaybackTimer(Timer(duration, callback));
}

final class _DartVideoPlaybackTimer implements VideoPlaybackTimer {
  const _DartVideoPlaybackTimer(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}

bool isValidExternalImageUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

Widget buildMediaTravelNodeContent(NodeRenderContext context) =>
    switch (context.node.type) {
      NodeType.itinerary => _ItineraryContent(context),
      NodeType.image => _ImageContent(context),
      NodeType.video => _VideoContent(context),
      _ => buildLifeDataNodeContent(context),
    };

Widget buildMediaTravelNodeInlineEditor(NodeEditContext context) =>
    switch (context.node.type) {
      NodeType.itinerary => _ItineraryEditor(context),
      NodeType.image => _ImageEditor(context),
      NodeType.video => _VideoEditor(context),
      _ => buildLifeDataNodeInlineEditor(context),
    };

final class _ImageContent extends StatelessWidget {
  const _ImageContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final payload = context.typedPayload is ImagePayload
        ? context.typedPayload! as ImagePayload
        : ImagePayload.fromNode(context.node);
    final preset = context.effectivePreset;
    final preview = _imagePreview(
      payload: payload,
      bytes: context.attachmentBytes,
      loading: context.attachmentLoading,
      error: context.attachmentError,
      onAction: context.onMediaAction,
      cacheSize: switch (preset) {
        NodeSizePreset.compact => 160,
        NodeSizePreset.standard => 320,
        NodeSizePreset.large => 640,
        _ => 900,
      },
    );
    final warning = payload.altText.trim().isEmpty
        ? Semantics(
            liveRegion: true,
            label: 'Image alt text is missing',
            child: const Row(
              children: [
                Icon(Icons.warning_amber, size: 16),
                SizedBox(width: 4),
                Text('Add alt text'),
              ],
            ),
          )
        : const SizedBox.shrink();
    final actions = Wrap(
      spacing: 8,
      children: [
        if (context.attachmentError != null)
          TextButton(
            onPressed: () =>
                context.onMediaAction?.call(const RetryImageAction()),
            child: const Text('Retry'),
          ),
        if (isValidExternalImageUrl(payload.url))
          TextButton(
            onPressed: () => context.onMediaAction?.call(
              OpenImageExternallyAction(payload.url),
            ),
            child: const Text('Open externally'),
          ),
      ],
    );
    return Semantics(
      image: true,
      label: payload.altText.trim().isEmpty
          ? context.node.title
          : payload.altText,
      child: Container(
        key: ValueKey('image-content-${preset.name}'),
        color: Theme.of(buildContext).colorScheme.surface,
        padding: const EdgeInsets.all(10),
        child: switch (preset) {
          NodeSizePreset.compact => Column(
            children: [
              Expanded(child: preview),
              warning,
              actions,
            ],
          ),
          NodeSizePreset.standard => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: preview),
              if (payload.caption.isNotEmpty)
                Text(
                  payload.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (payload.tags.isNotEmpty) _imageTags(payload),
              warning,
              actions,
            ],
          ),
          NodeSizePreset.large => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: preview),
              const SizedBox(height: 8),
              Text(
                payload.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                payload.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (payload.tags.isNotEmpty) _imageTags(payload),
              warning,
              actions,
            ],
          ),
          _ => Row(
            children: [
              Expanded(flex: 3, child: preview),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.node.title,
                      style: Theme.of(buildContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(payload.caption),
                    if (payload.tags.isNotEmpty) _imageTags(payload),
                    const Spacer(),
                    Text(payload.fileName),
                    warning,
                    actions,
                  ],
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

Widget _imagePreview({
  required ImagePayload payload,
  required Uint8List? bytes,
  required bool loading,
  required String? error,
  required int cacheSize,
  NodePayloadDraftCallback? onAction,
  bool interactive = true,
  String? selectedAnnotationId,
  ValueChanged<String>? onAnnotationSelected,
  ValueChanged<ImageAnnotation>? onAnnotationChanged,
  ImageAnnotationType? activeAnnotationTool,
  void Function(
    ImageAnnotationType type,
    Offset start,
    Offset end,
    List<Offset> points,
  )?
  onAnnotationDrawn,
  int capturedPointLimit = maxDrawingPointsPerItem,
}) {
  if (loading) return const Center(child: CircularProgressIndicator());
  if (error != null) {
    return Center(child: Text(error, key: const ValueKey('image-load-error')));
  }
  final fit = switch (payload.fitMode) {
    ImageFitMode.contain => BoxFit.contain,
    ImageFitMode.cover => BoxFit.cover,
    ImageFitMode.fill => BoxFit.fill,
    ImageFitMode.fitWidth => BoxFit.fitWidth,
    ImageFitMode.fitHeight => BoxFit.fitHeight,
  };
  Widget image;
  if (bytes != null) {
    image = Image.memory(
      bytes,
      key: const ValueKey('image-local-preview'),
      fit: fit,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  } else if (isValidExternalImageUrl(payload.url)) {
    image = _RetryableNetworkImage(
      url: payload.url,
      fit: fit,
      cacheSize: cacheSize,
      onAction: onAction,
    );
  } else {
    return const Center(child: Icon(Icons.image_outlined, size: 40));
  }
  image = ColorFiltered(
    colorFilter: ColorFilter.matrix(_imageColorMatrix(payload)),
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(
        payload.flipHorizontal ? -1 : 1,
        payload.flipVertical ? -1 : 1,
        1,
      ),
      child: RotatedBox(
        quarterTurns: payload.rotationQuarterTurns,
        child: image,
      ),
    ),
  );
  final result = LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        image,
        for (final annotation in payload.annotations)
          _ImageAnnotationOverlay(
            annotation: annotation,
            canvasSize: constraints.biggest,
            selected: annotation.id == selectedAnnotationId,
            onSelected: onAnnotationSelected,
            onChanged: onAnnotationChanged,
          ),
        if (activeAnnotationTool != null && onAnnotationDrawn != null)
          _ImageAnnotationDrawingSurface(
            tool: activeAnnotationTool,
            canvasSize: constraints.biggest,
            pointLimit: math.min(maxDrawingPointsPerItem, capturedPointLimit),
            onDrawn: onAnnotationDrawn,
          ),
      ],
    ),
  );
  if (!interactive || onAnnotationChanged != null) return result;
  return Builder(
    builder: (context) => GestureDetector(
      key: const ValueKey('image-open-lightbox'),
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 8,
                child: SizedBox(
                  width: 1000,
                  height: 700,
                  child: _imagePreview(
                    payload: payload,
                    bytes: bytes,
                    loading: loading,
                    error: error,
                    cacheSize: 1600,
                    onAction: onAction,
                    interactive: false,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
      child: result,
    ),
  );
}

Widget _imageTags(ImagePayload payload) => Wrap(
  spacing: 4,
  runSpacing: 4,
  children: [
    for (final tag in payload.tags.take(3))
      Chip(visualDensity: VisualDensity.compact, label: Text(tag)),
  ],
);

List<double> _imageColorMatrix(ImagePayload payload) {
  final preset = switch (payload.filter) {
    ImageFilterPreset.none => (0.0, 0.0, 0.0),
    ImageFilterPreset.vivid => (0.0, 0.15, 0.35),
    ImageFilterPreset.mono => (0.0, 0.1, -1.0),
    ImageFilterPreset.warm => (0.08, 0.05, 0.1),
    ImageFilterPreset.cool => (-0.05, 0.05, 0.05),
  };
  final brightness = (payload.brightness + preset.$1) * 255;
  final contrast = 1 + payload.contrast + preset.$2;
  final saturation = (1 + payload.saturation + preset.$3).clamp(0, 2);
  final inverseSaturation = 1 - saturation;
  final red = 0.2126 * inverseSaturation;
  final green = 0.7152 * inverseSaturation;
  final blue = 0.0722 * inverseSaturation;
  return <double>[
    contrast * (red + saturation),
    contrast * green,
    contrast * blue,
    0,
    brightness,
    contrast * red,
    contrast * (green + saturation),
    contrast * blue,
    0,
    brightness,
    contrast * red,
    contrast * green,
    contrast * (blue + saturation),
    0,
    brightness,
    0,
    0,
    0,
    1,
    0,
  ];
}

final class _ImageAnnotationPreview extends StatefulWidget {
  const _ImageAnnotationPreview({required this.annotation, this.onChanged});

  final ImageAnnotation annotation;
  final ValueChanged<ImageAnnotation>? onChanged;

  @override
  State<_ImageAnnotationPreview> createState() =>
      _ImageAnnotationPreviewState();
}

final class _ImageAnnotationPreviewState
    extends State<_ImageAnnotationPreview> {
  late final TextEditingController _textController = TextEditingController(
    text: widget.annotation.text,
  );
  late final FocusNode _textFocusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _ImageAnnotationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_textFocusNode.hasFocus &&
        _textController.text != widget.annotation.text) {
      _textController.text = widget.annotation.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final annotation = widget.annotation;
    final color = Color(annotation.color);
    return switch (annotation.type) {
      ImageAnnotationType.text when widget.onChanged != null => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: Colors.black54,
        child: TextField(
          key: ValueKey('image-annotation-inline-text-${annotation.id}'),
          controller: _textController,
          focusNode: _textFocusNode,
          autofocus: annotation.text.isEmpty,
          maxLines: 3,
          minLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: 'Type text',
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (value) =>
              widget.onChanged?.call(annotation.copyWith(text: value)),
        ),
      ),
      ImageAnnotationType.text => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: Colors.black54,
        child: Text(
          annotation.text.isEmpty ? 'Text' : annotation.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
      ImageAnnotationType.arrow => CustomPaint(
        painter: _ImageArrowAnnotationPainter(
          points: annotation.points,
          color: color,
          strokeWidth: annotation.strokeWidth,
        ),
      ),
      ImageAnnotationType.rectangle => Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: annotation.strokeWidth),
        ),
      ),
      ImageAnnotationType.freehand => CustomPaint(
        painter: _ImageFreehandAnnotationPainter(
          points: annotation.points,
          color: color,
          strokeWidth: annotation.strokeWidth,
        ),
      ),
    };
  }
}

final class _ImageAnnotationDrawingSurface extends StatefulWidget {
  const _ImageAnnotationDrawingSurface({
    required this.tool,
    required this.canvasSize,
    required this.pointLimit,
    required this.onDrawn,
  });

  final ImageAnnotationType tool;
  final Size canvasSize;
  final int pointLimit;
  final void Function(
    ImageAnnotationType type,
    Offset start,
    Offset end,
    List<Offset> points,
  )
  onDrawn;

  @override
  State<_ImageAnnotationDrawingSurface> createState() =>
      _ImageAnnotationDrawingSurfaceState();
}

final class _ImageAnnotationDrawingSurfaceState
    extends State<_ImageAnnotationDrawingSurface> {
  final List<Offset> _points = <Offset>[];

  Offset _normalized(Offset localPosition) => Offset(
    (localPosition.dx / widget.canvasSize.width).clamp(0.0, 1.0),
    (localPosition.dy / widget.canvasSize.height).clamp(0.0, 1.0),
  );

  void _start(DragStartDetails details) => setState(() {
    _points.clear();
    if (widget.pointLimit > 0) {
      _points.add(_normalized(details.localPosition));
    }
  });

  void _update(DragUpdateDetails details) => setState(() {
    if (_points.length < widget.pointLimit) {
      _points.add(_normalized(details.localPosition));
    }
  });

  void _finish(DragEndDetails details) {
    if (_points.isEmpty) return;
    final start = _points.first;
    final end = _points.last;
    final points = List<Offset>.of(_points);
    setState(_points.clear);
    widget.onDrawn(widget.tool, start, end, points);
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        key: ValueKey('image-annotation-draw-${widget.tool.name}'),
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.tool == ImageAnnotationType.text
            ? (details) {
                final point = _normalized(details.localPosition);
                widget.onDrawn(widget.tool, point, point, <Offset>[point]);
              }
            : null,
        onPanStart: widget.tool == ImageAnnotationType.text ? null : _start,
        onPanUpdate: widget.tool == ImageAnnotationType.text ? null : _update,
        onPanEnd: widget.tool == ImageAnnotationType.text ? null : _finish,
        onPanCancel: () => setState(_points.clear),
        child: CustomPaint(
          painter: _ImageAnnotationDraftPainter(
            tool: widget.tool,
            points: _points,
            color: const Color(0xFFFF3BCE),
          ),
        ),
      ),
    ),
  );
}

final class _ImageAnnotationDraftPainter extends CustomPainter {
  const _ImageAnnotationDraftPainter({
    required this.tool,
    required this.points,
    required this.color,
  });

  final ImageAnnotationType tool;
  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final scaled = <Offset>[
      for (final point in points)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (tool) {
      case ImageAnnotationType.freehand:
        final path = Path()..moveTo(scaled.first.dx, scaled.first.dy);
        for (final point in scaled.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      case ImageAnnotationType.arrow:
        _drawImageArrow(canvas, scaled.first, scaled.last, paint);
      case ImageAnnotationType.rectangle:
        canvas.drawRect(Rect.fromPoints(scaled.first, scaled.last), paint);
      case ImageAnnotationType.text:
        final position = scaled.first;
        final textPainter = TextPainter(
          text: TextSpan(
            text: 'T',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, position);
    }
  }

  @override
  bool shouldRepaint(covariant _ImageAnnotationDraftPainter oldDelegate) =>
      oldDelegate.tool != tool ||
      oldDelegate.color != color ||
      oldDelegate.points != points;
}

final class _ImageArrowAnnotationPainter extends CustomPainter {
  const _ImageArrowAnnotationPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<CanvasPoint> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final start = points.isEmpty
        ? Offset(0, size.height / 2)
        : Offset(points.first.x * size.width, points.first.y * size.height);
    final end = points.isEmpty
        ? Offset(size.width, size.height / 2)
        : Offset(points.last.x * size.width, points.last.y * size.height);
    _drawImageArrow(canvas, start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageArrowAnnotationPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

void _drawImageArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
  final direction = end - start;
  final length = direction.distance;
  if (length == 0) return;
  final unit = direction / length;
  final normal = Offset(-unit.dy, unit.dx);
  final headLength = math.min(14.0, math.max(6.0, length * 0.28));
  final headBase = end - unit * headLength;
  canvas
    ..drawLine(start, end, paint)
    ..drawLine(end, headBase + normal * headLength * 0.55, paint)
    ..drawLine(end, headBase - normal * headLength * 0.55, paint);
}

final class _ImageAnnotationOverlay extends StatefulWidget {
  const _ImageAnnotationOverlay({
    required this.annotation,
    required this.canvasSize,
    required this.selected,
    this.onSelected,
    this.onChanged,
  });

  final ImageAnnotation annotation;
  final Size canvasSize;
  final bool selected;
  final ValueChanged<String>? onSelected;
  final ValueChanged<ImageAnnotation>? onChanged;

  @override
  State<_ImageAnnotationOverlay> createState() =>
      _ImageAnnotationOverlayState();
}

final class _ImageAnnotationOverlayState
    extends State<_ImageAnnotationOverlay> {
  ImageAnnotation? _preview;

  ImageAnnotation get _annotation => _preview ?? widget.annotation;

  void _updatePreview(ImageAnnotation value) =>
      setState(() => _preview = value);

  void _commitPreview() {
    final value = _preview;
    if (value == null) return;
    _preview = null;
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final annotation = _annotation;
    final canvasSize = widget.canvasSize;
    final selected = widget.selected;
    final onChanged = widget.onChanged;
    final onSelected = widget.onSelected;
    final width = math.max(28.0, annotation.width * canvasSize.width);
    final height = math.max(24.0, annotation.height * canvasSize.height);
    final maxX = math.max(0.0, 1 - width / canvasSize.width);
    final maxY = math.max(0.0, 1 - height / canvasSize.height);
    final left = annotation.positionX.clamp(0, maxX) * canvasSize.width;
    final top = annotation.positionY.clamp(0, maxY) * canvasSize.height;
    final editable = onChanged != null;
    final content = Transform.rotate(
      angle: annotation.rotationDegrees * math.pi / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(selected ? 2 : 0),
          child: _ImageAnnotationPreview(
            annotation: annotation,
            onChanged: selected ? onChanged : null,
          ),
        ),
      ),
    );
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: editable ? SystemMouseCursors.move : MouseCursor.defer,
              child: GestureDetector(
                key: ValueKey('image-annotation-overlay-${annotation.id}'),
                behavior: HitTestBehavior.translucent,
                onTap: editable ? () => onSelected?.call(annotation.id) : null,
                onPanStart:
                    editable && annotation.type != ImageAnnotationType.text
                    ? (_) => onSelected?.call(annotation.id)
                    : null,
                onPanUpdate:
                    editable && annotation.type != ImageAnnotationType.text
                    ? (details) {
                        final nextX =
                            (annotation.positionX +
                                    details.delta.dx / canvasSize.width)
                                .clamp(0, maxX)
                                .toDouble();
                        final nextY =
                            (annotation.positionY +
                                    details.delta.dy / canvasSize.height)
                                .clamp(0, maxY)
                                .toDouble();
                        _updatePreview(
                          annotation.copyWith(
                            positionX: nextX,
                            positionY: nextY,
                          ),
                        );
                      }
                    : null,
                onPanEnd:
                    editable && annotation.type != ImageAnnotationType.text
                    ? (_) => _commitPreview()
                    : null,
                onPanCancel: editable ? _commitPreview : null,

                child: content,
              ),
            ),
          ),
          if (selected && editable)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                key: ValueKey('image-annotation-resize-${annotation.id}'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  final nextWidth =
                      (annotation.width + details.delta.dx / canvasSize.width)
                          .clamp(0.05, math.max(0.05, 1 - annotation.positionX))
                          .toDouble();
                  final nextHeight =
                      (annotation.height + details.delta.dy / canvasSize.height)
                          .clamp(0.05, math.max(0.05, 1 - annotation.positionY))
                          .toDouble();
                  _updatePreview(
                    annotation.copyWith(width: nextWidth, height: nextHeight),
                  );
                },
                onPanEnd: (_) => _commitPreview(),
                onPanCancel: _commitPreview,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    border: Border.all(color: Colors.white, width: 1.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _ImageFreehandAnnotationPainter extends CustomPainter {
  const _ImageFreehandAnnotationPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<CanvasPoint> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final path = Path()
      ..moveTo(points.first.x * size.width, points.first.y * size.height);
    for (final point in points.skip(1)) {
      path.lineTo(point.x * size.width, point.y * size.height);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (points.length == 1) {
      canvas.drawCircle(
        Offset(points.first.x * size.width, points.first.y * size.height),
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageFreehandAnnotationPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

final class _RetryableNetworkImage extends StatefulWidget {
  const _RetryableNetworkImage({
    required this.url,
    required this.fit,
    required this.cacheSize,
    this.onAction,
  });
  final String url;
  final BoxFit fit;
  final int cacheSize;
  final NodePayloadDraftCallback? onAction;

  @override
  State<_RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

final class _RetryableNetworkImageState extends State<_RetryableNetworkImage> {
  int _revision = 0;

  @override
  void didUpdateWidget(covariant _RetryableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _revision = 0;
  }

  @override
  Widget build(BuildContext context) => Image.network(
    widget.url,
    key: ValueKey('image-network-preview-${widget.url}-$_revision'),
    fit: widget.fit,
    cacheWidth: widget.cacheSize,
    cacheHeight: widget.cacheSize,
    loadingBuilder: (_, child, progress) => progress == null
        ? child
        : const Center(child: CircularProgressIndicator()),
    errorBuilder: (_, _, _) => Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined),
          TextButton(
            key: const ValueKey('image-network-retry'),
            onPressed: () {
              setState(() => _revision++);
              widget.onAction?.call(const RetryImageAction());
            },
            child: const Text('Retry'),
          ),
          if (isValidExternalImageUrl(widget.url))
            TextButton(
              key: const ValueKey('image-network-open'),
              onPressed: () =>
                  widget.onAction?.call(OpenImageExternallyAction(widget.url)),
              child: const Text('Open externally'),
            ),
        ],
      ),
    ),
  );
}

final class _ImageEditor extends StatefulWidget {
  const _ImageEditor(this.context);
  final NodeEditContext context;
  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

final class _ImageEditorState extends State<_ImageEditor> {
  static const int _historyLimit = 50;
  static const int _historyByteLimit = maxDrawingSerializedPayloadBytes;

  late ImagePayload _draft = widget.context.typedDraft is ImagePayload
      ? widget.context.typedDraft as ImagePayload
      : ImagePayload.fromNode(widget.context.node);
  int _fieldRevision = 0;
  final TextEditingController _tagController = TextEditingController();
  final List<ImagePayload> _undo = <ImagePayload>[];
  final List<ImagePayload> _redo = <ImagePayload>[];
  final GlobalKey _previewKey = GlobalKey();
  String? _selectedAnnotationId;
  ImageAnnotationType? _activeAnnotationTool;
  bool _saving = false;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ImageEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextDraft = widget.context.typedDraft is ImagePayload
        ? widget.context.typedDraft as ImagePayload
        : ImagePayload.fromNode(widget.context.node);
    if (oldWidget.context.node.id != widget.context.node.id) {
      _draft = nextDraft;
      _tagController.clear();
      _undo.clear();
      _redo.clear();
      _selectedAnnotationId = null;
      _activeAnnotationTool = null;
      _fieldRevision++;
    } else if (!_sameImageDraft(_draft, nextDraft)) {
      _draft = nextDraft;
      if (_annotationById(_selectedAnnotationId) == null) {
        _selectedAnnotationId = null;
      }
      _fieldRevision++;
    }
  }

  bool _sameImageDraft(ImagePayload left, ImagePayload right) {
    if (identical(left, right)) return true;
    return jsonEncode(left.toData()) == jsonEncode(right.toData());
  }

  void _emit(ImagePayload value, {bool recordHistory = true}) {
    if (recordHistory) {
      _undo.add(_draft);
      _redo.clear();
      _trimHistory();
    }
    setState(() {
      _draft = value;
      if (_annotationById(_selectedAnnotationId) == null) {
        _selectedAnnotationId = null;
      }
    });
    widget.context.onDraftChanged(value);
  }

  ImageAnnotation? _annotationById(String? id) {
    if (id == null) return null;
    for (final annotation in _draft.annotations) {
      if (annotation.id == id) return annotation;
    }
    return null;
  }

  void _selectAnnotation(String id) => setState(() {
    _activeAnnotationTool = null;
    _selectedAnnotationId = id;
  });

  void _replaceAnnotation(ImageAnnotation value, {bool recordHistory = false}) {
    _emit(
      _draft.copyWith(
        annotations: <ImageAnnotation>[
          for (final annotation in _draft.annotations)
            if (annotation.id == value.id) value else annotation,
        ],
      ),
      recordHistory: recordHistory,
    );
  }

  void _removeAnnotation(String id) {
    _emit(
      _draft.copyWith(
        annotations: _draft.annotations
            .where((annotation) => annotation.id != id)
            .toList(growable: false),
      ),
    );
  }

  void _duplicateAnnotation(ImageAnnotation annotation) {
    final copy = annotation.copyWith(
      positionX: (annotation.positionX + 0.04).clamp(
        0,
        math.max(0, 1 - annotation.width),
      ),
      positionY: (annotation.positionY + 0.04).clamp(
        0,
        math.max(0, 1 - annotation.height),
      ),
    );
    final duplicated = ImageAnnotation(
      id: 'annotation-${DateTime.now().microsecondsSinceEpoch}',
      type: copy.type,
      text: copy.text,
      color: copy.color,
      strokeWidth: copy.strokeWidth,
      positionX: copy.positionX,
      positionY: copy.positionY,
      width: copy.width,
      height: copy.height,
      rotationDegrees: copy.rotationDegrees,
      points: copy.points,
    );
    _selectedAnnotationId = duplicated.id;
    _emit(
      _draft.copyWith(
        annotations: <ImageAnnotation>[..._draft.annotations, duplicated],
      ),
    );
  }

  int _payloadBytes(ImagePayload payload) =>
      utf8.encode(jsonEncode(payload.toData())).length;

  void _trimHistory() {
    while (_undo.length + _redo.length > _historyLimit) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
    var bytes = <ImagePayload>[
      ..._undo,
      ..._redo,
    ].fold<int>(0, (total, payload) => total + _payloadBytes(payload));
    while (bytes > _historyByteLimit && _undo.length + _redo.length > 1) {
      final removed = _undo.isNotEmpty ? _undo.removeAt(0) : _redo.removeAt(0);
      bytes -= _payloadBytes(removed);
    }
  }

  void _undoEdit() {
    if (_undo.isEmpty) return;
    _redo.add(_draft);
    final previous = _undo.removeLast();
    _trimHistory();
    _emit(previous, recordHistory: false);
  }

  void _redoEdit() {
    if (_redo.isEmpty) return;
    _undo.add(_draft);
    final next = _redo.removeLast();
    _trimHistory();
    _emit(next, recordHistory: false);
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty || _draft.tags.contains(tag)) return;
    _emit(_draft.copyWith(tags: <String>[..._draft.tags, tag]));
    _tagController.clear();
  }

  void _activateAnnotationTool(ImageAnnotationType type) {
    setState(() {
      _activeAnnotationTool = type;
      _selectedAnnotationId = null;
    });
  }

  void _addAnnotationAt(
    ImageAnnotationType type,
    Offset start,
    Offset end,
    List<Offset> points,
  ) {
    final id = 'annotation-${DateTime.now().microsecondsSinceEpoch}';
    final minX = type == ImageAnnotationType.text
        ? (start.dx - 0.14).clamp(0.0, 0.72)
        : math.min(start.dx, end.dx).clamp(0.0, 0.95);
    final minY = type == ImageAnnotationType.text
        ? (start.dy - 0.06).clamp(0.0, 0.88)
        : math.min(start.dy, end.dy).clamp(0.0, 0.95);
    final width = type == ImageAnnotationType.text
        ? 0.28
        : math.max(0.05, (start.dx - end.dx).abs()).clamp(0.05, 1 - minX);
    final height = type == ImageAnnotationType.text
        ? 0.12
        : math.max(0.05, (start.dy - end.dy).abs()).clamp(0.05, 1 - minY);
    final normalizedPoints =
        type == ImageAnnotationType.freehand ||
            type == ImageAnnotationType.arrow
        ? <CanvasPoint>[
            for (final point in points)
              CanvasPoint(
                ((point.dx - minX) / width).clamp(0.0, 1.0),
                ((point.dy - minY) / height).clamp(0.0, 1.0),
              ),
          ]
        : const <CanvasPoint>[];
    final annotation = ImageAnnotation(
      id: id,
      type: type,
      positionX: minX,
      positionY: minY,
      width: width,
      height: height,
      points: normalizedPoints,
    );
    _selectedAnnotationId = id;
    _activeAnnotationTool = null;
    _emit(
      _draft.copyWith(
        annotations: <ImageAnnotation>[..._draft.annotations, annotation],
      ),
    );
  }

  Future<void> _saveAsNewImage() async {
    final callback = widget.context.onMediaAction;
    if (callback == null) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _previewKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Edited image preview is unavailable.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Edited image could not be encoded.');
      final action = SaveEditedImageAction(
        bytes: data.buffer.asUint8List(),
        existing: _draft,
      );
      await callback(action);
      final result = await action.result.future;
      if (result != null && mounted) _emit(result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreOriginalImage() async {
    final callback = widget.context.onMediaAction;
    if (callback == null || _draft.originalAttachmentId.isEmpty) return;
    final action = RestoreOriginalImageAction(_draft);
    await callback(action);
    final result = await action.result.future;
    if (result != null && mounted) _emit(result);
  }

  @override
  Widget build(BuildContext context) {
    final selectedAnnotation = _annotationById(_selectedAnnotationId);
    final fields = <Widget>[
      TextFormField(
        key: ValueKey('image-url-${widget.context.node.id}-$_fieldRevision'),
        initialValue: _draft.url,
        decoration: _imageFieldDecoration(context, label: 'Image URL'),
        keyboardType: TextInputType.url,
        onChanged: (value) {
          final replacesLocalAttachment =
              value.trim().isNotEmpty && _draft.hasLocalAttachment;
          _emit(
            _draft.copyWith(
              url: value,
              clearAttachment: value.trim().isNotEmpty,
              clearMediaMetadata: replacesLocalAttachment,
            ),
          );
        },
      ),
      TextFormField(
        key: ValueKey(
          'image-caption-${widget.context.node.id}-$_fieldRevision',
        ),
        initialValue: _draft.caption,
        decoration: _imageFieldDecoration(context, label: 'Caption'),
        onChanged: (value) => _emit(_draft.copyWith(caption: value)),
      ),
      TextFormField(
        key: ValueKey('image-alt-${widget.context.node.id}-$_fieldRevision'),
        initialValue: _draft.altText,
        decoration: _imageFieldDecoration(
          context,
          label: 'Alt text',
          errorText: _draft.altText.trim().isEmpty
              ? 'Required for accessibility'
              : null,
        ),
        onChanged: (value) => _emit(_draft.copyWith(altText: value)),
      ),
      TextFormField(
        key: ValueKey(
          'image-source-url-${widget.context.node.id}-$_fieldRevision',
        ),
        initialValue: _draft.sourceUrl,
        decoration: _imageFieldDecoration(
          context,
          label: 'Source URL',
          hintText: 'https://source.example/image',
        ),
        keyboardType: TextInputType.url,
        onChanged: (value) => _emit(_draft.copyWith(sourceUrl: value)),
      ),
      TextFormField(
        key: const ValueKey('image-tag-input'),
        controller: _tagController,
        decoration: _imageFieldDecoration(
          context,
          label: 'Add tag',
          suffixIcon: IconButton(
            tooltip: 'Add tag',
            onPressed: () => _addTag(_tagController.text),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: _addTag,
      ),
      Wrap(
        spacing: 6,
        children: [
          for (final tag in _draft.tags)
            InputChip(
              label: Text(tag),
              onDeleted: () => _emit(
                _draft.copyWith(
                  tags: _draft.tags.where((item) => item != tag).toList(),
                ),
              ),
            ),
        ],
      ),
      DropdownButtonFormField<ImageFitMode>(
        key: const ValueKey('image-fit-mode'),
        initialValue: _draft.fitMode,
        decoration: _imageFieldDecoration(context, label: 'Image fit'),
        items: [
          for (final mode in ImageFitMode.values)
            DropdownMenuItem(value: mode, child: Text(mode.name)),
        ],
        onChanged: (value) {
          if (value != null) _emit(_draft.copyWith(fitMode: value));
        },
      ),
      Wrap(
        spacing: 6,
        children: [
          IconButton(
            tooltip: 'Rotate left',
            onPressed: () => _emit(
              _draft.copyWith(
                rotationQuarterTurns: (_draft.rotationQuarterTurns + 3) % 4,
              ),
            ),
            icon: const Icon(Icons.rotate_left),
          ),
          IconButton(
            tooltip: 'Rotate right',
            onPressed: () => _emit(
              _draft.copyWith(
                rotationQuarterTurns: (_draft.rotationQuarterTurns + 1) % 4,
              ),
            ),
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            tooltip: 'Flip horizontal',
            onPressed: () =>
                _emit(_draft.copyWith(flipHorizontal: !_draft.flipHorizontal)),
            icon: const Icon(Icons.flip),
          ),
          IconButton(
            tooltip: 'Flip vertical',
            onPressed: () =>
                _emit(_draft.copyWith(flipVertical: !_draft.flipVertical)),
            icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
          ),
          IconButton(
            onPressed: _undo.isEmpty ? null : _undoEdit,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: _redo.isEmpty ? null : _redoEdit,
            icon: const Icon(Icons.redo),
          ),
        ],
      ),
      DropdownButtonFormField<ImageFilterPreset>(
        key: const ValueKey('image-filter'),
        initialValue: _draft.filter,
        decoration: _imageFieldDecoration(context, label: 'Filter'),
        items: [
          for (final filter in ImageFilterPreset.values)
            DropdownMenuItem(value: filter, child: Text(filter.name)),
        ],
        onChanged: (value) {
          if (value != null) _emit(_draft.copyWith(filter: value));
        },
      ),
      _ImageAdjustmentSlider(
        label: 'Brightness',
        value: _draft.brightness,
        onChanged: (value) => _emit(_draft.copyWith(brightness: value)),
      ),
      _ImageAdjustmentSlider(
        label: 'Contrast',
        value: _draft.contrast,
        onChanged: (value) => _emit(_draft.copyWith(contrast: value)),
      ),
      _ImageAdjustmentSlider(
        label: 'Saturation',
        value: _draft.saturation,
        onChanged: (value) => _emit(_draft.copyWith(saturation: value)),
      ),
      Text('Annotations', style: Theme.of(context).textTheme.titleSmall),
      Wrap(
        spacing: 6,
        children: [
          for (final type in ImageAnnotationType.values)
            OutlinedButton.icon(
              key: ValueKey('image-annotation-add-${type.name}'),
              style: _activeAnnotationTool == type
                  ? OutlinedButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    )
                  : null,
              onPressed: () => _activateAnnotationTool(type),
              icon: Icon(_imageAnnotationIcon(type), size: 16),
              label: Text(_imageAnnotationLabel(type)),
            ),
        ],
      ),
      if (_activeAnnotationTool != null)
        Text(
          _activeAnnotationTool == ImageAnnotationType.text
              ? 'Click preview to place text, then type inside it.'
              : 'Drag on preview to draw ${_imageAnnotationLabel(_activeAnnotationTool!).toLowerCase()}.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      for (final annotation in _draft.annotations)
        Card(
          margin: const EdgeInsets.only(top: 6),
          child: ListTile(
            key: ValueKey('image-annotation-item-${annotation.id}'),
            dense: true,
            selected: annotation.id == _selectedAnnotationId,
            leading: Icon(_imageAnnotationIcon(annotation.type), size: 18),
            title: Text(
              annotation.text.isEmpty
                  ? _imageAnnotationLabel(annotation.type)
                  : annotation.text,
            ),
            subtitle: Text(
              '${(annotation.positionX * 100).round()}%, '
              '${(annotation.positionY * 100).round()}% · '
              '${(annotation.width * 100).round()}×'
              '${(annotation.height * 100).round()}%',
            ),
            onTap: () => _selectAnnotation(annotation.id),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Duplicate annotation',
                  onPressed: () => _duplicateAnnotation(annotation),
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: 'Delete annotation',
                  onPressed: () => _removeAnnotation(annotation.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ),
      if (selectedAnnotation != null)
        _ImageAnnotationProperties(
          annotation: selectedAnnotation,
          onChanged: (value) => _replaceAnnotation(value, recordHistory: true),
          onDelete: () => _removeAnnotation(selectedAnnotation.id),
          onDuplicate: () => _duplicateAnnotation(selectedAnnotation),
        ),
    ];
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: widget.context.onMediaAction == null
              ? null
              : () async =>
                    widget.context.onMediaAction!(const ReplaceImageAction()),
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Replace'),
        ),
        if (_draft.hasLocalAttachment)
          OutlinedButton.icon(
            onPressed: widget.context.onMediaAction == null
                ? null
                : () async => widget.context.onMediaAction!(
                    ExportImageAction(_draft.attachmentId),
                  ),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export'),
          ),
        if (_draft.hasLocalAttachment)
          FilledButton.icon(
            key: const ValueKey('image-save-as-new'),
            onPressed: _saving ? null : _saveAsNewImage,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: const Text('Save as new image'),
          ),
        if (_draft.originalAttachmentId.isNotEmpty &&
            _draft.originalAttachmentId != _draft.attachmentId)
          OutlinedButton.icon(
            onPressed: widget.context.onMediaAction == null
                ? null
                : _restoreOriginalImage,
            icon: const Icon(Icons.restore),
            label: const Text('Restore original'),
          ),
        if (_draft.hasLocalAttachment || _draft.hasRemoteUrl)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.65),
              ),
            ),
            onPressed: () => _emit(
              _draft.copyWith(
                clearAttachment: true,
                clearUrl: true,
                clearMediaMetadata: true,
                rotationQuarterTurns: 0,
                flipHorizontal: false,
                flipVertical: false,
                brightness: 0,
                contrast: 0,
                saturation: 0,
                filter: ImageFilterPreset.none,
                annotations: const <ImageAnnotation>[],
              ),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove from node'),
          ),
        if (widget.context.attachmentError != null)
          OutlinedButton(
            onPressed: widget.context.onMediaAction == null
                ? null
                : () async =>
                      widget.context.onMediaAction!(const RetryImageAction()),
            child: const Text('Retry'),
          ),
        if (isValidExternalImageUrl(_draft.url))
          OutlinedButton(
            onPressed: widget.context.onMediaAction == null
                ? null
                : () async => widget.context.onMediaAction!(
                    OpenImageExternallyAction(_draft.url),
                  ),
            child: const Text('Open externally'),
          ),
      ],
    );
    final sourceSection = _ImageInspectorSection(
      sectionKey: const ValueKey('image-inspector-source'),
      icon: Icons.link_rounded,
      title: 'Source',
      children: [fields[0], fields[3], fields[4], fields[5]],
    );
    final detailsSection = _ImageInspectorSection(
      sectionKey: const ValueKey('image-inspector-details'),
      icon: Icons.notes_rounded,
      title: 'Details',
      children: [fields[1], fields[2]],
    );
    final adjustmentsSection = _ImageInspectorSection(
      sectionKey: const ValueKey('image-inspector-adjustments'),
      icon: Icons.tune_rounded,
      title: 'Adjustments',
      children: fields.sublist(8, 12),
    );
    final annotationsSection = _ImageInspectorSection(
      sectionKey: const ValueKey('image-inspector-annotations'),
      icon: Icons.draw_outlined,
      title: 'Annotations',
      children: [
        ...fields.skip(13),
        if (_draft.annotations.isEmpty)
          Text(
            'Choose a tool to add an annotation.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    final sections = [
      sourceSection,
      detailsSection,
      adjustmentsSection,
      annotationsSection,
    ];
    final previewPanel = _ImagePreviewPanel(
      payload: _draft,
      preview: RepaintBoundary(
        key: _previewKey,
        child: _imagePreview(
          payload: _draft,
          bytes: widget.context.attachmentBytes,
          loading: widget.context.attachmentLoading,
          error: widget.context.attachmentError,
          cacheSize: 900,
          onAction: widget.context.onMediaAction,
          selectedAnnotationId: _selectedAnnotationId,
          onAnnotationSelected: _selectAnnotation,
          onAnnotationChanged: _replaceAnnotation,
          activeAnnotationTool: _activeAnnotationTool,
          onAnnotationDrawn: _addAnnotationAt,
          capturedPointLimit: math.max(
            0,
            maxDrawingPointsTotal -
                _draft.annotations.fold<int>(
                  0,
                  (total, annotation) => total + annotation.points.length,
                ),
          ),
        ),
      ),
      fitControl: fields[6],
      transformToolbar: fields[7],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns =
            constraints.maxWidth >= 720 && constraints.maxHeight >= 520;
        return Container(
          key: ValueKey('image-editor-${widget.context.effectivePreset.name}'),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: useTwoColumns
                    ? Row(
                        key: const ValueKey('image-editor-two-column'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 42, child: previewPanel),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 58,
                            child: SingleChildScrollView(
                              key: const ValueKey('image-editor-fields'),
                              padding: EdgeInsets.zero,
                              child: Column(children: sections),
                            ),
                          ),
                        ],
                      )
                    : KeyedSubtree(
                        key: const ValueKey('image-editor-stacked'),
                        child: SingleChildScrollView(
                          key: const ValueKey('image-editor-fields'),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              SizedBox(height: 360, child: previewPanel),
                              const SizedBox(height: 12),
                              ...sections,
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              _ImageEditorFooter(child: actions),
            ],
          ),
        );
      },
    );
  }
}

final class _ImagePreviewPanel extends StatelessWidget {
  const _ImagePreviewPanel({
    required this.payload,
    required this.preview,
    required this.fitControl,
    required this.transformToolbar,
  });

  final ImagePayload payload;
  final Widget preview;
  final Widget fitControl;
  final Widget transformToolbar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey('image-preview-panel'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: colors.surfaceContainerLowest,
                  child: preview,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _ImageSourceStatus(payload: payload),
            const SizedBox(height: 10),
            fitControl,
            const SizedBox(height: 8),
            transformToolbar,
          ],
        ),
      ),
    );
  }
}

final class _ImageSourceStatus extends StatelessWidget {
  const _ImageSourceStatus({required this.payload});

  final ImagePayload payload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLocal = payload.hasLocalAttachment;
    final label = isLocal
        ? (payload.fileName.trim().isEmpty
              ? 'Local attachment'
              : payload.fileName)
        : payload.hasRemoteUrl
        ? (Uri.tryParse(payload.url)?.host ?? 'Remote image')
        : 'No image selected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isLocal ? Icons.attach_file_rounded : Icons.public_rounded,
            size: 16,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ImageInspectorSection extends StatelessWidget {
  const _ImageInspectorSection({
    required this.sectionKey,
    required this.icon,
    required this.title,
    required this.children,
  });

  final Key sectionKey;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        key: sectionKey,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: colors.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                children[index],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const List<int> _imageAnnotationColors = <int>[
  0xFFFF3BCE,
  0xFF40C4FF,
  0xFF69F0AE,
  0xFFFFD740,
  0xFFFF5252,
  0xFFFFFFFF,
  0xFF111111,
];

final class _ImageAnnotationProperties extends StatelessWidget {
  const _ImageAnnotationProperties({
    required this.annotation,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
  });

  final ImageAnnotation annotation;
  final ValueChanged<ImageAnnotation> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('image-annotation-properties-${annotation.id}'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(color: colors.primary.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_imageAnnotationIcon(annotation.type), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Selected annotation',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Duplicate annotation',
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Delete annotation',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ImageAnnotationType>(
            key: ValueKey('image-annotation-type-${annotation.id}'),
            initialValue: annotation.type,
            decoration: _imageFieldDecoration(context, label: 'Type'),
            items: [
              for (final type in ImageAnnotationType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(_imageAnnotationLabel(type)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              onChanged(
                annotation.copyWith(
                  type: value,
                  text:
                      value == ImageAnnotationType.text &&
                          annotation.text.isEmpty
                      ? 'Text'
                      : annotation.text,
                ),
              );
            },
          ),
          if (annotation.type == ImageAnnotationType.text) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('image-annotation-text-${annotation.id}'),
              initialValue: annotation.text,
              decoration: _imageFieldDecoration(
                context,
                label: 'Annotation text',
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: (value) => onChanged(annotation.copyWith(text: value)),
            ),
          ],
          const SizedBox(height: 12),
          Text('Color', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _imageAnnotationColors)
                ChoiceChip(
                  key: ValueKey(
                    'image-annotation-color-'
                    '${value.toRadixString(16).padLeft(8, '0')}',
                  ),
                  selected: annotation.color == value,
                  showCheckmark: annotation.color == value,
                  label: SizedBox.square(
                    dimension: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(value),
                        border: Border.all(color: colors.outlineVariant),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  onSelected: (_) =>
                      onChanged(annotation.copyWith(color: value)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-stroke'),
            label: 'Stroke',
            value: annotation.strokeWidth,
            min: 1,
            max: 24,
            displayValue: annotation.strokeWidth.toStringAsFixed(1),
            onChanged: (value) =>
                onChanged(annotation.copyWith(strokeWidth: value)),
          ),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-position-x'),
            label: 'Position X',
            value: annotation.positionX,
            min: 0,
            max: math.max(0.01, 1 - annotation.width),
            displayValue: '${(annotation.positionX * 100).round()}%',
            onChanged: (value) =>
                onChanged(annotation.copyWith(positionX: value)),
          ),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-position-y'),
            label: 'Position Y',
            value: annotation.positionY,
            min: 0,
            max: math.max(0.01, 1 - annotation.height),
            displayValue: '${(annotation.positionY * 100).round()}%',
            onChanged: (value) =>
                onChanged(annotation.copyWith(positionY: value)),
          ),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-width'),
            label: 'Width',
            value: annotation.width,
            min: 0.05,
            max: math.max(0.05, 1 - annotation.positionX),
            displayValue: '${(annotation.width * 100).round()}%',
            onChanged: (value) => onChanged(annotation.copyWith(width: value)),
          ),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-height'),
            label: 'Height',
            value: annotation.height,
            min: 0.05,
            max: math.max(0.05, 1 - annotation.positionY),
            displayValue: '${(annotation.height * 100).round()}%',
            onChanged: (value) => onChanged(annotation.copyWith(height: value)),
          ),
          _ImageAnnotationPropertySlider(
            sliderKey: const ValueKey('image-annotation-rotation'),
            label: 'Rotation',
            value: annotation.rotationDegrees,
            min: -180,
            max: 180,
            displayValue: '${annotation.rotationDegrees.round()}°',
            onChanged: (value) =>
                onChanged(annotation.copyWith(rotationDegrees: value)),
          ),
          Text(
            'Drag annotation on preview. Use corner handle to resize.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

final class _ImageAnnotationPropertySlider extends StatelessWidget {
  const _ImageAnnotationPropertySlider({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(displayValue, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      Slider(
        key: sliderKey,
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );
}

final class _ImageEditorFooter extends StatelessWidget {
  const _ImageEditorFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('image-editor-footer'),
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: child,
    );
  }
}

InputDecoration _imageFieldDecoration(
  BuildContext context, {
  required String label,
  String? hintText,
  String? errorText,
  Widget? suffixIcon,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    errorText: errorText,
    suffixIcon: suffixIcon,
    isDense: true,
    filled: true,
    fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.38),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: colors.outlineVariant),
    ),
  );
}

IconData _imageAnnotationIcon(ImageAnnotationType type) => switch (type) {
  ImageAnnotationType.text => Icons.text_fields_rounded,
  ImageAnnotationType.arrow => Icons.arrow_right_alt_rounded,
  ImageAnnotationType.rectangle => Icons.crop_square_rounded,
  ImageAnnotationType.freehand => Icons.gesture_rounded,
};

String _imageAnnotationLabel(ImageAnnotationType type) => switch (type) {
  ImageAnnotationType.text => 'Text',
  ImageAnnotationType.arrow => 'Arrow',
  ImageAnnotationType.rectangle => 'Rectangle',
  ImageAnnotationType.freehand => 'Freehand',
};

final class _ImageAdjustmentSlider extends StatelessWidget {
  const _ImageAdjustmentSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Text(
            value.toStringAsFixed(1),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Reset $label',
            visualDensity: VisualDensity.compact,
            onPressed: value == 0 ? null : () => onChanged(0),
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
        ],
      ),
      Slider(
        value: value,
        min: -1,
        max: 1,
        divisions: 40,
        label: value.toStringAsFixed(2),
        onChanged: onChanged,
      ),
    ],
  );
}

final class _VideoContent extends StatelessWidget {
  const _VideoContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final payload = context.typedPayload is VideoPayload
        ? context.typedPayload! as VideoPayload
        : VideoPayload.fromNode(context.node);
    final preset = context.effectivePreset;
    return Semantics(
      image: true,
      label: payload.altText.isEmpty ? context.node.title : payload.altText,
      child: Container(
        key: ValueKey('video-content-${preset.name}'),
        padding: const EdgeInsets.all(10),
        color: Theme.of(buildContext).colorScheme.surface,
        child: switch (preset) {
          NodeSizePreset.compact => Column(
            children: [
              Expanded(
                child: _videoPlaybackSurface(
                  payload,
                  context.attachmentBytes,
                  onMediaAction: context.onMediaAction,
                ),
              ),
              Text(_videoDuration(payload.durationSeconds)),
            ],
          ),
          NodeSizePreset.standard => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _videoPlaybackSurface(
                  payload,
                  context.attachmentBytes,
                  onMediaAction: context.onMediaAction,
                ),
              ),
              Text(
                payload.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(_videoDuration(payload.durationSeconds)),
            ],
          ),
          NodeSizePreset.large => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _videoPlaybackSurface(
                  payload,
                  context.attachmentBytes,
                  onMediaAction: context.onMediaAction,
                ),
              ),
              Text(
                payload.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              _VideoStatus(payload: payload),
              _videoActions(context, payload),
            ],
          ),
          NodeSizePreset.wide => Row(
            children: [
              Expanded(
                flex: 3,
                child: _videoPlaybackSurface(
                  payload,
                  context.attachmentBytes,
                  onMediaAction: context.onMediaAction,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ListView(
                  children: [
                    Text(
                      payload.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _VideoStatus(payload: payload),
                    Text(payload.fileName, overflow: TextOverflow.ellipsis),
                    _videoActions(context, payload),
                  ],
                ),
              ),
            ],
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

Widget _videoPlaybackSurface(
  VideoPayload payload,
  Uint8List? bytes, {
  ValueChanged<Duration>? onPositionChanged,
  ValueChanged<bool>? onMutedChanged,
  ValueChanged<Duration>? onDurationChanged,
  NodePayloadDraftCallback? onMediaAction,
}) {
  final source = payload.hasLocalAttachment && bytes != null
      ? VideoPlaybackSource.local(
          bytes: bytes,
          mimeType: payload.mimeType,
          fileName: payload.fileName,
        )
      : payload.hasRemoteUrl && isValidExternalVideoUrl(payload.url)
      ? VideoPlaybackSource.remote(Uri.parse(payload.url))
      : null;
  return VideoPlaybackSurface(
    key: ValueKey('video-playback-${source?.identity ?? 'poster'}'),
    source: source,
    poster: _videoPoster(payload, null),
    initialPosition: Duration(
      milliseconds: (payload.playbackPositionSeconds * 1000).round(),
    ),
    initialMuted: payload.muted,
    fit: switch (payload.fitMode) {
      VideoFitMode.contain => BoxFit.contain,
      VideoFitMode.cover => BoxFit.cover,
      VideoFitMode.fill => BoxFit.fill,
      VideoFitMode.fitWidth => BoxFit.fitWidth,
      VideoFitMode.fitHeight => BoxFit.fitHeight,
    },
    onPositionChanged: onPositionChanged,
    onMutedChanged: onMutedChanged,
    onDurationChanged: onDurationChanged,
    recoveryActions: [
      if (payload.hasRemoteUrl)
        TextButton(
          onPressed: () =>
              onMediaAction?.call(OpenVideoExternallyAction(payload.url)),
          child: const Text('Open externally'),
        ),
      if (payload.hasLocalAttachment)
        TextButton(
          onPressed: () =>
              onMediaAction?.call(ExportVideoAction(payload.attachmentId)),
          child: const Text('Export'),
        ),
    ],
  );
}

Widget _videoPoster(VideoPayload payload, Uint8List? thumbnailBytes) {
  final fit = switch (payload.fitMode) {
    VideoFitMode.contain => BoxFit.contain,
    VideoFitMode.cover => BoxFit.cover,
    VideoFitMode.fill => BoxFit.fill,
    VideoFitMode.fitWidth => BoxFit.fitWidth,
    VideoFitMode.fitHeight => BoxFit.fitHeight,
  };
  Widget poster;
  if (thumbnailBytes != null) {
    poster = Image.memory(thumbnailBytes, fit: fit, gaplessPlayback: true);
  } else if (isValidExternalImageUrl(payload.thumbnailUrl)) {
    poster = Image.network(
      payload.thumbnailUrl,
      fit: fit,
      errorBuilder: (_, _, _) => const Icon(Icons.videocam_outlined, size: 48),
    );
  } else {
    poster = const Center(child: Icon(Icons.videocam_outlined, size: 48));
  }
  return Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black12),
        child: poster,
      ),
      const Center(child: Icon(Icons.play_circle_fill, size: 44)),
    ],
  );
}

Widget _videoActions(NodeRenderContext context, VideoPayload payload) => Wrap(
  spacing: 8,
  children: [
    if (isValidExternalVideoUrl(payload.url))
      TextButton(
        onPressed: () =>
            context.onMediaAction?.call(OpenVideoExternallyAction(payload.url)),
        child: const Text('Open externally'),
      ),
    if (payload.hasLocalAttachment)
      TextButton(
        onPressed: () => context.onMediaAction?.call(
          ExportVideoAction(payload.attachmentId),
        ),
        child: const Text('Export'),
      ),
  ],
);

final class _VideoStatus extends StatelessWidget {
  const _VideoStatus({required this.payload});
  final VideoPayload payload;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Icon(payload.muted ? Icons.volume_off : Icons.volume_up, size: 16),
      Text(
        '${_videoDuration(payload.playbackPositionSeconds)} / ${_videoDuration(payload.durationSeconds)}',
      ),
    ],
  );
}

final class _VideoEditor extends StatefulWidget {
  const _VideoEditor(this.context);
  final NodeEditContext context;
  @override
  State<_VideoEditor> createState() => _VideoEditorState();
}

final class _VideoEditorState extends State<_VideoEditor>
    with WidgetsBindingObserver {
  late _VideoPlaybackSession _session = _createSession(widget.context);
  VideoPayload get _draft => _session.draft;

  _VideoPlaybackSession _createSession(NodeEditContext context) {
    final payload = context.typedDraft is VideoPayload
        ? context.typedDraft as VideoPayload
        : VideoPayload.fromNode(context.node);
    final token = _videoSessionToken(context.node.id, payload);
    late final _VideoPlaybackSession session;
    final controller = VideoPlaybackDraftController(
      debounce: context.videoPlaybackDebounce,
      scheduler: context.videoPlaybackScheduler,
      onPersist: (position) async {
        if (!mounted || _session.token != token) return;
        final next = _session.draft.copyWith(playbackPositionSeconds: position);
        _session.draft = next;
        _session.onDraftChanged(next);
      },
      onError: (_, _) {},
    );
    session = _VideoPlaybackSession(
      token: token,
      draft: payload,
      onDraftChanged: context.onDraftChanged,
      controller: controller,
    );
    return session;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _VideoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.node.id != widget.context.node.id ||
        oldWidget.context.typedDraft != widget.context.typedDraft) {
      final oldSession = _session;
      _session = _createSession(widget.context);
      if (oldSession.token == _session.token) {
        unawaited(oldSession.controller.close().catchError((_) {}));
      } else {
        oldSession.controller.discard();
      }
    }
  }

  void _emit(VideoPayload value) {
    setState(() => _session.draft = value);
    _session.onDraftChanged(value);
  }

  void _updatePlaybackPosition(double value) {
    setState(() {
      _session.draft = _draft.copyWith(playbackPositionSeconds: value);
    });
    _session.controller.update(value, durationSeconds: _draft.durationSeconds);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_session.controller.onLifecycleInactive().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_session.controller.close().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedPreset = widget.context.effectivePreset;
    final preset =
        requestedPreset == NodeSizePreset.auto ||
            requestedPreset == NodeSizePreset.custom
        ? NodePresentationSpec.forType(NodeType.video).defaultPreset
        : requestedPreset;
    final playbackControls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resume position: ${_videoDuration(_draft.playbackPositionSeconds)}',
        ),
        Slider(
          key: ValueKey('video-position-${widget.context.node.id}'),
          value: _draft.playbackPositionSeconds.clamp(
            0,
            _draft.durationSeconds > 0 ? _draft.durationSeconds : 1,
          ),
          max: _draft.durationSeconds > 0 ? _draft.durationSeconds : 1,
          onChanged: _updatePlaybackPosition,
          semanticFormatterCallback: _videoDuration,
        ),
        TextButton.icon(
          key: ValueKey('video-save-position-${widget.context.node.id}'),
          onPressed: () =>
              unawaited(_session.controller.onPause().catchError((_) {})),
          icon: const Icon(Icons.pause_circle_outline),
          label: const Text('Pause / Save position'),
        ),
      ],
    );
    final fields = <Widget>[
      TextFormField(
        key: ValueKey('video-url-${widget.context.node.id}'),
        initialValue: _draft.url,
        decoration: const InputDecoration(labelText: 'Video URL'),
        onChanged: (value) => _emit(
          _draft.copyWith(url: value, clearAttachment: value.trim().isNotEmpty),
        ),
      ),
      TextFormField(
        key: ValueKey('video-caption-${widget.context.node.id}'),
        initialValue: _draft.caption,
        decoration: const InputDecoration(labelText: 'Caption'),
        onChanged: (value) => _emit(_draft.copyWith(caption: value)),
      ),
      TextFormField(
        key: ValueKey('video-alt-${widget.context.node.id}'),
        initialValue: _draft.altText,
        decoration: const InputDecoration(labelText: 'Alt text'),
        onChanged: (value) => _emit(_draft.copyWith(altText: value)),
      ),
      Row(
        key: ValueKey('video-muted-${widget.context.node.id}'),
        children: [
          const Expanded(child: Text('Muted')),
          Switch(
            value: _draft.muted,
            onChanged: (value) => _emit(_draft.copyWith(muted: value)),
          ),
        ],
      ),
      DropdownButtonFormField<VideoFitMode>(
        key: ValueKey('video-fit-${widget.context.node.id}'),
        isExpanded: true,
        initialValue: _draft.fitMode,
        decoration: const InputDecoration(labelText: 'Fit'),
        items: [
          for (final value in VideoFitMode.values)
            DropdownMenuItem(value: value, child: Text(value.name)),
        ],
        onChanged: (value) {
          if (value != null) _emit(_draft.copyWith(fitMode: value));
        },
      ),
    ];
    final actions = Wrap(
      key: ValueKey('video-actions-${widget.context.node.id}'),
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: widget.context.onMediaAction == null
              ? null
              : () async =>
                    widget.context.onMediaAction!(const ReplaceVideoAction()),
          child: const Text('Replace'),
        ),
        if (_draft.hasLocalAttachment)
          OutlinedButton(
            onPressed: widget.context.onMediaAction == null
                ? null
                : () async => widget.context.onMediaAction!(
                    ExportVideoAction(_draft.attachmentId),
                  ),
            child: const Text('Export'),
          ),
        if (isValidExternalVideoUrl(_draft.url))
          OutlinedButton(
            onPressed: widget.context.onMediaAction == null
                ? null
                : () async => widget.context.onMediaAction!(
                    OpenVideoExternallyAction(_draft.url),
                  ),
            child: const Text('Open externally'),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectivePreset =
            (constraints.hasBoundedWidth && constraints.maxWidth < 420) ||
                (constraints.hasBoundedHeight && constraints.maxHeight < 360)
            ? NodeSizePreset.compact
            : preset;
        return Container(
          key: ValueKey('video-editor-${preset.name}'),
          padding: const EdgeInsets.all(12),
          child: switch (effectivePreset) {
            NodeSizePreset.compact => ListView(
              children: [fields[0], fields[1], actions],
            ),
            NodeSizePreset.standard => ListView(
              children: [
                SizedBox(
                  height: 100,
                  child: _videoPlaybackSurface(
                    _draft,
                    widget.context.attachmentBytes,
                    onPositionChanged: (position) =>
                        _updatePlaybackPosition(position.inMilliseconds / 1000),
                    onMutedChanged: (muted) {
                      if (muted != _draft.muted) {
                        _emit(_draft.copyWith(muted: muted));
                      }
                    },
                    onMediaAction: widget.context.onMediaAction,
                    onDurationChanged: (duration) {
                      final seconds = duration.inMilliseconds / 1000;
                      if (seconds != _draft.durationSeconds) {
                        _emit(_draft.copyWith(durationSeconds: seconds));
                      }
                    },
                  ),
                ),
                ...fields.take(3),
                actions,
              ],
            ),
            NodeSizePreset.large => ListView(
              children: [
                SizedBox(
                  height: 180,
                  child: _videoPlaybackSurface(
                    _draft,
                    widget.context.attachmentBytes,
                    onPositionChanged: (position) =>
                        _updatePlaybackPosition(position.inMilliseconds / 1000),
                    onMutedChanged: (muted) {
                      if (muted != _draft.muted) {
                        _emit(_draft.copyWith(muted: muted));
                      }
                    },
                    onMediaAction: widget.context.onMediaAction,
                    onDurationChanged: (duration) {
                      final seconds = duration.inMilliseconds / 1000;
                      if (seconds != _draft.durationSeconds) {
                        _emit(_draft.copyWith(durationSeconds: seconds));
                      }
                    },
                  ),
                ),
                ...fields,
                _VideoStatus(payload: _draft),
                playbackControls,
                actions,
              ],
            ),
            NodeSizePreset.wide => Builder(
              builder: (context) {
                final preview = SizedBox(
                  key: ValueKey('video-preview-${widget.context.node.id}'),
                  child: _videoPlaybackSurface(
                    _draft,
                    widget.context.attachmentBytes,
                    onPositionChanged: (position) =>
                        _updatePlaybackPosition(position.inMilliseconds / 1000),
                    onMutedChanged: (muted) {
                      if (muted != _draft.muted) {
                        _emit(_draft.copyWith(muted: muted));
                      }
                    },
                    onMediaAction: widget.context.onMediaAction,
                    onDurationChanged: (duration) {
                      final seconds = duration.inMilliseconds / 1000;
                      if (seconds != _draft.durationSeconds) {
                        _emit(_draft.copyWith(durationSeconds: seconds));
                      }
                    },
                  ),
                );

                final colors = Theme.of(context).colorScheme;
                return Padding(
                  key: ValueKey(
                    'video-editor-stacked-${widget.context.node.id}',
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colors.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: preview,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colors.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Video details',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              fields[0],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: fields[1]),
                                  const SizedBox(width: 8),
                                  Expanded(child: fields[2]),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: fields[3]),
                                  const SizedBox(width: 12),
                                  Expanded(child: fields[4]),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _VideoStatus(payload: _draft),
                                  ),
                                  TextButton.icon(
                                    key: ValueKey(
                                      'video-save-position-${widget.context.node.id}',
                                    ),
                                    onPressed: () => unawaited(
                                      _session.controller.onPause().catchError(
                                        (_) {},
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.bookmark_outline,
                                      size: 18,
                                    ),
                                    label: const Text('Save position'),
                                  ),
                                  const SizedBox(width: 8),
                                  actions,
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            _ => const SizedBox.shrink(),
          },
        );
      },
    );
  }
}

final class _VideoPlaybackSession {
  _VideoPlaybackSession({
    required this.token,
    required this.draft,
    required this.onDraftChanged,
    required this.controller,
  });
  final String token;
  VideoPayload draft;
  final NodePayloadDraftCallback onDraftChanged;
  final VideoPlaybackDraftController controller;
}

String _videoSessionToken(String nodeId, VideoPayload payload) =>
    '$nodeId|${payload.attachmentId}|${payload.url}';

String _videoDuration(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final minutes = total ~/ 60;
  final remainder = total % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

final class _ItineraryContent extends StatelessWidget {
  const _ItineraryContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final payload = context.typedPayload is ItineraryPayload
        ? context.typedPayload! as ItineraryPayload
        : ItineraryPayload.fromNode(context.node);
    final requestedPreset = context.effectivePreset;
    final completed = payload.agenda.where((item) => item.completed).length;
    final progress = payload.agenda.isEmpty
        ? 0.0
        : completed / payload.agenda.length;
    final upcoming = [...payload.agenda]
      ..sort((a, b) {
        final day = a.dayOffset.compareTo(b.dayOffset);
        return day == 0 ? a.startMinutes.compareTo(b.startMinutes) : day;
      });
    final next = upcoming.where((item) => !item.completed).firstOrNull;
    final insights = ItineraryInsights.fromPayload(payload);
    final header = _ItineraryPreviewHeader(
      payload: payload,
      completed: completed,
      progress: progress,
    );
    return LayoutBuilder(
      builder: (buildContext, constraints) {
        final preset = _itineraryPreviewPreset(requestedPreset, constraints);
        final condensed =
            constraints.hasBoundedHeight && constraints.maxHeight < 180;
        return Container(
          key: ValueKey('itinerary-content-${requestedPreset.name}'),
          padding: EdgeInsets.all(condensed ? 8 : 12),
          decoration: BoxDecoration(
            color: Theme.of(buildContext).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: condensed
              ? _ItineraryPreviewCondensedHeader(payload: payload)
              : switch (preset) {
                  NodeSizePreset.compact => Column(
                    key: const ValueKey('itinerary-content-compact-summary'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      header,
                      if (next != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Next · ${_clock(next.startMinutes)} ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(buildContext).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _ItineraryPreviewReadiness(insights: insights),
                    ],
                  ),
                  NodeSizePreset.standard => Column(
                    key: const ValueKey('itinerary-content-standard-core'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      header,
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _ItineraryPreviewChip(
                            icon: Icons.schedule_outlined,
                            label: 'Timezone: ${payload.timezone}',
                          ),
                          _ItineraryPreviewChip(
                            icon: Icons.group_outlined,
                            label: '${payload.travelers} travelers',
                          ),
                          _ItineraryPreviewChip(
                            icon: Icons.fact_check_outlined,
                            label: '${insights.readinessScore}% ready',
                          ),
                          if (payload.bookings.isNotEmpty)
                            _ItineraryPreviewChip(
                              icon: Icons.confirmation_number_outlined,
                              label:
                                  '${insights.confirmedBookings}/${payload.bookings.where((booking) => booking.status != 'cancelled').length} bookings',
                            ),
                          if (payload.packing.isNotEmpty)
                            _ItineraryPreviewChip(
                              icon: Icons.luggage_outlined,
                              label:
                                  '${insights.packedItems}/${payload.packing.length} packed',
                            ),
                        ],
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Next: ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  NodeSizePreset.large => Column(
                    key: const ValueKey('itinerary-content-large-detail'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: 10),
                      _ItineraryPreviewReadiness(insights: insights),
                      const SizedBox(height: 10),
                      _ItineraryPreviewBudget(
                        payload: payload,
                        key: const ValueKey('itinerary-content-budget'),
                      ),
                      const SizedBox(height: 10),
                      Expanded(child: _AgendaList(payload: payload)),
                    ],
                  ),
                  NodeSizePreset.wide => Row(
                    key: const ValueKey('itinerary-content-wide-columns'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _ItineraryPreviewChip(
                                  icon: Icons.schedule_outlined,
                                  label: 'Timezone: ${payload.timezone}',
                                ),
                                _ItineraryPreviewChip(
                                  icon: Icons.group_outlined,
                                  label: '${payload.travelers} travelers',
                                ),
                                if (payload.transport.trim().isNotEmpty)
                                  _ItineraryPreviewChip(
                                    icon: Icons.directions_transit_outlined,
                                    label: payload.transport.trim(),
                                  ),
                                if (payload.accommodation.trim().isNotEmpty)
                                  _ItineraryPreviewChip(
                                    icon: Icons.hotel_outlined,
                                    label: payload.accommodation.trim(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _ItineraryPreviewReadiness(insights: insights),
                            const SizedBox(height: 10),
                            _ItineraryPreviewBudget(
                              payload: payload,
                              key: const ValueKey('itinerary-content-budget'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _AgendaList(payload: payload)),
                    ],
                  ),
                  _ => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [header],
                  ),
                },
        );
      },
    );
  }
}

NodeSizePreset _itineraryPreviewPreset(
  NodeSizePreset requested,
  BoxConstraints constraints,
) {
  final width = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : double.infinity;
  final height = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : double.infinity;
  if (width < 420 || height < 210) return NodeSizePreset.compact;
  if (requested == NodeSizePreset.wide && width < 560) {
    return NodeSizePreset.standard;
  }
  if (requested == NodeSizePreset.large && height < 300) {
    return NodeSizePreset.standard;
  }
  return requested;
}

final class _AgendaList extends StatelessWidget {
  const _AgendaList({required this.payload});

  final ItineraryPayload payload;

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('itinerary-content-agenda'),
    padding: EdgeInsets.zero,
    children: [
      if (payload.agenda.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No agenda planned yet.'),
        )
      else
        for (final item in payload.agenda)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.completed
                      ? Icons.check_circle_rounded
                      : _itineraryCategoryIcon(item.category),
                  size: 18,
                  color: item.completed
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        'Day ${item.dayOffset + 1} · ${_clock(item.startMinutes)}${item.location.trim().isEmpty ? '' : ' · ${item.location.trim()}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (item.cost > 0)
                  Text(
                    '${payload.currency} ${_itineraryNumber(item.cost)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
    ],
  );
}

final class _ItineraryPreviewHeader extends StatelessWidget {
  const _ItineraryPreviewHeader({
    required this.payload,
    required this.completed,
    required this.progress,
  });

  final ItineraryPayload payload;
  final int completed;
  final double progress;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('itinerary-preview-header'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              payload.destination.trim().isEmpty
                  ? 'Destination not set'
                  : payload.destination.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          _ItineraryStatusBadge(status: payload.status),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        '${_date(payload.startDate)} – ${_date(payload.endDate)} · ${_itineraryTripDays(payload)} days',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$completed/${payload.agenda.length}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ],
  );
}

final class _ItineraryPreviewCondensedHeader extends StatelessWidget {
  const _ItineraryPreviewCondensedHeader({required this.payload});

  final ItineraryPayload payload;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('itinerary-content-condensed-header'),
    children: [
      Icon(
        Icons.travel_explore_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          payload.destination.trim().isEmpty
              ? 'Destination not set'
              : payload.destination.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(width: 6),
      _ItineraryStatusBadge(status: payload.status),
    ],
  );
}

final class _ItineraryPreviewChip extends StatelessWidget {
  const _ItineraryPreviewChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
}

final class _ItineraryPreviewBudget extends StatelessWidget {
  const _ItineraryPreviewBudget({required this.payload, super.key});

  final ItineraryPayload payload;

  @override
  Widget build(BuildContext context) {
    final insights = ItineraryInsights.fromPayload(payload);
    final effectiveCost = math.max(
      payload.actualCost,
      insights.totalPlannedCost,
    );
    final progress = payload.budget <= 0
        ? 0.0
        : (effectiveCost / payload.budget).clamp(0, 1).toDouble();
    final overBudget = payload.budget > 0 && effectiveCost > payload.budget;
    final color = overBudget
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Budget: ${payload.currency} ${_itineraryNumber(effectiveCost)} / ${_itineraryNumber(payload.budget)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: progress,
          minHeight: 5,
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      ],
    );
  }
}

final class _ItineraryPreviewReadiness extends StatelessWidget {
  const _ItineraryPreviewReadiness({required this.insights});

  final ItineraryInsights insights;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = insights.warnings.isEmpty ? colors.primary : colors.tertiary;
    return Row(
      key: const ValueKey('itinerary-content-readiness'),
      children: [
        Icon(
          insights.warnings.isEmpty
              ? Icons.verified_outlined
              : Icons.warning_amber_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: LinearProgressIndicator(
            value: insights.readinessScore / 100,
            minHeight: 5,
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${insights.readinessScore}% ready${insights.warnings.isEmpty ? '' : ' · ${insights.warnings.length} alerts'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

final class _ItineraryEditor extends StatefulWidget {
  const _ItineraryEditor(this.context);
  final NodeEditContext context;
  @override
  State<_ItineraryEditor> createState() => _ItineraryEditorState();
}

final class _ItineraryEditorState extends State<_ItineraryEditor> {
  late ItineraryPayload _draft = widget.context.typedDraft as ItineraryPayload;
  final Map<String, String> _errors = {};
  int _draftRevision = 0;
  int _newAgendaSequence = 0;
  int _newBookingSequence = 0;
  int _newPackingSequence = 0;

  @override
  void didUpdateWidget(covariant _ItineraryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.context.typedDraft as ItineraryPayload;
    final previousIncoming = oldWidget.context.typedDraft as ItineraryPayload;
    final nodeChanged = oldWidget.context.node.id != widget.context.node.id;
    final incomingRevision = jsonEncode(incoming.toData());
    final externalDraftChanged =
        incomingRevision != jsonEncode(previousIncoming.toData()) &&
        incomingRevision != jsonEncode(_draft.toData());
    if (nodeChanged || externalDraftChanged) {
      _draft = incoming;
      _errors.clear();
      _draftRevision++;
    }
  }

  void _emit(ItineraryPayload next) {
    setState(() => _draft = next);
    widget.context.onDraftChanged(next);
  }

  void _dateChanged(String key, String value, bool start) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _date(parsed) != value) {
      setState(() => _errors[key] = 'Date is invalid.');
      return;
    }
    final next = start
        ? _draft.copyWith(startDate: parsed)
        : _draft.copyWith(endDate: parsed);
    final error = next.endDate.isBefore(next.startDate)
        ? 'End date must not precede start date.'
        : '';
    setState(() {
      _errors['start-date'] = error;
      _errors['end-date'] = error;
    });
    if (error.isEmpty) _emit(next);
  }

  void _numberChanged(String key, String value, bool budget) {
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _errors[key] = 'Enter a non-negative finite number.');
      return;
    }
    setState(() => _errors[key] = '');
    _emit(
      budget
          ? _draft.copyWith(budget: parsed)
          : _draft.copyWith(actualCost: parsed),
    );
  }

  void _travelersChanged(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 100) {
      setState(() => _errors['travelers'] = 'Enter 1 to 100 travelers.');
      return;
    }
    setState(() => _errors['travelers'] = '');
    _emit(_draft.copyWith(travelers: parsed));
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _draft.startDate : _draft.endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final next = start
        ? _draft.copyWith(
            startDate: picked,
            endDate: _draft.endDate.isBefore(picked) ? picked : _draft.endDate,
          )
        : _draft.copyWith(
            endDate: picked.isBefore(_draft.startDate)
                ? _draft.startDate
                : picked,
          );
    setState(() {
      _draft = next;
      _draftRevision++;
      _errors['start-date'] = '';
      _errors['end-date'] = '';
    });
    widget.context.onDraftChanged(next);
  }

  void _addAgenda() {
    final days = _itineraryTripDays(_draft);
    final previous = _draft.agenda.lastOrNull;
    var dayOffset = previous?.dayOffset ?? 0;
    var startMinutes = previous == null
        ? 9 * 60
        : previous.startMinutes + previous.durationMinutes;
    if (startMinutes + 60 > 1440) {
      dayOffset = math.min(dayOffset + 1, days - 1);
      startMinutes = 9 * 60;
    }
    final id =
        'agenda-${widget.context.node.id}-${_newAgendaSequence++}-${DateTime.now().microsecondsSinceEpoch}';
    _emit(
      _draft.copyWith(
        agenda: [
          ..._draft.agenda,
          ItineraryAgendaItem(
            id: id,
            title: 'New activity',
            startMinutes: startMinutes,
            durationMinutes: 60,
            dayOffset: dayOffset,
          ),
        ],
      ),
    );
  }

  void _removeAt(int index) {
    final agenda = [..._draft.agenda]..removeAt(index);
    _emit(_draft.copyWith(agenda: agenda));
  }

  void _duplicateAt(int index) {
    final source = _draft.agenda[index];
    final duplicate = source.copyWith(
      id: '${source.id}-copy-${_newAgendaSequence++}',
      title: '${source.title} copy',
      startMinutes: math.min(
        math.max(0, 1440 - source.durationMinutes),
        source.startMinutes + source.durationMinutes,
      ),
      completed: false,
    );
    final agenda = [..._draft.agenda]..insert(index + 1, duplicate);
    _emit(_draft.copyWith(agenda: agenda));
  }

  void _reorder(int oldIndex, int newIndex) {
    final agenda = [..._draft.agenda];
    if (newIndex > oldIndex) newIndex--;
    final item = agenda.removeAt(oldIndex);
    agenda.insert(newIndex, item);
    _emit(_draft.copyWith(agenda: agenda));
  }

  void _agendaTimeChanged(int index, String value) {
    final parts = value.split(':');
    final hours = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final minutes = parts.length == 2 ? int.tryParse(parts[1]) : null;
    final errorKey = 'agenda-$index-time';
    if (hours == null || minutes == null || hours > 23 || minutes > 59) {
      setState(() => _errors[errorKey] = 'Use HH:mm.');
      return;
    }
    setState(() => _errors[errorKey] = '');
    _replaceAt(
      index,
      _draft.agenda[index].copyWith(startMinutes: hours * 60 + minutes),
    );
  }

  void _agendaDurationChanged(int index, String value) {
    final parsed = int.tryParse(value);
    final errorKey = 'agenda-$index-duration';
    final item = _draft.agenda[index];
    if (parsed == null || parsed <= 0 || item.startMinutes + parsed > 1440) {
      setState(() => _errors[errorKey] = 'Duration exceeds this day.');
      return;
    }
    setState(() => _errors[errorKey] = '');
    _replaceAt(index, item.copyWith(durationMinutes: parsed));
  }

  void _agendaCostChanged(int index, String value) {
    final parsed = double.tryParse(value);
    final errorKey = 'agenda-$index-cost';
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _errors[errorKey] = 'Enter a non-negative cost.');
      return;
    }
    setState(() => _errors[errorKey] = '');
    _replaceAt(index, _draft.agenda[index].copyWith(cost: parsed));
  }

  void _addBooking() {
    final startAt = DateTime(
      _draft.startDate.year,
      _draft.startDate.month,
      _draft.startDate.day,
      9,
    );
    final id =
        'booking-${widget.context.node.id}-${_newBookingSequence++}-${DateTime.now().microsecondsSinceEpoch}';
    _emit(
      _draft.copyWith(
        bookings: [
          ..._draft.bookings,
          ItineraryBooking(
            id: id,
            title: 'New booking',
            type: 'other',
            startAt: startAt,
            endAt: startAt.add(const Duration(hours: 1)),
          ),
        ],
      ),
    );
  }

  void _replaceBooking(int index, ItineraryBooking changed) {
    final bookings = [..._draft.bookings]..[index] = changed;
    _emit(_draft.copyWith(bookings: bookings));
  }

  void _duplicateBooking(int index) {
    final source = _draft.bookings[index];
    final duplicate = source.copyWith(
      id: '${source.id}-copy-${_newBookingSequence++}',
      title: '${source.title} copy',
      confirmationCode: '',
      status: 'planned',
    );
    final bookings = [..._draft.bookings]..insert(index + 1, duplicate);
    _emit(_draft.copyWith(bookings: bookings));
  }

  void _removeBooking(int index) {
    final bookings = [..._draft.bookings]..removeAt(index);
    _emit(_draft.copyWith(bookings: bookings));
  }

  void _bookingDateChanged(int index, String value, {required bool start}) {
    final parsed = DateTime.tryParse(value.trim());
    final errorKey = 'booking-$index-${start ? 'start' : 'end'}';
    if (parsed == null) {
      setState(() => _errors[errorKey] = 'Use YYYY-MM-DD HH:mm.');
      return;
    }
    final booking = _draft.bookings[index];
    final next = start
        ? booking.copyWith(startAt: parsed)
        : booking.copyWith(endAt: parsed);
    if (next.endAt.isBefore(next.startAt)) {
      setState(() => _errors[errorKey] = 'End must not precede start.');
      return;
    }
    setState(() {
      _errors['booking-$index-start'] = '';
      _errors['booking-$index-end'] = '';
    });
    _replaceBooking(index, next);
  }

  void _bookingCostChanged(int index, String value) {
    final parsed = double.tryParse(value);
    final errorKey = 'booking-$index-cost';
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _errors[errorKey] = 'Enter a non-negative cost.');
      return;
    }
    setState(() => _errors[errorKey] = '');
    _replaceBooking(index, _draft.bookings[index].copyWith(cost: parsed));
  }

  void _addPackingItem() {
    final id =
        'packing-${widget.context.node.id}-${_newPackingSequence++}-${DateTime.now().microsecondsSinceEpoch}';
    _emit(
      _draft.copyWith(
        packing: [
          ..._draft.packing,
          ItineraryPackingItem(id: id, title: 'New item'),
        ],
      ),
    );
  }

  void _replacePacking(int index, ItineraryPackingItem changed) {
    final packing = [..._draft.packing]..[index] = changed;
    _emit(_draft.copyWith(packing: packing));
  }

  void _removePacking(int index) {
    final packing = [..._draft.packing]..removeAt(index);
    _emit(_draft.copyWith(packing: packing));
  }

  void _packingQuantityChanged(int index, String value) {
    final parsed = int.tryParse(value);
    final errorKey = 'packing-$index-quantity';
    if (parsed == null || parsed < 1 || parsed > 99) {
      setState(() => _errors[errorKey] = 'Use 1 to 99.');
      return;
    }
    setState(() => _errors[errorKey] = '');
    _replacePacking(index, _draft.packing[index].copyWith(quantity: parsed));
  }

  Widget _field(
    String key,
    String label,
    String value,
    ValueChanged<String> changed, {
    TextInputType? keyboardType,
    Widget? suffixIcon,
    int maxLines = 1,
  }) => KeyedSubtree(
    key: ValueKey(
      'itinerary-$key-state-${widget.context.node.id}-$_draftRevision',
    ),
    child: TextFormField(
      key: ValueKey('itinerary-$key-field'),
      initialValue: value,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errors[key]?.isNotEmpty == true ? _errors[key] : null,
        suffixIcon: suffixIcon,
      ),
      onChanged: changed,
    ),
  );

  Widget _statusField() {
    const common = <String>[
      'planned',
      'booked',
      'in-progress',
      'completed',
      'cancelled',
    ];
    final statuses = <String>{_draft.status, ...common}.toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('itinerary-status-field-$_draftRevision'),
      initialValue: _draft.status,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Trip status'),
      items: [
        for (final status in statuses)
          DropdownMenuItem(
            value: status,
            child: Text(_itineraryStatusLabel(status)),
          ),
      ],
      onChanged: (value) {
        if (value != null) _emit(_draft.copyWith(status: value));
      },
    );
  }

  Widget _currencyField() {
    const common = <String>['USD', 'EUR', 'IDR', 'JPY', 'GBP', 'AUD', 'SGD'];
    final currencies = <String>{_draft.currency, ...common}.toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('itinerary-currency-field-$_draftRevision'),
      initialValue: _draft.currency,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Currency'),
      items: [
        for (final currency in currencies)
          DropdownMenuItem(value: currency, child: Text(currency)),
      ],
      onChanged: (value) {
        if (value != null) _emit(_draft.copyWith(currency: value));
      },
    );
  }

  Widget _agendaEditor({required bool wide, required bool showAll}) {
    if (_draft.agenda.isEmpty) {
      return Container(
        key: const ValueKey('itinerary-agenda-empty'),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Text('No agenda yet. Add first activity.'),
      );
    }
    return ReorderableListView(
      key: wide
          ? const ValueKey('itinerary-timeline')
          : const ValueKey('itinerary-large-timeline'),
      padding: EdgeInsets.zero,
      shrinkWrap: showAll,
      physics: showAll ? const NeverScrollableScrollPhysics() : null,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
      children: [
        for (final (index, item) in _draft.agenda.indexed)
          _wideAgendaItem(index, item),
      ],
    );
  }

  Widget _responsivePair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 420) {
        return Column(children: [first, const SizedBox(height: 10), second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 10),
          Expanded(child: second),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final preset = widget.context.effectivePreset;
    final standard = preset == NodeSizePreset.standard;
    final large = preset == NodeSizePreset.large;
    final wide = preset == NodeSizePreset.wide;
    final requestedDetailed = large || wide;
    final color = Theme.of(context).colorScheme.primary;
    final agendaCompleted = _draft.agenda
        .where((item) => item.completed)
        .length;
    final agendaProgress = _draft.agenda.isEmpty
        ? 0.0
        : agendaCompleted / _draft.agenda.length;
    final insights = ItineraryInsights.fromPayload(_draft);
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedWorkspace = constraints.maxHeight >= 1200;
        final detailed =
            constraints.maxWidth >= 360 &&
            (requestedDetailed || expandedWorkspace);
        final showAllContent = detailed && expandedWorkspace;
        final useWideLayout = wide || expandedWorkspace;
        final editorBody = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(key: ValueKey('itinerary-editor-${preset.name}-layout')),
            _ItineraryEditorSummary(
              payload: _draft,
              completed: agendaCompleted,
              progress: agendaProgress,
            ),
            if (detailed) ...[
              const SizedBox(height: 14),
              _ItineraryReadinessPanel(payload: _draft, insights: insights),
            ],
            const SizedBox(height: 16),
            _ItineraryEditorSection(
              title: 'Trip overview',
              icon: Icons.map_outlined,
              child: Column(
                children: [
                  _field(
                    'destination',
                    'Destination',
                    _draft.destination,
                    (value) => _emit(_draft.copyWith(destination: value)),
                  ),
                  const SizedBox(height: 10),
                  _responsivePair(
                    _field(
                      'start-date',
                      'Start date',
                      _date(_draft.startDate),
                      (value) => _dateChanged('start-date', value, true),
                      keyboardType: TextInputType.datetime,
                      suffixIcon: IconButton(
                        key: const ValueKey('itinerary-start-date-picker'),
                        tooltip: 'Pick start date',
                        icon: const Icon(Icons.calendar_today_outlined),
                        onPressed: () => _pickDate(start: true),
                      ),
                    ),
                    _field(
                      'end-date',
                      'End date',
                      _date(_draft.endDate),
                      (value) => _dateChanged('end-date', value, false),
                      keyboardType: TextInputType.datetime,
                      suffixIcon: IconButton(
                        key: const ValueKey('itinerary-end-date-picker'),
                        tooltip: 'Pick end date',
                        icon: const Icon(Icons.event_outlined),
                        onPressed: () => _pickDate(start: false),
                      ),
                    ),
                  ),
                  if (standard || detailed) ...[
                    const SizedBox(height: 10),
                    if (detailed)
                      _responsivePair(
                        _field(
                          'timezone',
                          'Timezone',
                          _draft.timezone,
                          (value) => _emit(_draft.copyWith(timezone: value)),
                        ),
                        _field(
                          'travelers',
                          'Travelers',
                          '${_draft.travelers}',
                          _travelersChanged,
                          keyboardType: TextInputType.number,
                        ),
                      )
                    else
                      _field(
                        'timezone',
                        'Timezone',
                        _draft.timezone,
                        (value) => _emit(_draft.copyWith(timezone: value)),
                      ),
                  ],
                ],
              ),
            ),
            if (detailed) ...[
              const SizedBox(height: 14),
              _ItineraryEditorSection(
                title: 'Travel details',
                icon: Icons.luggage_outlined,
                child: Column(
                  children: [
                    _responsivePair(
                      _field(
                        'transport',
                        'Primary transport',
                        _draft.transport,
                        (value) => _emit(_draft.copyWith(transport: value)),
                      ),
                      _field(
                        'accommodation',
                        'Accommodation',
                        _draft.accommodation,
                        (value) => _emit(_draft.copyWith(accommodation: value)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _field(
                      'booking-reference',
                      'Booking reference',
                      _draft.bookingReference,
                      (value) =>
                          _emit(_draft.copyWith(bookingReference: value)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ItineraryEditorSection(
                title: 'Bookings',
                icon: Icons.confirmation_number_outlined,
                trailing: FilledButton.tonalIcon(
                  key: const ValueKey('itinerary-add-booking'),
                  onPressed: _addBooking,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add booking'),
                ),
                child: _draft.bookings.isEmpty
                    ? const _ItineraryEmptyAdvancedState(
                        key: ValueKey('itinerary-bookings-empty'),
                        icon: Icons.airplane_ticket_outlined,
                        message:
                            'Track flights, hotels, trains, rentals, and reservations.',
                      )
                    : Column(
                        children: [
                          for (final (index, booking)
                              in _draft.bookings.indexed) ...[
                            if (index > 0) const SizedBox(height: 10),
                            _ItineraryBookingEditorCard(
                              key: ValueKey(
                                'itinerary-booking-$index-${booking.id}',
                              ),
                              booking: booking,
                              index: index,
                              currency: _draft.currency,
                              startError: _errors['booking-$index-start'],
                              endError: _errors['booking-$index-end'],
                              costError: _errors['booking-$index-cost'],
                              onChanged: (changed) =>
                                  _replaceBooking(index, changed),
                              onStartChanged: (value) => _bookingDateChanged(
                                index,
                                value,
                                start: true,
                              ),
                              onEndChanged: (value) => _bookingDateChanged(
                                index,
                                value,
                                start: false,
                              ),
                              onCostChanged: (value) =>
                                  _bookingCostChanged(index, value),
                              onDuplicate: () => _duplicateBooking(index),
                              onDelete: () => _removeBooking(index),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _ItineraryEditorSection(
                title: 'Packing checklist',
                icon: Icons.checklist_rounded,
                trailing: FilledButton.tonalIcon(
                  key: const ValueKey('itinerary-add-packing'),
                  onPressed: _addPackingItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add item'),
                ),
                child: _draft.packing.isEmpty
                    ? const _ItineraryEmptyAdvancedState(
                        key: ValueKey('itinerary-packing-empty'),
                        icon: Icons.luggage_outlined,
                        message:
                            'Build a reusable packing list and mark essentials.',
                      )
                    : Column(
                        children: [
                          _ItineraryPackingProgress(
                            payload: _draft,
                            insights: insights,
                          ),
                          const SizedBox(height: 10),
                          for (final (index, item)
                              in _draft.packing.indexed) ...[
                            if (index > 0) const SizedBox(height: 8),
                            _ItineraryPackingEditorRow(
                              key: ValueKey(
                                'itinerary-packing-$index-${item.id}',
                              ),
                              item: item,
                              index: index,
                              quantityError: _errors['packing-$index-quantity'],
                              onChanged: (changed) =>
                                  _replacePacking(index, changed),
                              onQuantityChanged: (value) =>
                                  _packingQuantityChanged(index, value),
                              onDelete: () => _removePacking(index),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _ItineraryEditorSection(
                title: 'Budget & status',
                icon: Icons.account_balance_wallet_outlined,
                child: Column(
                  children: [
                    _responsivePair(_statusField(), _currencyField()),
                    const SizedBox(height: 10),
                    _responsivePair(
                      _field(
                        'budget',
                        'Budget',
                        '${_draft.budget}',
                        (value) => _numberChanged('budget', value, true),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      _field(
                        'actual-cost',
                        'Actual cost',
                        '${_draft.actualCost}',
                        (value) => _numberChanged('actual-cost', value, false),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ItineraryBudgetProgress(payload: _draft),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ItineraryEditorSection(
                title: 'Trip notes',
                icon: Icons.notes_outlined,
                child: _field(
                  'notes',
                  'Important notes, reminders, documents',
                  widget.context.node.body,
                  widget.context.onBodyChanged,
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 14),
              for (final error in {
                ...widget.context.validationErrors,
                ..._draft.validate(title: widget.context.node.title),
              })
                Text(
                  error,
                  key: ValueKey('itinerary-validation-$error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              _ItineraryEditorSection(
                key: const ValueKey('itinerary-agenda-section'),
                title: 'Agenda',
                icon: Icons.route_outlined,
                trailing: FilledButton.tonalIcon(
                  key: const ValueKey('itinerary-add-agenda'),
                  onPressed: _addAgenda,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add activity'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      key: useWideLayout
                          ? const ValueKey('itinerary-editor-wide-columns')
                          : null,
                      children: [
                        Expanded(
                          child: Text(
                            '$agendaCompleted of ${_draft.agenda.length} completed',
                          ),
                        ),
                        Text(
                          '${_itineraryTripDays(_draft)} days · ${_draft.currency} ${_itineraryNumber(insights.totalPlannedCost)} planned',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (showAllContent)
                      KeyedSubtree(
                        key: large
                            ? const ValueKey('itinerary-editor-large-agenda')
                            : null,
                        child: _agendaEditor(
                          wide: useWideLayout,
                          showAll: true,
                        ),
                      )
                    else
                      SizedBox(
                        key: large
                            ? const ValueKey('itinerary-editor-large-agenda')
                            : null,
                        height: useWideLayout ? 430 : 360,
                        child: _agendaEditor(
                          wide: useWideLayout,
                          showAll: false,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (!detailed) const SizedBox(height: 4),
            if (!detailed)
              LinearProgressIndicator(
                value: agendaProgress,
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
          ],
        );
        return Container(
          key: ValueKey('itinerary-editor-${preset.name}'),
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: editorBody,
          ),
        );
      },
    );
  }

  Widget _wideAgendaItem(int index, ItineraryAgendaItem item) =>
      _ItineraryAgendaEditorCard(
        key: ValueKey('agenda-$index-${item.id}'),
        payload: _draft,
        item: item,
        index: index,
        timeError: _errors['agenda-$index-time'],
        durationError: _errors['agenda-$index-duration'],
        costError: _errors['agenda-$index-cost'],
        onChanged: (changed) => _replaceAt(index, changed),
        onTimeChanged: (value) => _agendaTimeChanged(index, value),
        onDurationChanged: (value) => _agendaDurationChanged(index, value),
        onCostChanged: (value) => _agendaCostChanged(index, value),
        onDuplicate: () => _duplicateAt(index),
        onDelete: () => _removeAt(index),
        onConvert: widget.context.onItineraryAction == null
            ? null
            : (target) async => widget.context.onItineraryAction!(
                ConvertItineraryAgendaAction(item: item, target: target),
              ),
      );

  void _replaceAt(int index, ItineraryAgendaItem changed) {
    final agenda = [..._draft.agenda]..[index] = changed;
    _emit(_draft.copyWith(agenda: agenda));
  }
}

final class _ItineraryEditorSummary extends StatelessWidget {
  const _ItineraryEditorSummary({
    required this.payload,
    required this.completed,
    required this.progress,
  });

  final ItineraryPayload payload;
  final int completed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('itinerary-editor-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.75),
            colors.tertiaryContainer.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff_rounded, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  payload.destination.trim().isEmpty
                      ? 'Plan your next trip'
                      : 'Trip to ${payload.destination.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ItineraryStatusBadge(status: payload.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_date(payload.startDate)} – ${_date(payload.endDate)} · ${_itineraryTripDays(payload)} days · ${payload.travelers} travelers',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$completed/${payload.agenda.length} done',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ItineraryEditorSection extends StatelessWidget {
  const _ItineraryEditorSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

final class _ItineraryReadinessPanel extends StatelessWidget {
  const _ItineraryReadinessPanel({
    required this.payload,
    required this.insights,
  });

  final ItineraryPayload payload;
  final ItineraryInsights insights;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warningColor = insights.warnings.isEmpty
        ? colors.primary
        : colors.tertiary;
    return Container(
      key: const ValueKey('itinerary-readiness-panel'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warningColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warningColor.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: warningColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trip readiness',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${insights.readinessScore}%',
                key: const ValueKey('itinerary-readiness-score'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: warningColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(
            value: insights.readinessScore / 100,
            minHeight: 7,
            color: warningColor,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _ItineraryMetricChip(
                icon: Icons.confirmation_number_outlined,
                label:
                    '${insights.confirmedBookings}/${payload.bookings.where((booking) => booking.status != 'cancelled').length} bookings confirmed',
              ),
              _ItineraryMetricChip(
                icon: Icons.luggage_outlined,
                label:
                    '${insights.packedItems}/${payload.packing.length} packed',
              ),
              _ItineraryMetricChip(
                icon: insights.agendaConflicts.isEmpty
                    ? Icons.event_available_outlined
                    : Icons.event_busy_outlined,
                label: insights.agendaConflicts.isEmpty
                    ? 'No schedule conflicts'
                    : '${insights.agendaConflicts.length} schedule conflicts',
              ),
              _ItineraryMetricChip(
                icon: Icons.payments_outlined,
                label:
                    '${payload.currency} ${_itineraryNumber(insights.totalPlannedCost)} planned',
              ),
            ],
          ),
          if (insights.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final warning in insights.warnings.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: warningColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

final class _ItineraryMetricChip extends StatelessWidget {
  const _ItineraryMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

final class _ItineraryEmptyAdvancedState extends StatelessWidget {
  const _ItineraryEmptyAdvancedState({
    required this.icon,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

final class _ItineraryPackingProgress extends StatelessWidget {
  const _ItineraryPackingProgress({
    required this.payload,
    required this.insights,
  });

  final ItineraryPayload payload;
  final ItineraryInsights insights;

  @override
  Widget build(BuildContext context) {
    final progress = payload.packing.isEmpty
        ? 0.0
        : insights.packedItems / payload.packing.length;
    return Row(
      key: const ValueKey('itinerary-packing-progress'),
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${insights.packedItems}/${payload.packing.length} packed',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

final class _ItineraryBookingEditorCard extends StatelessWidget {
  const _ItineraryBookingEditorCard({
    required super.key,
    required this.booking,
    required this.index,
    required this.currency,
    required this.onChanged,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onCostChanged,
    required this.onDuplicate,
    required this.onDelete,
    this.startError,
    this.endError,
    this.costError,
  });

  final ItineraryBooking booking;
  final int index;
  final String currency;
  final ValueChanged<ItineraryBooking> onChanged;
  final ValueChanged<String> onStartChanged;
  final ValueChanged<String> onEndChanged;
  final ValueChanged<String> onCostChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final String? startError;
  final String? endError;
  final String? costError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final types = <String>{
      booking.type,
      'flight',
      'hotel',
      'train',
      'activity',
      'car',
      'other',
    }.toList();
    final statuses = <String>{
      booking.status,
      'planned',
      'reserved',
      'confirmed',
      'completed',
      'cancelled',
    }.toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_itineraryBookingIcon(booking.type), color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('itinerary-booking-title-$index-${booking.id}'),
                  initialValue: booking.title,
                  decoration: const InputDecoration(
                    labelText: 'Booking title',
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      onChanged(booking.copyWith(title: value)),
                ),
              ),
              IconButton(
                tooltip: 'Duplicate ${booking.title}',
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Delete ${booking.title}',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth < 540
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'itinerary-booking-type-$index-${booking.id}',
                      ),
                      initialValue: booking.type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        isDense: true,
                      ),
                      items: [
                        for (final type in types)
                          DropdownMenuItem(
                            value: type,
                            child: Text(_itineraryBookingTypeLabel(type)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onChanged(booking.copyWith(type: value));
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'itinerary-booking-status-$index-${booking.id}',
                      ),
                      initialValue: booking.status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        isDense: true,
                      ),
                      items: [
                        for (final status in statuses)
                          DropdownMenuItem(
                            value: status,
                            child: Text(_itineraryBookingStatusLabel(status)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onChanged(booking.copyWith(status: value));
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-provider-$index-${booking.id}',
                      ),
                      initialValue: booking.provider,
                      decoration: const InputDecoration(
                        labelText: 'Provider',
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          onChanged(booking.copyWith(provider: value)),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-code-$index-${booking.id}',
                      ),
                      initialValue: booking.confirmationCode,
                      decoration: const InputDecoration(
                        labelText: 'Confirmation code',
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          onChanged(booking.copyWith(confirmationCode: value)),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-start-$index-${booking.id}',
                      ),
                      initialValue: _itineraryDateTime(booking.startAt),
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: 'Start',
                        helperText: 'YYYY-MM-DD HH:mm',
                        errorText: startError?.isNotEmpty == true
                            ? startError
                            : null,
                        isDense: true,
                      ),
                      onChanged: onStartChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-end-$index-${booking.id}',
                      ),
                      initialValue: _itineraryDateTime(booking.endAt),
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: 'End',
                        helperText: 'YYYY-MM-DD HH:mm',
                        errorText: endError?.isNotEmpty == true
                            ? endError
                            : null,
                        isDense: true,
                      ),
                      onChanged: onEndChanged,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-location-$index-${booking.id}',
                      ),
                      initialValue: booking.location,
                      decoration: const InputDecoration(
                        labelText: 'Location / terminal',
                        isDense: true,
                      ),
                      onChanged: (value) =>
                          onChanged(booking.copyWith(location: value)),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-booking-cost-$index-${booking.id}',
                      ),
                      initialValue: _itineraryNumber(booking.cost),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cost $currency',
                        errorText: costError?.isNotEmpty == true
                            ? costError
                            : null,
                        isDense: true,
                      ),
                      onChanged: onCostChanged,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('itinerary-booking-notes-$index-${booking.id}'),
            initialValue: booking.notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Booking notes, cancellation terms, contacts',
              isDense: true,
            ),
            onChanged: (value) => onChanged(booking.copyWith(notes: value)),
          ),
        ],
      ),
    );
  }
}

final class _ItineraryPackingEditorRow extends StatelessWidget {
  const _ItineraryPackingEditorRow({
    required super.key,
    required this.item,
    required this.index,
    required this.onChanged,
    required this.onQuantityChanged,
    required this.onDelete,
    this.quantityError,
  });

  final ItineraryPackingItem item;
  final int index;
  final ValueChanged<ItineraryPackingItem> onChanged;
  final ValueChanged<String> onQuantityChanged;
  final VoidCallback onDelete;
  final String? quantityError;

  @override
  Widget build(BuildContext context) {
    final categories = <String>{
      item.category,
      'documents',
      'clothing',
      'electronics',
      'toiletries',
      'health',
      'misc',
    }.toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                label: item.packed
                    ? 'Unpack ${item.title}'
                    : 'Pack ${item.title}',
                child: Checkbox(
                  value: item.packed,
                  onChanged: (value) =>
                      onChanged(item.copyWith(packed: value ?? false)),
                ),
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('itinerary-packing-title-$index-${item.id}'),
                  initialValue: item.title,
                  decoration: const InputDecoration(
                    labelText: 'Item',
                    isDense: true,
                  ),
                  onChanged: (value) => onChanged(item.copyWith(title: value)),
                ),
              ),
              IconButton(
                tooltip: item.essential
                    ? 'Mark ${item.title} optional'
                    : 'Mark ${item.title} essential',
                onPressed: () =>
                    onChanged(item.copyWith(essential: !item.essential)),
                icon: Icon(
                  item.essential
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: item.essential
                      ? Theme.of(context).colorScheme.tertiary
                      : null,
                ),
              ),
              IconButton(
                tooltip: 'Delete ${item.title}',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final categoryWidth = math.max(160.0, constraints.maxWidth - 100);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: math.min(categoryWidth, constraints.maxWidth * 0.68),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'itinerary-packing-category-$index-${item.id}',
                      ),
                      initialValue: item.category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        isDense: true,
                      ),
                      items: [
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(
                              _itineraryPackingCategoryLabel(category),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          onChanged(item.copyWith(category: value));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey(
                        'itinerary-packing-quantity-$index-${item.id}',
                      ),
                      initialValue: '${item.quantity}',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Qty',
                        errorText: quantityError?.isNotEmpty == true
                            ? quantityError
                            : null,
                        isDense: true,
                      ),
                      onChanged: onQuantityChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

final class _ItineraryBudgetProgress extends StatelessWidget {
  const _ItineraryBudgetProgress({required this.payload});

  final ItineraryPayload payload;

  @override
  Widget build(BuildContext context) {
    final insights = ItineraryInsights.fromPayload(payload);
    final effectiveCost = math.max(
      payload.actualCost,
      insights.totalPlannedCost,
    );
    final overBudget = payload.budget > 0 && effectiveCost > payload.budget;
    final progress = payload.budget <= 0
        ? 0.0
        : (effectiveCost / payload.budget).clamp(0, 1).toDouble();
    final remaining = payload.budget - effectiveCost;
    final color = overBudget
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Column(
      key: const ValueKey('itinerary-budget-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 7,
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 6),
        Text(
          payload.budget <= 0
              ? 'Set a budget to track trip spending.'
              : overBudget
              ? '${payload.currency} ${_itineraryNumber(remaining.abs())} over budget'
              : '${payload.currency} ${_itineraryNumber(remaining)} remaining · ${_itineraryNumber(insights.totalPlannedCost)} planned',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

final class _ItineraryAgendaEditorCard extends StatelessWidget {
  const _ItineraryAgendaEditorCard({
    required super.key,
    required this.payload,
    required this.item,
    required this.index,
    required this.onChanged,
    required this.onTimeChanged,
    required this.onDurationChanged,
    required this.onCostChanged,
    required this.onDuplicate,
    required this.onDelete,
    this.timeError,
    this.durationError,
    this.costError,
    this.onConvert,
  });

  final ItineraryPayload payload;
  final ItineraryAgendaItem item;
  final int index;
  final ValueChanged<ItineraryAgendaItem> onChanged;
  final ValueChanged<String> onTimeChanged;
  final ValueChanged<String> onDurationChanged;
  final ValueChanged<String> onCostChanged;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final String? timeError;
  final String? durationError;
  final String? costError;
  final FutureOr<void> Function(ItineraryConversionTarget target)? onConvert;

  @override
  Widget build(BuildContext context) {
    final days = _itineraryTripDays(payload);
    final safeDay = item.dayOffset.clamp(0, days - 1);
    const categories = <String>[
      'activity',
      'transport',
      'food',
      'lodging',
      'reservation',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 13, right: 4),
                    child: Icon(Icons.drag_indicator_rounded),
                  ),
                ),
                Checkbox(
                  semanticLabel: 'Complete ${item.title} item ${index + 1}',
                  value: item.completed,
                  onChanged: (value) =>
                      onChanged(item.copyWith(completed: value ?? false)),
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('itinerary-wide-title-$index-${item.id}'),
                    initialValue: item.title,
                    decoration: const InputDecoration(
                      labelText: 'Activity',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        onChanged(item.copyWith(title: value)),
                  ),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  key: ValueKey('itinerary-category-$index-${item.id}'),
                  tooltip: 'Agenda category',
                  initialValue: item.category,
                  onSelected: (value) =>
                      onChanged(item.copyWith(category: value)),
                  itemBuilder: (context) => [
                    for (final category in categories)
                      PopupMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            Icon(_itineraryCategoryIcon(category), size: 18),
                            const SizedBox(width: 8),
                            Text(_itineraryCategoryLabel(category)),
                          ],
                        ),
                      ),
                  ],
                  icon: Icon(_itineraryCategoryIcon(item.category)),
                ),
                IconButton(
                  key: ValueKey<String>('itinerary-convert-task-${item.id}'),
                  tooltip: 'Convert ${item.title} to task',
                  onPressed: onConvert == null
                      ? null
                      : () async => onConvert!(ItineraryConversionTarget.task),
                  icon: const Icon(Icons.task_alt, size: 19),
                ),
                IconButton(
                  key: ValueKey<String>('itinerary-convert-event-${item.id}'),
                  tooltip: 'Convert ${item.title} to event',
                  onPressed: onConvert == null
                      ? null
                      : () async => onConvert!(ItineraryConversionTarget.event),
                  icon: const Icon(Icons.event_outlined, size: 19),
                ),
                IconButton(
                  key: ValueKey('itinerary-duplicate-$index-${item.id}'),
                  tooltip: 'Duplicate ${item.title}',
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  key: ValueKey('itinerary-delete-$index-${item.id}'),
                  tooltip: 'Delete ${item.title}',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('itinerary-day-$index-${item.id}'),
                    initialValue: safeDay,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Trip day',
                      isDense: true,
                      helperText: _date(
                        payload.startDate.add(Duration(days: safeDay)),
                      ),
                    ),
                    items: [
                      for (var day = 0; day < days; day++)
                        DropdownMenuItem(
                          value: day,
                          child: Text('Day ${day + 1}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onChanged(item.copyWith(dayOffset: value));
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 115,
                  child: TextFormField(
                    key: ValueKey('itinerary-time-$index-${item.id}'),
                    initialValue: _clock(item.startMinutes),
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: 'Start',
                      isDense: true,
                      errorText: timeError?.isNotEmpty == true
                          ? timeError
                          : null,
                    ),
                    onChanged: onTimeChanged,
                  ),
                ),
                SizedBox(
                  width: 125,
                  child: TextFormField(
                    key: ValueKey('itinerary-duration-$index-${item.id}'),
                    initialValue: '${item.durationMinutes}',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Minutes',
                      isDense: true,
                      errorText: durationError?.isNotEmpty == true
                          ? durationError
                          : null,
                    ),
                    onChanged: onDurationChanged,
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    key: ValueKey('itinerary-cost-$index-${item.id}'),
                    initialValue: _itineraryNumber(item.cost),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cost ${payload.currency}',
                      isDense: true,
                      errorText: costError?.isNotEmpty == true
                          ? costError
                          : null,
                    ),
                    onChanged: onCostChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('itinerary-location-$index-${item.id}'),
              initialValue: item.location,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
                isDense: true,
              ),
              onChanged: (value) => onChanged(item.copyWith(location: value)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('itinerary-item-notes-$index-${item.id}'),
              initialValue: item.notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes, reservation details, reminders',
                isDense: true,
              ),
              onChanged: (value) => onChanged(item.copyWith(notes: value)),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ItineraryStatusBadge extends StatelessWidget {
  const _ItineraryStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      _itineraryStatusLabel(status),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

int _itineraryTripDays(ItineraryPayload payload) =>
    math.max(1, payload.endDate.difference(payload.startDate).inDays + 1);

String _itineraryNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String _itineraryStatusLabel(String status) => switch (status) {
  'booked' => 'Booked',
  'in-progress' => 'In progress',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => 'Planned',
};

String _itineraryCategoryLabel(String category) => switch (category) {
  'transport' => 'Transport',
  'food' => 'Food',
  'lodging' => 'Lodging',
  'reservation' => 'Reservation',
  _ => 'Activity',
};

IconData _itineraryCategoryIcon(String category) => switch (category) {
  'transport' => Icons.directions_transit_outlined,
  'food' => Icons.restaurant_outlined,
  'lodging' => Icons.hotel_outlined,
  'reservation' => Icons.confirmation_number_outlined,
  _ => Icons.explore_outlined,
};

String _itineraryBookingTypeLabel(String type) => switch (type) {
  'flight' => 'Flight',
  'hotel' => 'Hotel',
  'train' => 'Train',
  'activity' => 'Activity',
  'car' => 'Car rental',
  _ => 'Other',
};

String _itineraryBookingStatusLabel(String status) => switch (status) {
  'reserved' => 'Reserved',
  'confirmed' => 'Confirmed',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => 'Planned',
};

IconData _itineraryBookingIcon(String type) => switch (type) {
  'flight' => Icons.flight_outlined,
  'hotel' => Icons.hotel_outlined,
  'train' => Icons.train_outlined,
  'activity' => Icons.local_activity_outlined,
  'car' => Icons.directions_car_outlined,
  _ => Icons.confirmation_number_outlined,
};

String _itineraryPackingCategoryLabel(String category) => switch (category) {
  'documents' => 'Documents',
  'clothing' => 'Clothing',
  'electronics' => 'Electronics',
  'toiletries' => 'Toiletries',
  'health' => 'Health',
  _ => 'Miscellaneous',
};

String _itineraryDateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
