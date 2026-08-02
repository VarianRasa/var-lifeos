import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/search/application/search_document_projector.dart';

void main() {
  test('projects user-facing node fields without internal secrets', () {
    final node = MindmapNode.create(
      id: 'n1',
      type: NodeType.note,
      title: 'Launch plan',
      body: 'Prepare release',
      day: DateTime(2026, 8, 3),
      project: 'Var',
      tags: const ['beta'],
      data: const {'caption': 'Milestone', 'apiKey': 'do-not-index'},
      now: DateTime.utc(2026, 8, 3),
    );

    final result = const SearchDocumentProjector().projectNode(
      node,
      workspaceId: 'daily',
    );

    expect(result.single.text, contains('Launch plan'));
    expect(result.single.text, contains('Milestone'));
    expect(result.single.text, isNot(contains('do-not-index')));
  });
}
