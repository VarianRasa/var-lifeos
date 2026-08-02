import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/workshop_summary_export.dart';
import 'package:var_app/features/mindmap/domain/canvas_workshop.dart';
import 'package:var_app/features/mindmap/domain/workshop_ai.dart';

void main() {
  const snapshot = WorkshopAiSummarySnapshot(
    summary: 'Outcome',
    themes: <String>['Theme'],
    decisions: <String>['Decision'],
    actionItems: <String>['Action'],
    risks: <String>['Risk'],
    model: 'private-model',
    version: 'private-version',
  );
  const summary = CanvasWorkshopSummary(
    activeDurationSeconds: 60,
    participantCount: 2,
    objectsAdded: 1,
    objectsUpdated: 2,
    objectsDeleted: 3,
    participantContributionCounts: <String, int>{'private-user': 4},
    lastPresenterUid: 'private-presenter',
    aiSummarySnapshot: snapshot,
  );

  test('JSON export uses privacy-minimal envelope', () {
    final encoded = exportWorkshopSummaryJson(summary);
    final json = jsonDecode(encoded) as Map<String, Object?>;

    expect(json.keys, <String>{'schemaVersion', 'summary'});
    expect(encoded, isNot(contains('private-user')));
    expect(encoded, isNot(contains('private-presenter')));
    expect(encoded, isNot(contains('private-model')));
    expect(encoded, contains('Outcome'));
  });

  test('PDF export starts with PDF signature', () async {
    final bytes = await exportWorkshopSummaryPdf(summary);

    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
  });
}
