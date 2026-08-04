# Connection Lines & Arrows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Connection Lines & Arrows in `MindmapCanvas` for node-to-node and node-to-point connections with customizable color, line style, arrow style, and label.

**Architecture:** Extend domain metadata for `NodeType.connection` (or parsed connection data) in `lib/features/mindmap/domain/mindmap_node_data.dart`, render smooth Bezier curves using a custom painter in `lib/features/mindmap/presentation/mindmap_connection_painter.dart`, and add interactive selection/editing toolbars in `lib/features/mindmap/presentation/mindmap_canvas.dart`.

**Tech Stack:** Flutter, Dart, Riverpod.

## Global Constraints
- Target SDK/Platform: Flutter Desktop / Web / Mobile.
- Styling: Material 3 dark theme, tokens from `lib/core/theme/app_colors.dart`.
- Quality: All new code must pass `flutter analyze` and unit/widget tests.

---

### Task 1: Domain Connection Metadata Struct & Helpers

**Files:**
- Modify: `lib/features/mindmap/domain/mindmap_node_data.dart`
- Test: `test/features/mindmap/domain/mindmap_node_data_test.dart`

**Interfaces:**
- Produces: `ConnectionMetadata` class, `connectionMetadataFromData(Map<String, Object?> data)`, and `dataWithConnectionMetadata(...)`.

- [ ] **Step 1: Write failing domain unit test for ConnectionMetadata**

```dart
test('connectionMetadataFromData returns correct fallback and parsed values', () {
  final empty = connectionMetadataFromData({});
  expect(empty.lineStyle, equals('solid'));
  expect(empty.arrowStyle, equals('end'));
  expect(empty.color, equals('slate'));

  final customData = {
    'startNodeId': 'node-1',
    'endNodeId': 'node-2',
    'lineStyle': 'dashed',
    'arrowStyle': 'both',
    'color': 'indigo',
    'label': 'relates to',
  };
  final parsed = connectionMetadataFromData(customData);
  expect(parsed.startNodeId, equals('node-1'));
  expect(parsed.endNodeId, equals('node-2'));
  expect(parsed.lineStyle, equals('dashed'));
  expect(parsed.arrowStyle, equals('both'));
  expect(parsed.color, equals('indigo'));
  expect(parsed.label, equals('relates to'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart --name "connectionMetadataFromData"`
Expected: FAIL (unresolved identifier)

- [ ] **Step 3: Implement ConnectionMetadata struct and helper methods**

Add to `lib/features/mindmap/domain/mindmap_node_data.dart`:
```dart
class ConnectionMetadata {
  const ConnectionMetadata({
    this.startNodeId,
    this.startPoint,
    this.endNodeId,
    this.endPoint,
    this.lineStyle = 'solid',
    this.arrowStyle = 'end',
    this.color = 'slate',
    this.label,
  });

  final String? startNodeId;
  final Offset? startPoint;
  final String? endNodeId;
  final Offset? endPoint;
  final String lineStyle;
  final String arrowStyle;
  final String color;
  final String? label;
}

ConnectionMetadata connectionMetadataFromData(Map<String, Object?> data) { ... }
Map<String, Object?> dataWithConnectionMetadata(Map<String, Object?> data, ConnectionMetadata metadata) { ... }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/domain/mindmap_node_data_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/mindmap_node_data.dart test/features/mindmap/domain/mindmap_node_data_test.dart
git commit -m "feat(mindmap): add ConnectionMetadata domain model and helpers"
```

---

### Task 2: Custom Painter for Smooth Bezier Connection Lines

**Files:**
- Create: `lib/features/mindmap/presentation/mindmap_connection_painter.dart`
- Create: `test/features/mindmap/presentation/mindmap_connection_painter_test.dart`

**Interfaces:**
- Consumes: `ConnectionMetadata` from Task 1.
- Produces: `MindmapConnectionPainter` widget component for canvas rendering.

- [ ] **Step 1: Write failing painter test**

```dart
testWidgets('MindmapConnectionPainter paints connection curve and label', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CustomPaint(
        painter: MindmapConnectionPainter(
          connections: [
            ConnectionRenderItem(
              id: 'conn-1',
              start: const Offset(100, 100),
              end: const Offset(300, 300),
              metadata: const ConnectionMetadata(label: 'Test Link'),
            ),
          ],
        ),
      ),
    ),
  );
  expect(find.byType(CustomPaint), findsOneWidget);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/presentation/mindmap_connection_painter_test.dart`
Expected: FAIL (file/class missing)

- [ ] **Step 3: Implement MindmapConnectionPainter**

Build painter drawing `Path.cubicTo`, styled stroke (`solid`, `dashed`, `dotted`), arrows at endpoints, and text label centered on the curve midpoint.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/mindmap_connection_painter_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_connection_painter.dart test/features/mindmap/presentation/mindmap_connection_painter_test.dart
git commit -m "feat(mindmap): add MindmapConnectionPainter for connection curves"
```

---

### Task 3: Integrate Connection Creation and Context Menu in Canvas

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

**Interfaces:**
- Consumes: `MindmapConnectionPainter` from Task 2.

- [ ] **Step 1: Write failing canvas integration widget test**

```dart
testWidgets('MindmapCanvas renders connection lines and handles line selection', (tester) async {
  // Test connection node rendering and selection menu display
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart --name "renders connection lines"`
Expected: FAIL

- [ ] **Step 3: Implement canvas integration & floating line menu**

Wire `MindmapConnectionPainter` inside `MindmapCanvas` background stack and add context menu popover for editing line options (color, arrow, style, label, delete).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/mindmap_canvas_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart test/features/mindmap/presentation/mindmap_canvas_test.dart
git commit -m "feat(mindmap): integrate connection lines rendering and context menu on canvas"
```
