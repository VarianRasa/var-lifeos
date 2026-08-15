# Image Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement non-destructive image annotations (numbered comment pins and vector freehand sketch paths) stored in relative coordinates inside `MindmapNode.data['annotations']` with FTS search projection.

**Architecture:** Domain annotation model & codec -> Interactive overlay painter & gesture controller -> FTS Search document projection -> Canvas image node integration.

**Tech Stack:** Dart SDK 3.11+, Flutter, CustomPainter, Riverpod, Sembast.

## Global Constraints

- Store all points and pin anchors as relative ratios `xRatio`, `yRatio` in range `[0.0, 1.0]`.
- Never modify or overwrite original image files.
- Project pin text into searchable FTS index via `SearchDocumentProjector`.
- Support undo/redo for drawing strokes before persistence.

---

### Task 1: Image Annotation Domain Model, Codec, and FTS Search Projection

**Files:**
- Create: `lib/features/mindmap/domain/image_annotation.dart`
- Modify: `lib/features/search/application/search_document_projector.dart`
- Create: `test/features/mindmap/domain/image_annotation_test.dart`
- Modify: `test/features/search/application/search_document_projector_test.dart`

**Interfaces:**
- Consumes: `MindmapNode`, `SearchDocument`
- Produces: `ImageAnnotationPin`, `ImageAnnotationStroke`, `ImageAnnotationData`, `SearchDocumentProjector.projectNode`

- [ ] **Step 1: Write failing unit test for annotation domain codec & search projection**

```dart
// test/features/mindmap/domain/image_annotation_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

void main() {
  group('ImageAnnotationData', () {
    test('serializes and deserializes pins and strokes using relative ratios', () {
      const data = ImageAnnotationData(
        pins: [
          ImageAnnotationPin(
            id: 'pin-1',
            xRatio: 0.4,
            yRatio: 0.6,
            text: 'Check shadow details',
          ),
        ],
        strokes: [
          ImageAnnotationStroke(
            colorValue: 0xFFFF0000,
            strokeWidth: 3.0,
            points: [
              ImageAnnotationPoint(xRatio: 0.1, yRatio: 0.2),
              ImageAnnotationPoint(xRatio: 0.15, yRatio: 0.25),
            ],
          ),
        ],
      );

      final json = data.toJson();
      final restored = ImageAnnotationData.fromJson(json);

      expect(restored.pins.length, equals(1));
      expect(restored.pins.first.text, equals('Check shadow details'));
      expect(restored.strokes.length, equals(1));
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/domain/image_annotation_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ImageAnnotation domain classes & update SearchDocumentProjector**

```dart
// lib/features/mindmap/domain/image_annotation.dart
class ImageAnnotationPoint {
  final double xRatio;
  final double yRatio;

  const ImageAnnotationPoint({required this.xRatio, required this.yRatio});

  Map<String, dynamic> toJson() => {'xRatio': xRatio, 'yRatio': yRatio};

  factory ImageAnnotationPoint.fromJson(Map<String, dynamic> json) => ImageAnnotationPoint(
        xRatio: (json['xRatio'] as num).toDouble(),
        yRatio: (json['yRatio'] as num).toDouble(),
      );
}

class ImageAnnotationPin {
  final String id;
  final double xRatio;
  final double yRatio;
  final String text;
  final String? createdAt;

  const ImageAnnotationPin({
    required this.id,
    required this.xRatio,
    required this.yRatio,
    required this.text,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'xRatio': xRatio,
        'yRatio': yRatio,
        'text': text,
        'createdAt': createdAt ?? DateTime.now().toIso8601String(),
      };

  factory ImageAnnotationPin.fromJson(Map<String, dynamic> json) => ImageAnnotationPin(
        id: json['id'] as String,
        xRatio: (json['xRatio'] as num).toDouble(),
        yRatio: (json['yRatio'] as num).toDouble(),
        text: json['text'] as String,
        createdAt: json['createdAt'] as String?,
      );
}

class ImageAnnotationStroke {
  final int colorValue;
  final double strokeWidth;
  final List<ImageAnnotationPoint> points;

