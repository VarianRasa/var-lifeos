import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/calendar/domain/calendar_node_payload.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/presentation/add_node_dialog.dart';

void main() {
  testWidgets('Node editor switches rich sections for each node type', (
    tester,
  ) async {
    await _pumpDialogHost(tester);
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('add-node-checklist-field')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-kanban')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-kanban-cards-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('add-node-checklist-field')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-habit')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-habit-recurrence-daily')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-goal')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-goal-milestones-field')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-plan')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-plan-steps-field')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-note')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-note-source-field')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-node-type-journal')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('add-node-journal-mood-field')),
      findsOneWidget,
    );
  });

  testWidgets('Node editor returns kanban board data from the kanban section', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-node-type-kanban')));
    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Release board',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-kanban-cards-field')),
      'Draft copy\nQA smoke test\nShip release',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.type, NodeType.kanban);
    final board = KanbanBoard.fromNodeData(draft!.data);
    expect(board.cards.map((card) => card.title), [
      'Draft copy',
      'QA smoke test',
      'Ship release',
    ]);
  });

  testWidgets('Node editor returns related node ids from the relation field', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Connected task',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-related-ids-field')),
      'note-1, goal-1\nnote-1',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.relatedNodeIds, ['note-1', 'goal-1']);
  });

  testWidgets('Node editor returns project and area context fields', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Scoped task',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-project-field')),
      'Launch App',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-area-field')),
      'Work Ops',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.project, 'Launch App');
    expect(draft?.area, 'Work Ops');
  });

  testWidgets('Node editor returns habit completions from the habit section', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-node-type-habit')));
    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Workout',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-habit-completions-field')),
      '2026-06-16\n2026-06-17\n2026-06-18',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.data['habit'], {
      'recurrence': 'daily',
      'target': '',
      'completions': ['2026-06-16', '2026-06-17', '2026-06-18'],
    });
  });

  testWidgets('Node editor returns completed goal milestones', (tester) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-node-type-goal')));
    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Launch v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-goal-milestones-field')),
      'Prototype\nBeta',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-goal-completed-milestones-field')),
      'Prototype',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.data['goal'], {
      'milestones': ['Prototype', 'Beta'],
      'completedMilestones': ['Prototype'],
    });
  });

  testWidgets('Node editor returns completed plan steps', (tester) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-node-type-plan')));
    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Sprint plan',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-plan-steps-field')),
      'Scope\nBuild',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-plan-completed-steps-field')),
      'Scope',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.data['plan'], {
      'steps': ['Scope', 'Build'],
      'completedSteps': ['Scope'],
    });
  });

  testWidgets('Node editor returns journal mood, energy, and weekly review', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-node-type-journal')));
    await tester.enterText(
      find.byKey(const ValueKey('add-node-title-field')),
      'Daily journal',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-journal-mood-field')),
      '4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-journal-energy-field')),
      '3',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-journal-gratitude-field')),
      'Focus time\nGood sleep',
    );
    final weeklyReviewToggle = find.byKey(
      const ValueKey('add-node-journal-weekly-review'),
    );
    tester.widget<CheckboxListTile>(weeklyReviewToggle).onChanged?.call(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.type, NodeType.journal);
    expect(draft?.data['journal'], {
      'mood': 4,
      'energy': 3,
      'prompt': '',
      'gratitude': ['Focus time', 'Good sleep'],
      'isWeeklyReview': true,
    });
  });

  testWidgets('Node editor applies the daily journal template', (tester) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('add-node-template-daily-journal')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('add-node-title-field')))
          .controller
          ?.text,
      'Daily journal',
    );
    expect(
      find.byKey(const ValueKey('add-node-journal-prompt-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('add-node-journal-prompt-field')),
          )
          .controller
          ?.text,
      'What mattered today?',
    );

    await tester.enterText(
      find.byKey(const ValueKey('add-node-journal-mood-field')),
      '4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('add-node-journal-energy-field')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.type, NodeType.journal);
    expect(draft?.title, 'Daily journal');
    expect(
      draft?.data['journal'],
      containsPair('prompt', 'What mattered today?'),
    );
  });

  testWidgets('Node editor applies and saves the monthly review template', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('add-node-template-monthly-review')),
        )
        .onSelected
        ?.call(true);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('add-node-title-field')))
          .controller
          ?.text,
      'Monthly review',
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('add-node-journal-monthly-review')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.type, NodeType.journal);
    expect(draft?.data['journal'], containsPair('isMonthlyReview', true));
  });

  testWidgets('Node editor applies the workout habit template', (tester) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(
      tester,
      onDraft: (value) {
        draft = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('add-node-template-workout-habit')),
        )
        .onSelected
        ?.call(true);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('add-node-title-field')))
          .controller
          ?.text,
      'Workout',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('add-node-habit-target-field')),
          )
          .controller
          ?.text,
      '30 min',
    );

    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    expect(draft?.type, NodeType.habit);
    expect(draft?.data['habit'], containsPair('target', '30 min'));
  });

  testWidgets('Node editor creates event calendar payload details', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(tester, onDraft: (value) => draft = value);
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('add-node-template-event')),
        )
        .onSelected
        ?.call(true);
    await tester.pumpAndSettle();

    final locationField = find.byKey(
      const ValueKey('add-node-calendar-location-field'),
    );
    await tester.ensureVisible(locationField);
    await tester.enterText(locationField, 'Studio A');
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    final payload = calendarNodePayloadFromData(draft!.data);
    expect(payload?.kind, CalendarNodeKind.event);
    expect(payload?.location, 'Studio A');
  });

  testWidgets('Node editor creates meeting calendar payload details', (
    tester,
  ) async {
    AddNodeDraft? draft;

    await _pumpDialogHost(tester, onDraft: (value) => draft = value);
    await tester.tap(find.byKey(const ValueKey('open-add-node-dialog')));
    await tester.pumpAndSettle();

    tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('add-node-template-meeting-notes')),
        )
        .onSelected
        ?.call(true);
    await tester.pumpAndSettle();

    final agendaField = find.byKey(
      const ValueKey('add-node-calendar-agenda-field'),
    );
    await tester.ensureVisible(agendaField);
    await tester.enterText(agendaField, 'Decide launch scope');
    await tester.enterText(
      find.byKey(const ValueKey('add-node-calendar-attendees-field')),
      'Maya\nRafi',
    );
    await tester.tap(find.byKey(const ValueKey('save-node')));
    await tester.pumpAndSettle();

    final payload = calendarNodePayloadFromData(draft!.data);
    expect(payload?.kind, CalendarNodeKind.meeting);
    expect(payload?.agenda, 'Decide launch scope');
    expect(payload?.attendeeCount, 2);
  });
}

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  ValueChanged<AddNodeDraft?>? onDraft,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              key: const ValueKey('open-add-node-dialog'),
              onPressed: () async {
                final draft = await showAddNodeDialog(context);
                onDraft?.call(draft);
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}
