import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/note_node_editor.dart';

void main() {
  testWidgets('note color updates payload and visible editor tint', (
    tester,
  ) async {
    await tester.pumpWidget(const _NoteEditorHarness());
    final before = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('note-node-editor')),
    );

    await tester.tap(find.byTooltip('Note color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('violet'));
    await tester.pumpAndSettle();

    final harness = tester.state<_NoteEditorHarnessState>(
      find.byType(_NoteEditorHarness),
    );
    final after = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('note-node-editor')),
    );
    expect(harness.payload.color, 'violet');
    expect(
      (after.decoration! as BoxDecoration).color,
      isNot((before.decoration! as BoxDecoration).color),
    );
  });

  testWidgets('note tags support add edit delete and deduplication', (
    tester,
  ) async {
    await tester.pumpWidget(const _NoteEditorHarness());
    final input = find.byKey(const ValueKey<String>('note-tag-input'));

    await tester.ensureVisible(input);
    await tester.enterText(input, '#Research');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-tag-research')),
      findsOneWidget,
    );

    await tester.enterText(input, 'research');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final harness = tester.state<_NoteEditorHarnessState>(
      find.byType(_NoteEditorHarness),
    );
    expect(harness.node.tags, <String>['research']);

    await tester.tap(find.byKey(const ValueKey<String>('note-tag-research')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('note-tag-edit-field')),
      'Reference',
    );
    await tester.tap(find.byKey(const ValueKey<String>('note-tag-edit-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-tag-reference')),
      findsOneWidget,
    );

    tester
        .widget<InputChip>(
          find.byKey(const ValueKey<String>('note-tag-reference')),
        )
        .onDeleted!();
    await tester.pump();
    expect(harness.node.tags, isEmpty);
  });
}

final class _NoteEditorHarness extends StatefulWidget {
  const _NoteEditorHarness();

  @override
  State<_NoteEditorHarness> createState() => _NoteEditorHarnessState();
}

final class _NoteEditorHarnessState extends State<_NoteEditorHarness> {
  late MindmapNode node = MindmapNode.create(
    id: 'note',
    type: NodeType.note,
    title: 'Knowledge note',
    body: '# Heading',
    day: DateTime(2026, 7, 16),
  );
  NotePayload payload = const NotePayload();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.purple),
    home: Scaffold(
      body: SizedBox(
        width: 780,
        height: 720,
        child: NoteNodeEditor(
          node: node,
          payload: payload,
          onTitleChanged: (value) =>
              setState(() => node = node.copyWith(title: value)),
          onBodyChanged: (value) =>
              setState(() => node = node.copyWith(body: value)),
          onPayloadChanged: (value) => setState(() => payload = value),
          onNodeChanged: (value) => setState(() => node = value),
        ),
      ),
    ),
  );
}
