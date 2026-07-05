import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_knowledge_index.dart';

void main() {
  test(
    'NodeKnowledgeIndex computes outgoing backlinks mentions and broken ids',
    () {
      final day = DateTime(2026, 7);
      final current = MindmapNode.create(
        id: 'current',
        type: NodeType.note,
        title: 'Daily Review',
        day: day,
        body: 'Review Health Goal and [[Existing Link]]',
        relatedNodeIds: const ['existing', 'missing'],
      );
      final existing = MindmapNode.create(
        id: 'existing',
        type: NodeType.note,
        title: 'Existing Link',
        day: day,
      );
      final mention = MindmapNode.create(
        id: 'mention',
        type: NodeType.goal,
        title: 'Health Goal',
        day: day,
      );
      final backlink = MindmapNode.create(
        id: 'backlink',
        type: NodeType.plan,
        title: 'Weekly Plan',
        day: day,
        body: 'See [[Daily Review]]',
        relatedNodeIds: const ['current'],
      );

      final links = NodeKnowledgeIndex([
        current,
        existing,
        mention,
        backlink,
      ]).linksFor('current');

      expect(links.outgoingNodes.map((node) => node.id), ['existing']);
      expect(links.brokenOutgoingIds, ['missing']);
      expect(links.backlinks.single.node.id, 'backlink');
      expect(links.backlinks.single.reasonLabel, 'relation + [[link]]');
      expect(links.unlinkedMentions.map((node) => node.id), ['mention']);
    },
  );

  test('bodyWithLinkedTitle converts first plain mention only', () {
    expect(
      bodyWithLinkedTitle('Health Goal and Health Goal', 'Health Goal'),
      '[[Health Goal]] and Health Goal',
    );
    expect(
      bodyWithLinkedTitle('Already [[Health Goal]]', 'Health Goal'),
      'Already [[Health Goal]]',
    );
  });
}
