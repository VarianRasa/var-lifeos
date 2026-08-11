import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/presentation/widgets/wikilink_autocomplete_text_field.dart';

void main() {
  testWidgets('inserts selected node as a bracketed WikiLink', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var changedValue = '';
    final target = MindmapNode.create(
      id: 'target',
      type: NodeType.goal,
      title: 'Health Goal',
      day: DateTime(2026, 8, 7),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allMindmapNodesProvider.overrideWith((ref) async => [target]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WikiLinkAutocompleteTextField(
              controller: controller,
              onChanged: (value) => changedValue = value,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'See [[Health');
    await tester.pumpAndSettle();

    expect(find.text('Health Goal'), findsOneWidget);
    await tester.tap(find.text('Health Goal'));
    await tester.pumpAndSettle();

    expect(controller.text, 'See [[Health Goal]]');
    expect(changedValue, 'See [[Health Goal]]');
  });
}
