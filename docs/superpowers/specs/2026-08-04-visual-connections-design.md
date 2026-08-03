# Design Spec: Visual Connections (Arrows & Lines)

Date: 2026-08-04  
Status: Approved  

## Overview
Enhance mindmap canvas connections in Var to match Milanote-style visual connectors. Connections support customizable line types (straight, bezier, orthogonal), stroke patterns (solid, dashed, dotted), directional arrowheads (none, target, both), custom connection colors, and midpoint text badges.

---

## 1. Domain Model (`ConnectionStyle`)

Location: `lib/features/mindmap/domain/connection_style.dart`

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

  Map<String, dynamic> toJson();
  factory ConnectionStyle.fromJson(Map<String, dynamic> json);
  ConnectionStyle copyWith({...});
}
```

### Persistence
Connection styles are stored inside `MindmapNode.data['connection_styles']` as a `Map<String, Map<String, dynamic>>` keyed by target node ID on the source node.

---

## 2. Canvas Rendering (`_ConnectionLinesPainter`)

Location: `lib/features/mindmap/presentation/mindmap_canvas.dart`

### Path Construction
1. **Bézier (Default)**: Smooth cubic Bézier curve with horizontal/vertical control point offsets based on endpoint alignment.
2. **Straight**: Direct linear path connecting source and target bounding rectangle attachment points.
3. **Orthogonal**: Right-angled 90-degree step path (L-shaped or Z-shaped depending on node alignment).

### Dash & Dot Formatting
- **Solid**: Continuous stroke.
- **Dashed**: Path metric dashes (e.g. 8px dash, 4px gap).
- **Dotted**: Path metric dots (e.g. 2px dot, 4px gap).

### Arrowhead Rendering
- Calculates end-tangent angles at start/target attachment points.
- Draws filled isosceles triangle arrowheads facing the endpoint node boundaries.

### Midpoint Label Pill
- Calculates path midpoint using `PathMetrics`.
- Draws rounded rectangle background pill with crisp text label.

---

## 3. UI Connection Style Toolbar / Popover

Location: `lib/features/mindmap/presentation/widgets/connection_style_bar.dart`

When `_selectedConnectionKey` is active on canvas:
- Shows a floating action bar near the midpoint of the selected connection line.
- Quick controls:
  - Line type selector (Bezier / Straight / Orthogonal icons)
  - Stroke pattern selector (Solid / Dashed / Dotted icons)
  - Arrowhead toggle (`->`, `<->`, `-`)
  - Accent color picker dots
  - Label editor button / inline dialog
  - Delete connection button

---

## 4. Fallback & Backward Compatibility
- Existing connections without explicit `ConnectionStyle` metadata default gracefully to `ConnectionLineType.bezier`, `ConnectionLinePattern.solid`, `ConnectionArrowhead.target`, theme outline color, and 2.0 width.

---

## 5. Testing Plan
- `test/features/mindmap/domain/connection_style_test.dart`: Serialization, deserialization, copyWith defaults self-checks.
- `test/features/mindmap/presentation/connection_style_bar_test.dart`: Toolbar widget interaction tests.
