# Creative Studio Canvas (Milanote + Procreate + Gendo AI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform Var from a 30+ rigid LifeOS node-type app into an expressive Creative Studio Canvas combining Milanote (spatial boards, visual cards, nested boards), Procreate/IbisPaint (multi-layer vector & raster drawing engine, brushes, color picker, eraser), and Gendo AI (sketch-to-photorealistic render, style transfer, and material iteration node).

**Architecture:** 
- Unified spatial canvas data model using `CanvasObjectType` and streamlined `NodeType` (Card, Sketch, Media, Frame/Board, Connector, GendoAiNode).
- Standalone multi-layer digital drawing engine (`DrawingLayerManager`, `BrushEngine`, `CanvasBrushStyle`) integrated with Flutter `CustomPainter`.
- Gendo AI studio node widget and client service supporting sketch input, style presets, negative prompts, and iteration history on the canvas.
- Milanote spatial sidebar & quick draggable tool palette.

**Tech Stack:** Flutter 3.11+, Riverpod 2.6+, Sembast DB, `desktop_drop`, `cross_file`.

## Global Constraints
- Material 3 dark-first visual style.
- Pure Dart entities in domain layers, no Flutter dependencies in pure logic.
- Backward compatibility: existing legacy nodes automatically load and display cleanly as unified visual cards without data loss.

---

### Task 1: Drawing Layer Manager & Brush Engine (Procreate / IbisPaint Model)

**Files:**
- Create: `lib/features/mindmap/domain/canvas_drawing_layer.dart`
- Create: `lib/features/mindmap/domain/canvas_brush_engine.dart`
- Test: `test/features/mindmap/domain/canvas_drawing_layer_test.dart`

**Interfaces:**
- Consumes: Dart core primitives, `Offset` / Point math.
- Produces: `CanvasDrawingStroke`, `CanvasDrawingLayer`, `CanvasBrushType` (pencil, ink, marker, highlighter, airbrush, eraser), `DrawingLayerManager`.

- [ ] **Step 1: Write the failing unit tests for Drawing Layer & Brush Engine**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement `CanvasDrawingLayer`, `CanvasBrushEngine`, and `DrawingLayerManager`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 2: Gendo AI Studio Node Domain & Service

**Files:**
- Create: `lib/features/mindmap/domain/gendo_ai_node.dart`
- Create: `lib/features/mindmap/application/gendo_ai_service.dart`
- Test: `test/features/mindmap/domain/gendo_ai_node_test.dart`

**Interfaces:**
- Consumes: Image payload, prompt data, render style presets.
- Produces: `GendoAiRenderRequest`, `GendoAiRenderResult`, `GendoAiNodeData`, `GendoAiService`.

- [ ] **Step 1: Write failing unit test for Gendo AI model and service**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `GendoAiNodeData` and `GendoAiService`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 3: Drawing Studio Canvas Overlay & Brush Settings Bar

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/drawing_studio_overlay.dart`
- Create: `lib/features/mindmap/presentation/widgets/brush_palette_bar.dart`
- Create: `lib/features/mindmap/presentation/widgets/drawing_layer_panel.dart`
- Test: `test/features/mindmap/presentation/widgets/drawing_studio_overlay_test.dart`

**Interfaces:**
- Consumes: `DrawingLayerManager`, `CanvasBrushEngine`.
- Produces: Visual studio overlay for multi-layer sketching with brush selection, pressure/size sliders, color wheel, and layer manager.

- [ ] **Step 1: Write failing widget test for Drawing Studio Overlay**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `DrawingStudioOverlay`, `BrushPaletteBar`, and `DrawingLayerPanel`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 4: Gendo AI Interactive Studio Canvas Card

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/gendo_ai_canvas_card.dart`
- Test: `test/features/mindmap/presentation/widgets/gendo_ai_canvas_card_test.dart`

**Interfaces:**
- Consumes: `GendoAiNodeData`, `GendoAiService`.
- Produces: Interactive canvas node with sketch input, prompt input, photorealistic style toggle, generate button, and image history viewer.

- [ ] **Step 1: Write failing widget test for Gendo AI Canvas Card**
- [ ] **Step 2: Run test to verify failure**
- [ ] **Step 3: Implement `GendoAiCanvasCard`**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit changes**

---

### Task 5: Integration into Mindmap Canvas & Milanote Studio Sidebar

**Files:**
- Modify: `lib/features/mindmap/presentation/mindmap_canvas.dart`
- Modify: `lib/features/mindmap/presentation/widgets/milanote_element_palette.dart`
- Test: `test/features/mindmap/presentation/canvas_milanote_features_test.dart`

**Interfaces:**
- Consumes: Drawing studio overlay, Gendo AI card, Milanote draggable palette.
- Produces: Integrated spatial creative canvas supporting instant sketching, AI generation, and card manipulation.

- [ ] **Step 1: Update MilanoteElementPalette to include Sketch and Gendo AI items**
- [ ] **Step 2: Integrate Drawing Studio layer mode and Gendo AI node rendering in `MindmapCanvas`**
- [ ] **Step 3: Run comprehensive widget tests**
- [ ] **Step 4: Run `flutter analyze` and `flutter test`**
- [ ] **Step 5: Commit changes**