  const ImageAnnotationStroke({
    required this.colorValue,
    required this.strokeWidth,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'color': colorValue,
        'strokeWidth': strokeWidth,
        'points': points.map((p) => p.toJson()).toList(),
      };

  factory ImageAnnotationStroke.fromJson(Map<String, dynamic> json) => ImageAnnotationStroke(
        colorValue: json['color'] as int,
        strokeWidth: (json['strokeWidth'] as num).toDouble(),
        points: (json['points'] as List)
            .map((p) => ImageAnnotationPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class ImageAnnotationData {
  final List<ImageAnnotationPin> pins;
  final List<ImageAnnotationStroke> strokes;

  const ImageAnnotationData({this.pins = const [], this.strokes = const []});

  Map<String, dynamic> toJson() => {
        'pins': pins.map((p) => p.toJson()).toList(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory ImageAnnotationData.fromJson(Map<String, dynamic> json) {
    return ImageAnnotationData(
      pins: ((json['pins'] as List?) ?? [])
          .map((p) => ImageAnnotationPin.fromJson(p as Map<String, dynamic>))
          .toList(),
      strokes: ((json['strokes'] as List?) ?? [])
          .map((s) => ImageAnnotationStroke.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
```

Update `lib/features/search/application/search_document_projector.dart` to inspect `node.data['annotations']` and append pin comment texts to projected node text.

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/domain/image_annotation_test.dart test/features/search/application/search_document_projector_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/image_annotation.dart lib/features/search/application/search_document_projector.dart test/features/mindmap/domain/image_annotation_test.dart
git commit -m "feat: add image annotation domain model and FTS search projection"
```

---

### Task 2: Responsive Image Annotation Overlay Widget & Gesture Controller

**Files:**
- Create: `lib/features/mindmap/presentation/image_annotation_overlay.dart`
- Create: `lib/features/mindmap/application/image_annotation_controller.dart`
- Create: `test/features/mindmap/presentation/image_annotation_overlay_test.dart`

**Interfaces:**
- Consumes: `ImageAnnotationData`, `ImageAnnotationPin`, `ImageAnnotationStroke`
- Produces: `ImageAnnotationOverlay`, `ImageAnnotationController`

- [ ] **Step 1: Write failing widget test for responsive annotation overlay and pin popover**

```dart
// test/features/mindmap/presentation/image_annotation_overlay_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';
import 'package:var_app/features/mindmap/presentation/image_annotation_overlay.dart';

void main() {
  group('ImageAnnotationOverlay', () {
    testWidgets('renders numbered pin badge at relative ratio position', (tester) async {
      const data = ImageAnnotationData(
        pins: [
          ImageAnnotationPin(
            id: 'pin-1',
            xRatio: 0.5,
            yRatio: 0.5,
            text: 'Center Note',
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: ImageAnnotationOverlay(
                annotationData: data,
                isAnnotating: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/presentation/image_annotation_overlay_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement ImageAnnotationOverlay and CustomPainter**

```dart
// lib/features/mindmap/presentation/image_annotation_overlay.dart
import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/image_annotation.dart';

class ImageAnnotationOverlay extends StatelessWidget {
  final ImageAnnotationData annotationData;
  final bool isAnnotating;
  final Function(ImageAnnotationPin pin)? onPinTap;
  final Function(Offset localOffset)? onTapToAddPin;

  const ImageAnnotationOverlay({
    super.key,
    required this.annotationData,
    this.isAnnotating = false,
    this.onPinTap,
    this.onTapToAddPin,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            CustomPaint(
              size: Size(width, height),
              painter: _AnnotationPainter(annotationData: annotationData),
            ),
            for (var i = 0; i < annotationData.pins.length; i++) ...[
              Positioned(
                left: annotationData.pins[i].xRatio * width - 12,
                top: annotationData.pins[i].yRatio * height - 12,
                child: GestureDetector(
                  onTap: () => onPinTap?.call(annotationData.pins[i]),
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.amber,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final ImageAnnotationData annotationData;

  _AnnotationPainter({required this.annotationData});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in annotationData.strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        :color = Color(stroke.colorValue)
        :strokeWidth = stroke.strokeWidth
        :strokeCap = StrokeCap.round
        :style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(
        stroke.points.first.xRatio * size.width,
        stroke.points.first.yRatio * size.height,
      );

      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
          stroke.points[i].xRatio * size.width,
          stroke.points[i].yRatio * size.height,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `flutter test test/features/mindmap/presentation/image_annotation_overlay_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/image_annotation_overlay.dart test/features/mindmap/presentation/image_annotation_overlay_test.dart
git commit -m "feat: add responsive ImageAnnotationOverlay widget and vector painter"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-04-image-annotation.md`. Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?