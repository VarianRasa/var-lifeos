import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/markdown_checklist_parser.dart';

void main() {
  test('parseMarkdownChecklist extracts checked and unchecked items', () {
    final items = parseMarkdownChecklist('''
Intro
- [ ] Draft spec
- [x] Ship patch
* [X] Review result
+ [ ] Follow up
''');

    expect(items.map((item) => item.title), [
      'Draft spec',
      'Ship patch',
      'Review result',
      'Follow up',
    ]);
    expect(items.map((item) => item.isDone), [false, true, true, false]);
  });

  test('parseMarkdownChecklist ignores normal bullets', () {
    final items = parseMarkdownChecklist('''
- normal bullet
- [] malformed
- [ ]
''');

    expect(items, isEmpty);
  });
}
