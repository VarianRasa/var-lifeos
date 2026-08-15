import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../domain/canvas_workshop.dart';

String exportWorkshopSummaryJson(CanvasWorkshopSummary summary) =>
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'summary': _privacyMinimalSummary(summary),
    });

Future<Uint8List> exportWorkshopSummaryPdf(
  CanvasWorkshopSummary summary,
) async {
  final document = pw.Document();
  final ai = summary.aiSummarySnapshot;
  document.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Header(level: 0, child: pw.Text('Workshop summary')),
          pw.Text('Active time: ${summary.activeDurationSeconds} seconds'),
          pw.Text('Participants: ${summary.participantCount}'),
          pw.Text('Objects added: ${summary.objectsAdded}'),
          pw.Text('Objects updated: ${summary.objectsUpdated}'),
          pw.Text('Objects deleted: ${summary.objectsDeleted}'),
          if (ai != null) ...[
            pw.SizedBox(height: 12),
            pw.Text(ai.summary),
            for (final action in ai.actionItems) pw.Text('Action: $action'),
            for (final risk in ai.risks) pw.Text('Risk: $risk'),
          ],
        ],
      ),
    ),
  );
  return document.save();
}

Map<String, Object?> _privacyMinimalSummary(CanvasWorkshopSummary summary) {
  final ai = summary.aiSummarySnapshot;
  return <String, Object?>{
    'activeDurationSeconds': summary.activeDurationSeconds,
    'participantCount': summary.participantCount,
    'objectsAdded': summary.objectsAdded,
    'objectsUpdated': summary.objectsUpdated,
    'objectsDeleted': summary.objectsDeleted,
    'votingWinnerVotes': summary.votingWinnerVotes,
    'clusterCount': summary.clusterCount,
    if (ai != null)
      'ai': <String, Object>{
        'summary': ai.summary,
        'themes': ai.themes,
        'decisions': ai.decisions,
        'actionItems': ai.actionItems,
        'risks': ai.risks,
      },
  };
}
