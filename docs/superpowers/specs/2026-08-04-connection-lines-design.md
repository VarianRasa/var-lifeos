# Design Spec: Connection Lines & Arrows

## Overview
Adds customizable connection lines and arrows to the `MindmapCanvas` in `var_app`. Connection lines can connect two nodes, a node and a free canvas point, or two free canvas points. They adjust dynamically when connected nodes move and feature smart Bezier curve routing to avoid visually obscuring node centers.

## 1. Data Structure & Domain Model
Connections are saved as mindmap nodes with `type = NodeType.connection` (or parsed metadata).

### Metadata Schema (`MindmapNode.data`)
- `startNodeId` (`String?`): Source node ID, or `null` if absolute point.
- `startPoint` (`Map<String, double>`: `{'x': double, 'y': double}`): Canvas offset for source point when unattached or fallback.
- `endNodeId` (`String?`): Target node ID, or `null` if absolute point.
- `endPoint` (`Map<String, double>`: `{'x': double, 'y': double}`): Canvas offset for target point when unattached or fallback.
- `lineStyle` (`String`): `'solid'`, `'dashed'`, or `'dotted'` (default: `'solid'`).
- `arrowStyle` (`String`): `'none'`, `'end'`, or `'both'` (default: `'end'`).
- `color` (`String`): Color key or hex string (default: `'slate'`).
- `label` (`String?`): Optional text label displayed along the midpoint.

## 2. Rendering & Smart Bezier Routing
- Integrated into `MindmapCanvas` background painter (`MindmapConnectionPainter`).
- **Edge Anchor Snapping**: Calculates optimal bounding box perimeter attachment point for source/target nodes.
- **Smart Bezier Curve**: Computes control points based on vector direction between source and target anchors to draw clean, curved paths using Flutter `Path.cubicTo`.
- **Arrows & Label**: Rendered at curve endpoints with proper tangent angle rotation; midpoint text pill rendered over line.

## 3. Interaction & Context Toolbar
- **Creation**: Drag from node edge handles or select Connection Tool from canvas toolbar.
- **Selection & Editing**: Tapping a line selects it and displays a floating context toolbar:
  - Color palette selection.
  - Line style picker (`solid`, `dashed`, `dotted`).
  - Arrow style picker (`none`, `end`, `both`).
  - Inline label editor.
  - Delete button.
- **Endpoint Dragging**: Interactive drag handles at start and end points allow re-anchoring to other nodes or free canvas points.

## 4. Verification & Testing
- Unit tests for connection data parsing and anchor position calculations.
- Widget tests verifying painter rendering, selection handles, and connection deletion.
