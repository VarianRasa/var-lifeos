# Color Sticky Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `NodeType.note` to render as Milanote-style colorful Post-It sticky notes on the mindmap canvas with custom color options.

**Architecture:** Create `AppStickyColors` palette helper for 6 pastel themes. Build `StickyNoteCardWidget` visual component with double drop shadow and color switcher. Wire into `productivity_node_editors.dart` for `NodeType.note`.

**Tech Stack:** Dart 3, Flutter, Material 3.

## Global Constraints
- SDK: Dart `^3.11.4`, Flutter 3.x
- Style: Material 3 dark-first visual style, colors in `lib/core/theme/app_colors.dart`
- Analyzer: Clean `flutter analyze` with strict lints

---

### Task 1: AppStickyColors Palette Helper

**Files:**
- Create: `lib/core/theme/app_sticky_colors.dart`
- Test: `test/core/theme/app_sticky_colors_test.dart`

**Interfaces:**
- Produces: `StickyColorOption` enum with `background`, `text`, and `fromName()`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_sticky_colors.dart';

void main() {
  test('StickyColorOption maps colors and defaults correctly', () {
    final yellow = StickyColorOption.fromName('yellow');
    expect(yellow.background, const Color(0xFFFEF08A));
    expect(yellow.text, const Color(0xFF713F12));

    final blue = StickyColorOption.fromName('blue');
    expect(blue.background, const Color(0xFFBAE6FD));

    final fallback = StickyColorOption.fromName('unknown');
    expect(fallback, StickyColorOption.yellow);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/core/theme/app_sticky_colors_test.dart`  
Expected: FAIL (file missing)

- [ ] **Step 3: Implement `AppStickyColors`**

Create `lib/core/theme/app_sticky_colors.dart`:

```dart
import 'package:flutter/material.dart';

enum StickyColorOption {
  yellow(background: Color(0xFFFEF08A), text: Color(0xFF713F12)),
  blue(background: Color(0xFFBAE6FD), text: Color(0xFF0C4A6E)),
  green(background: Color(0xFFBBF7D0), text: Color(0xFF14532D)),
  pink(background: Color(0xFFFBCFE8), text: Color(0xFF831843)),
  purple(background: Color(0xFFE9D5FF), text: Color(0xFF581C87)),
  orange(background: Color(0xFFFFEDD5), text: Color(0xFF7C2D12));

  final Color background;
  final Color text;

  const StickyColorOption({
    required this.background,
    required this.text,
  });

  static StickyColorOption fromName(String? name) {
    return values.firstWhere(
      (e) => e.name == name,
      orElse: () => yellow,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/theme/app_sticky_colors_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_sticky_colors.dart test/core/theme/app_sticky_colors_test.dart
git commit -m "feat: add AppStickyColors palette helper"
```

---

### Task 2: StickyNoteCardWidget Component

**Files:**
- Create: `lib/features/mindmap/presentation/widgets/sticky_note_card_widget.dart`
- Test: `test/features/mindmap/presentation/widgets/sticky_note_card_widget_test.dart`

**Interfaces:**
- Consumes: `StickyColorOption` from Task 1

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_sticky_colors.dart';
import 'package:var_app/features/mindmap/presentation/widgets/sticky_note_card_widget.dart';

void main() {
  testWidgets('StickyNoteCardWidget renders title, body, and color theme', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StickyNoteCardWidget(
            title: 'Meeting Ideas',
            body: 'Brainstorm session at 3 PM',
            colorOption: StickyColorOption.yellow,
          ),
        ),
      ),
    );

    expect(find.text('Meeting Ideas'), findsOneWidget);
    expect(find.text('Brainstorm session at 3 PM'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `flutter test test/features/mindmap/presentation/widgets/sticky_note_card_widget_test.dart`  
Expected: FAIL (file missing)

- [ ] **Step 3: Implement `StickyNoteCardWidget`**

Create `lib/features/mindmap/presentation/widgets/sticky_note_card_widget.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_sticky_colors.dart';

class StickyNoteCardWidget extends StatelessWidget {
  final String title;
  final String body;
  final StickyColorOption colorOption;
  final ValueChanged<StickyColorOption>? onColorChanged;

  const StickyNoteCardWidget({
    super.key,
    required this.title,
    required this.body,
    required this.colorOption,
    this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      minHeight: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorOption.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.push_pin_outlined,
                size: 16,
                color: colorOption.text.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Note' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorOption.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (onColorChanged != null)
                PopupMenuButton<StickyColorOption>(
                  icon: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: colorOption.text.withValues(alpha: 0.7),
                  ),
                  onSelected: onColorChanged,
                  itemBuilder: (context) => [
                    for (final opt in StickyColorOption.values)
                      PopupMenuItem(
                        value: opt,
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: opt.background,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black26),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(opt.name),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              body.isEmpty ? 'No details' : body,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorOption.text.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/mindmap/presentation/widgets/sticky_note_card_widget_test.dart`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/mindmap/presentation/widgets/sticky_note_card_widget.dart test/features/mindmap/presentation/widgets/sticky_note_card_widget_test.dart
git commit -m "feat: add StickyNoteCardWidget Post-It visual card component"
```

---

### Task 3: Wire Sticky Note Renderers into Mindmap

**Files:**
- Modify: `lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart`

- [ ] **Step 1: Check baseline health**

Run: `flutter analyze`  
Expected: 0 issues

- [ ] **Step 2: Update `_NoteContent` to use `StickyNoteCardWidget`**

Update `productivity_node_editors.dart`:
1. Parse `StickyColorOption` from `node.data['stickyColor']`.
2. Return `StickyNoteCardWidget` for `NodeType.note`.
3. Provide `onColorChanged` callback to update `node.data['stickyColor']`.

- [ ] **Step 3: Run analyze & test suite**

Run: `flutter analyze`  
Run: `flutter test`  
Expected: All tests PASS, clean analyze.

- [ ] **Step 4: Commit & Auto-Push**

```bash
git add lib/features/mindmap/presentation/node_editors/productivity_node_editors.dart
git commit -m "feat: render NodeType.note as color sticky notes on canvas"
git push origin feature/life-os-core
```
