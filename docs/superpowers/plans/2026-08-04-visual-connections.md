# Visual Connections (Arrows & Lines) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement customizable Milanote-style visual connection lines (line types, stroke patterns, arrowheads, colors, and midpoint labels) for the Var mindmap canvas.

**Architecture:** Create `ConnectionStyle` domain model with Sembast serialization inside `MindmapNode.data['connection_styles']`. Upgrade `_ConnectionLinesPainter` in `mindmap_canvas.dart` to calculate straight/bezier/orthogonal paths, dashed/dotted effects, arrowheads, and label badges. Create `ConnectionStyleBar` floating toolbar widget for connection styling.

**Tech Stack:** Dart 3, Flutter, Material 3, Sembast, Riverpod.

## Global Constraints
- SDK: Dart `^3.11.4`, Flutter 3.x
- Style: Material 3 dark-first visual style, colors in `lib/core/theme/app_colors.dart`
- Analyzer: Clean `flutter analyze` with strict lints

---

### Task 1: ConnectionStyle Domain Model & Serialization

**Files:**
- Create: `lib/features/mindmap/domain/connection_style.dart`
- Test: `test/features/mindmap/domain/connection_style_test.dart`

**Interfaces:**
- Produces: `ConnectionStyle`, `ConnectionLineType`, `ConnectionLinePattern`, `ConnectionArrowhead`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/connection_style.dart';

