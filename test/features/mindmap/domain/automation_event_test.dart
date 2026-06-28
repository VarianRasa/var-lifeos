import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/automation_event.dart';

void main() {
  test('automation events are stored as hidden archived nodes', () {
    final eventNode = createAutomationEventNode(
      id: 'pause-duplicates-1',
      type: AutomationEventType.pauseDuplicateRules,
      title: 'Paused duplicate automation rules',
      message: 'Paused Daily startup copy to resolve duplicate Daily plan.',
      day: DateTime(2026, 6, 24),
      occurredAt: DateTime(2026, 6, 24, 9, 30),
      affectedRuleNodeIds: const ['automation-rule-daily-startup-copy'],
      affectedLabels: const ['Daily startup copy'],
    );

    expect(eventNode.id, 'automation-event-pause-duplicates-1');
    expect(eventNode.isArchived, isTrue);
    expect(eventNode.tags, containsAll(['automation', 'automation-event']));
    expect(eventNode.data['automationEvent'], {
      'id': 'pause-duplicates-1',
      'type': 'pauseDuplicateRules',
      'title': 'Paused duplicate automation rules',
      'message': 'Paused Daily startup copy to resolve duplicate Daily plan.',
      'occurredAt': '2026-06-24T09:30:00.000',
      'affectedRuleNodeIds': ['automation-rule-daily-startup-copy'],
      'affectedLabels': ['Daily startup copy'],
    });

    final events = automationEventsFromNodes([eventNode]);

    expect(events, hasLength(1));
    expect(events.single.nodeId, eventNode.id);
    expect(events.single.type, AutomationEventType.pauseDuplicateRules);
    expect(events.single.title, 'Paused duplicate automation rules');
    expect(events.single.affectedLabels, ['Daily startup copy']);
  });

  test('automation events are listed newest first', () {
    final olderEvent = createAutomationEventNode(
      id: 'older',
      type: AutomationEventType.pauseDuplicateRules,
      title: 'Older event',
      message: 'Older',
      day: DateTime(2026, 6, 24),
      occurredAt: DateTime(2026, 6, 24, 8),
    );
    final newerEvent = createAutomationEventNode(
      id: 'newer',
      type: AutomationEventType.pauseDuplicateRules,
      title: 'Newer event',
      message: 'Newer',
      day: DateTime(2026, 6, 24),
      occurredAt: DateTime(2026, 6, 24, 10),
    );

    final events = automationEventsFromNodes([olderEvent, newerEvent]);

    expect(events.map((event) => event.id), ['newer', 'older']);
  });
}
