import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/command/domain/quick_create_command_parser.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  test('parses a rich task command with metadata tokens', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'task Ship release #Work #launch !high due:besok on:2026-06-25 status:doing project:Launch_App area:Work',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.task);
    expect(command.title, 'Ship release');
    expect(command.tags, ['work', 'launch']);
    expect(command.priority, NodePriority.high);
    expect(command.status, NodeStatus.doing);
    expect(command.day, DateTime(2026, 6, 25));
    expect(command.dueDate, DateTime(2026, 6, 19));
    expect(command.project, 'Launch App');
    expect(command.area, 'Work');
    expect(command.label, 'Create Task: Ship release');
  });

  test('supports type aliases and defaults the node day and inbox status', () {
    final today = DateTime(2026, 6, 18);
    final defaultDay = DateTime(2026, 7, 4);

    final command = quickCreateCommandFromQuery(
      'todo Buy milk !urgent due:today',
      today: today,
      defaultDay: defaultDay,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.task);
    expect(command.title, 'Buy milk');
    expect(command.status, NodeStatus.inbox);
    expect(command.priority, NodePriority.urgent);
    expect(command.dueDate, today.dateOnly);
    expect(command.day, defaultDay.dateOnly);
  });

  test('parses progress, state flags, and checklist items', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'task Prepare launch progress:75 pin archive check:Brief_scope|Publish_notes',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.title, 'Prepare launch');
    expect(command.progress, 0.75);
    expect(command.isPinned, isTrue);
    expect(command.isArchived, isTrue);
    expect(command.checklistTitles, ['Brief scope', 'Publish notes']);
  });

  test('parses related node ids from relation modifiers', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'note Follow up rel:task-launch|goal-roadmap link:daily-note',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.title, 'Follow up');
    expect(command.relatedNodeIds, [
      'task-launch',
      'goal-roadmap',
      'daily-note',
    ]);
  });

  test('parses meeting natural date time tag and attendees', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'meeting launch tomorrow 10:00 with Maya, Rafi #work',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.event);
    expect(command.title, 'launch');
    expect(command.body, 'launch');
    expect(command.day, DateTime(2026, 6, 19));
    expect(command.tags, ['work']);
    expect(command.data['calendar_kind'], 'meeting');
    expect(command.data['agenda'], 'launch');
    expect(command.data['attendees'], 'Maya\nRafi');
    expect(command.data['time_block'], containsPair('startTime', '10:00'));
    expect(command.data['time_block'], containsPair('endTime', '11:00'));
  });

  test('parses Indonesian meeting natural date and jam time', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'meeting tim besok jam 10 #work',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.title, 'tim');
    expect(command.day, DateTime(2026, 6, 19));
    expect(command.tags, ['work']);
    expect(command.data['calendar_kind'], 'meeting');
    expect(command.data['time_block'], containsPair('startTime', '10:00'));
    expect(command.data['time_block'], containsPair('endTime', '11:00'));
  });

  test('parses reminder tanggal 5 and time', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'reminder bayar listrik tanggal 5 jam 08:00',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.task);
    expect(command.title, 'bayar listrik');
    expect(command.day, DateTime(2026, 7, 5));
    expect(command.data['calendar_kind'], 'reminder');
    expect(command.data['remindAt'], '08:00');
    expect(command.data['time_block'], containsPair('startTime', '08:00'));
    expect(command.data['time_block'], containsPair('endTime', '08:15'));
  });

  test('parses event location and time', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'event dentist tomorrow 14:00 @Clinic',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.title, 'dentist');
    expect(command.day, DateTime(2026, 6, 19));
    expect(command.data['calendar_kind'], 'event');
    expect(command.data['location'], 'Clinic');
    expect(command.data['time_block'], containsPair('startTime', '14:00'));
    expect(command.data['time_block'], containsPair('endTime', '15:00'));
  });

  test('parses metric value unit and hari ini', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'metric berat 72 kg hari ini',
      today: today,
      defaultDay: today.addDays(2),
    );

    expect(command, isNotNull);
    expect(command!.title, 'berat');
    expect(command.day, today);
    expect(command.data['calendar_kind'], 'metric');
    expect(command.data['value'], '72');
    expect(command.data['unit'], 'kg');
  });

  test('parses decision options from vs expression', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'decision pilih stack: Flutter vs React Native',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.decision);
    expect(command.title, 'pilih stack');
    expect(command.body, 'Flutter\nReact Native');
    expect(command.data['calendar_kind'], 'decision');
    expect(command.data['options'], 'Flutter\nReact Native');
    expect(command.data.containsKey('selectedOption'), isFalse);
  });

  test('builds structured expense commands', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'expense 50k lunch with team',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.expense);
    expect(command.title, 'lunch with team');
    expect(command.body, contains('Amount: 50k'));
    expect(command.body, contains('Category: lunch'));
  });

  test('builds structured contact commands', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'contact Budi email budi@mail.com',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.contact);
    expect(command.title, 'Budi');
    expect(command.body, contains('Email: budi@mail.com'));
  });

  test('builds structured bookmark commands', () {
    final today = DateTime(2026, 6, 18);

    final command = quickCreateCommandFromQuery(
      'bookmark https://example.com Flutter refs',
      today: today,
      defaultDay: today,
    );

    expect(command, isNotNull);
    expect(command!.type, NodeType.bookmark);
    expect(command.title, 'Flutter refs');
    expect(command.data['link'], {'url': 'https://example.com'});
    expect(command.body, contains('URL: https://example.com'));
  });

  test('builds question and routine structured commands', () {
    final today = DateTime(2026, 6, 18);

    final question = quickCreateCommandFromQuery(
      'question how to improve onboarding',
      today: today,
      defaultDay: today,
    );
    final routine = quickCreateCommandFromQuery(
      'routine plan day + review tasks + shutdown',
      today: today,
      defaultDay: today,
    );

    expect(question, isNotNull);
    expect(question!.type, NodeType.question);
    expect(question.body, contains('## Question'));
    expect(routine, isNotNull);
    expect(routine!.type, NodeType.routine);
    expect(routine.checklistTitles, ['plan day', 'review tasks', 'shutdown']);
  });

  test('ignores ordinary search text and invalid date commands', () {
    final today = DateTime(2026, 6, 18);

    expect(
      quickCreateCommandFromQuery(
        'Ship release',
        today: today,
        defaultDay: today,
      ),
      isNull,
    );
    expect(
      quickCreateCommandFromQuery(
        'task #work !high',
        today: today,
        defaultDay: today,
      ),
      isNull,
    );
    expect(
      quickCreateCommandFromQuery(
        'task Broken due:2026-99-99',
        today: today,
        defaultDay: today,
      ),
      isNull,
    );
    expect(
      quickCreateCommandFromQuery(
        'task Broken progress:120',
        today: today,
        defaultDay: today,
      ),
      isNull,
    );
    expect(
      quickCreateCommandFromQuery(
        'note Broken rel:|',
        today: today,
        defaultDay: today,
      ),
      isNull,
    );
  });
}
