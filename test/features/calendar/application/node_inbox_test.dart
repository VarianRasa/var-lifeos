import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/application/node_inbox.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  MindmapNode node(
    String id, {
    required DateTime day,
    bool inbox = false,
    bool archived = false,
  }) {
    return MindmapNode.create(
      id: id,
      type: NodeType.note,
      title: id,
      day: day,
      isArchived: archived,
      data: {if (inbox) inboxNodeDataKey: true},
      now: day,
    );
  }

  test('inboxNodesForDay returns active inbox nodes up to selected day', () {
    final selectedDay = DateTime(2026, 7, 2);
    final nodes = [
      node('old', day: DateTime(2026, 7, 1), inbox: true),
      node('today', day: selectedDay, inbox: true),
      node('future', day: DateTime(2026, 7, 3), inbox: true),
      node('normal', day: selectedDay),
      node('archived', day: selectedDay, inbox: true, archived: true),
    ];

    expect(inboxNodesForDay(nodes, selectedDay).map((item) => item.id), [
      'old',
      'today',
    ]);
  });

  test('assignInboxNodeToDay clears inbox marker and makes item next', () {
    final original = node('capture', day: DateTime(2026, 7), inbox: true);

    final assigned = assignInboxNodeToDay(original, DateTime(2026, 7, 2));

    expect(assigned.day, DateTime(2026, 7, 2));
    expect(assigned.status, NodeStatus.next);
    expect(isInboxNode(assigned), isFalse);
    expect(
      assigned.data[inboxAssignedFromDataKey],
      original.day.toIso8601String(),
    );
  });

  test('markInboxNode keeps inbox marker and workflow status synchronized', () {
    final original = node('capture', day: DateTime(2026, 7));

    final inbox = markInboxNode(original, isInbox: true);
    final clarified = markInboxNode(inbox, isInbox: false);

    expect(inbox.status, NodeStatus.inbox);
    expect(isInboxNode(inbox), isTrue);
    expect(clarified.status, NodeStatus.next);
    expect(isInboxNode(clarified), isFalse);
  });

  test('deferInboxNode removes item from inbox as someday', () {
    final original = node('capture', day: DateTime(2026, 7), inbox: true);

    final deferred = deferInboxNode(original);

    expect(deferred.status, NodeStatus.someday);
    expect(isInboxNode(deferred), isFalse);
  });
}