void main() {
  test('ConnectionStyle json serialization & copyWith', () {
    const style = ConnectionStyle(
      lineType: ConnectionLineType.orthogonal,
      linePattern: ConnectionLinePattern.dashed,
      arrowhead: ConnectionArrowhead.both,
      colorHex: '#6366F1',
      strokeWidth: 3.0,
      label: 'Depends on',
    );

    final json = style.toJson();
    expect(json['lineType'], 'orthogonal');
    expect(json['linePattern'], 'dashed');
    expect(json['arrowhead'], 'both');
    expect(json['colorHex'], '#6366F1');
    expect(json['strokeWidth'], 3.0);
    expect(json['label'], 'Depends on');

    final parsed = ConnectionStyle.fromJson(json);
    expect(parsed, equals(style));

    final copy = style.copyWith(linePattern: ConnectionLinePattern.solid);
    expect(copy.linePattern, ConnectionLinePattern.solid);
    expect(copy.lineType, ConnectionLineType.orthogonal);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/domain/connection_style_test.dart`  
Expected: FAIL (file does not exist)

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/mindmap/domain/connection_style.dart`:

```dart
enum ConnectionLineType { bezier, straight, orthogonal }

enum ConnectionLinePattern { solid, dashed, dotted }

enum ConnectionArrowhead { target, both, none }

class ConnectionStyle {
  final ConnectionLineType lineType;
  final ConnectionLinePattern linePattern;
  final ConnectionArrowhead arrowhead;
  final String? colorHex;
  final double strokeWidth;
  final String? label;

  const ConnectionStyle({
    this.lineType = ConnectionLineType.bezier,
    this.linePattern = ConnectionLinePattern.solid,
    this.arrowhead = ConnectionArrowhead.target,
    this.colorHex,
    this.strokeWidth = 2.0,
    this.label,
  });

  Map<String, dynamic> toJson() => {
        'lineType': lineType.name,
        'linePattern': linePattern.name,
        'arrowhead': arrowhead.name,
        'colorHex': colorHex,
        'strokeWidth': strokeWidth,
        'label': label,
      };

  factory ConnectionStyle.fromJson(Map<String, dynamic> json) {
    return ConnectionStyle(
      lineType: ConnectionLineType.values.firstWhere(
        (e) => e.name == json['lineType'],
        orElse: () => ConnectionLineType.bezier,
      ),
      linePattern: ConnectionLinePattern.values.firstWhere(
        (e) => e.name == json['linePattern'],
        orElse: () => ConnectionLinePattern.solid,
      ),
      arrowhead: ConnectionArrowhead.values.firstWhere(
        (e) => e.name == json['arrowhead'],
        orElse: () => ConnectionArrowhead.target,
      ),
      colorHex: json['colorHex'] as String?,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      label: json['label'] as String?,
    );
  }

  ConnectionStyle copyWith({
    ConnectionLineType? lineType,
    ConnectionLinePattern? linePattern,
    ConnectionArrowhead? arrowhead,
    String? colorHex,
    double? strokeWidth,
    String? label,
  }) {
    return ConnectionStyle(
      lineType: lineType ?? this.lineType,
      linePattern: linePattern ?? this.linePattern,
      arrowhead: arrowhead ?? this.arrowhead,
      colorHex: colorHex ?? this.colorHex,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStyle &&
          runtimeType == other.runtimeType &&
          lineType == other.lineType &&
          linePattern == other.linePattern &&
          arrowhead == other.arrowhead &&
          colorHex == other.colorHex &&
          strokeWidth == other.strokeWidth &&
          label == other.label;

  @override
  int get hashCode =>
      lineType.hashCode ^
      linePattern.hashCode ^
      arrowhead.hashCode ^
      colorHex.hashCode ^
      strokeWidth.hashCode ^
      label.hashCode;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/domain/connection_style_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/domain/connection_style.dart test/features/mindmap/domain/connection_style_test.dart
git commit -m "feat: add ConnectionStyle domain model and serialization"
```

---

### Task 2: Floating Connection Style Bar Widget

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/connection_style_bar.dart`
- Test: `test/features/mindmap/presentation/widgets/connection_style_bar_test.dart`

**Interfaces:**
- Consumes: `ConnectionStyle` from Task 1

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/connection_style.dart';
import 'package:var_app/features/mindmap/presentation/widgets/connection_style_bar.dart';

void main() {
  testWidgets('ConnectionStyleBar renders and triggers callbacks', (tester) async {
    ConnectionStyle currentStyle = const ConnectionStyle();
    bool deletePressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionStyleBar(
            style: currentStyle,
            onStyleChanged: (newStyle) => currentStyle = newStyle,
            onDelete: () => deletePressed = true,
          ),
        ),
      ),
    );

    expect(find.byType(ConnectionStyleBar), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    expect(deletePressed, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/mindmap/presentation/widgets/connection_style_bar_test.dart`  
Expected: FAIL (file does not exist)

- [ ] **Step 3: Write minimal implementation**

Create `lib/features/mindmap/presentation/widgets/connection_style_bar.dart`:

```dart
import 'package:flutter/material.dart';
import '../../domain/connection_style.dart';

class ConnectionStyleBar extends StatelessWidget {
  final ConnectionStyle style;
  final ValueChanged<ConnectionStyle> onStyleChanged;
  final VoidCallback onDelete;

  const ConnectionStyleBar({
    super.key,
    required this.style,
    required this.onStyleChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Line type menu
          PopupMenuButton<ConnectionLineType>(
            icon: Icon(
              switch (style.lineType) {
                ConnectionLineType.bezier => Icons.gesture,
                ConnectionLineType.straight => Icons.show_chart,
                ConnectionLineType.orthogonal => Icons.alt_route,
              },
              size: 18,
            ),
            tooltip: 'Line Style',
            onSelected: (type) => onStyleChanged(style.copyWith(lineType: type)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ConnectionLineType.bezier,
                child: Text('Curved (Bézier)'),
              ),
              const PopupMenuItem(
                value: ConnectionLineType.straight,
                child: Text('Straight'),
              ),
              const PopupMenuItem(
                value: ConnectionLineType.orthogonal,
                child: Text('Orthogonal (90°)'),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Pattern menu
          PopupMenuButton<ConnectionLinePattern>(
            icon: Icon(
              style.linePattern == ConnectionLinePattern.solid
                  ? Icons.line_weight
                  : Icons.more_horiz,
              size: 18,
            ),
            tooltip: 'Stroke Pattern',
            onSelected: (pattern) => onStyleChanged(style.copyWith(linePattern: pattern)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ConnectionLinePattern.solid,
                child: Text('Solid'),
              ),
              const PopupMenuItem(
                value: ConnectionLinePattern.dashed,
                child: Text('Dashed'),
              ),
              const PopupMenuItem(
                value: ConnectionLinePattern.dotted,
                child: Text('Dotted'),
              ),
            ],
          ),
          const SizedBox(width: 4),

          // Arrowhead toggle
          IconButton(
            icon: Icon(
              switch (style.arrowhead) {
                ConnectionArrowhead.target => Icons.east,
                ConnectionArrowhead.both => Icons.sync_alt,
                ConnectionArrowhead.none => Icons.horizontal_rule,
              },
              size: 18,
            ),
            tooltip: 'Arrowhead',
            onPressed: () {
              final next = switch (style.arrowhead) {
                ConnectionArrowhead.target => ConnectionArrowhead.both,
                ConnectionArrowhead.both => ConnectionArrowhead.none,
                ConnectionArrowhead.none => ConnectionArrowhead.target,
              };
              onStyleChanged(style.copyWith(arrowhead: next));
            },
          ),
          const SizedBox(width: 4),

          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete Connection',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/widgets/connection_style_bar_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/widgets/connection_style_bar.dart test/features/mindmap/presentation/widgets/connection_style_bar_test.dart
git commit -m "feat: add ConnectionStyleBar floating toolbar widget"
```

---

### Task 3: Canvas Painter Connection Style Rendering

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Test: `test/features/mindmap/presentation/mindmap_canvas_test.dart`

**Interfaces:**
- Consumes: `ConnectionStyle` from Task 1, `ConnectionStyleBar` from Task 2

- [ ] **Step 1: Run analyze & tests to ensure baseline health**

Run: `flutter analyze`  
Expected: 0 issues

- [ ] **Step 2: Integrate ConnectionStyle in `_ConnectionLinesPainter` & toolbar**

Update `mindmap_canvas.dart`:
1. Parse `ConnectionStyle` from `sourceNode.data['connection_styles'][targetId]`.
2. Compute `Path` based on `ConnectionLineType` (Straight, Bezier, Orthogonal).
3. Render dashed/dotted patterns if specified in `ConnectionLinePattern`.
4. Draw start/target arrowheads based on `ConnectionArrowhead`.
5. Display floating `ConnectionStyleBar` overlay near connection midpoint when `_selectedConnectionKey` is active.

- [ ] **Step 3: Run analyze & test suite**

Run: `flutter analyze`  
Run: `flutter test`  
Expected: All tests PASS, clean analyze.

- [ ] **Step 4: Commit**

```bash
git add lib/features/mindmap/presentation/mindmap_canvas.dart
git commit -m "feat: integrate connection styling, arrowheads, and style bar on canvas"
```

---
