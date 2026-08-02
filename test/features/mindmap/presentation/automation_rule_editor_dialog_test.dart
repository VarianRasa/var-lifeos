import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/automation_rule.dart';
import 'package:var_app/features/mindmap/domain/recurring_routine.dart';
import 'package:var_app/features/mindmap/presentation/automation_rule_editor_dialog.dart';

void main() {
  testWidgets('AutomationRuleEditorDialog renders successfully', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(body: AutomationRuleEditorDialog()),
        ),
      ),
    );

    expect(find.text('Buat Aturan Otomatisasi'), findsOneWidget);
    expect(find.text('Nama Aturan / Deskripsi'), findsOneWidget);
    expect(find.text('Pemicu (Trigger)'), findsOneWidget);
    expect(find.text('Aksi (Action)'), findsOneWidget);
  });

  testWidgets('AutomationRuleEditorDialog populates fields when editing rule', (
    tester,
  ) async {
    final repository = InMemoryMindmapRepository();
    final rule = AutomationRuleRecord(
      nodeId: 'node-1',
      id: 'rule-1',
      label: 'Auto Task Followup',
      templateId: 'daily-plan',
      rule: RecurringRule.daily(),
      enabled: true,
      triggerType: AutomationTriggerType.taskCompleted,
      actionType: AutomationActionType.autoTag,
      actionTag: 'reviewed',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindmapRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Scaffold(body: AutomationRuleEditorDialog(existingRule: rule)),
        ),
      ),
    );

    expect(find.text('Edit Aturan Otomatisasi'), findsOneWidget);
    expect(find.text('Auto Task Followup'), findsOneWidget);
  });
}
