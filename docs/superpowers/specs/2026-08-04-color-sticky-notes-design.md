# Design Spec: Color Sticky Notes (`NodeType.note`)

Date: 2026-08-04  
Status: Approved  

## Overview
Upgrade `NodeType.note` to render as Milanote-style colorful Post-It sticky notes on the mindmap canvas. Supports 6 distinct pastel color themes with matching high-contrast text colors, subtle paper drop shadows, and inline color selector.

---

## 1. Sticky Color Palette (`AppStickyColors`)

Location: `lib/core/theme/app_sticky_colors.dart`

```dart
enum StickyColorOption {
  yellow(background: Color(0xFFFEF08A), text: Color(0xFF713F12)),
  blue(background: Color(0xFFBAE6FD), text: Color(0xFF0C4A6E)),
  green(background: Color(0xFFBBF7D0), text: Color(0xFF14532D)),
  pink(background: Color(0xFFFBCFE8), text: Color(0xFF831843)),
  purple(background: Color(0xFFE9D5FF), text: Color(0xFF581C87)),
  orange(background: Color(0xFFFFEDD5), text: Color(0xFF7C2D12));

  final Color background;
  final Color text;
  const StickyColorOption({required this.background, required this.text});

  static StickyColorOption fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => yellow);
}
```

---

## 2. Visual Component (`StickyNoteCardWidget`)

Location: `lib/features/mindmap/presentation/widgets/sticky_note_card_widget.dart`

Card layout for `NodeType.note`:
- Background: `option.background` with 12px border radius.
- Shadow: Double subtle offset shadow for paper effect.
- Header: Small pin icon + quick color selector dots when selected.
- Body: Title + body text rendered in `option.text` color.

---

## 3. Node Integration & Storage
- Stored in `MindmapNode.data['stickyColor']` (e.g. `'yellow'`, `'blue'`).
- Integrated into `productivity_node_editors.dart` for `NodeType.note`.

---

## 4. Testing Plan
- `test/core/theme/app_sticky_colors_test.dart`: Test color mapping and fallback.
- `test/features/mindmap/presentation/widgets/sticky_note_card_widget_test.dart`: Widget test for colors and text rendering.
