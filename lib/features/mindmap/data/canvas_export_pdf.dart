import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/canvas_board.dart';
import '../domain/mindmap_node.dart';

Future<Uint8List> generateCanvasPdf({
  required List<MindmapNode> nodes,
  required String title,
  CanvasBoard? board,
}) async {
  final pdf = pw.Document();
  final groups = <String, List<MindmapNode>>{};
  final standalone = <MindmapNode>[];

  for (final node in nodes) {
    final groupId = node.data['groupId'];
    if (groupId is String && groupId.isNotEmpty) {
      groups.putIfAbsent(groupId, () => []).add(node);
    } else {
      standalone.add(node);
    }
  }

  if (groups.isEmpty) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            for (final node in standalone) _buildNodePdfWidget(node),
          ],
        ),
      ),
    );
  } else {
    for (final entry in groups.entries) {
      final groupNodes = entry.value;
      final groupTitle =
          groupNodes.first.data['groupTitle'] as String? ?? 'Group';
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      title,
                      style: const pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.Text(
                      groupTitle,
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              for (final node in groupNodes) _buildNodePdfWidget(node),
            ],
          ),
        ),
      );
    }

    if (standalone.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text(
                  '$title - Other Nodes',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 16),
              for (final node in standalone) _buildNodePdfWidget(node),
            ],
          ),
        ),
      );
    }
  }

  final nativeObjects =
      board?.objects
          .where((object) => object.type != CanvasObjectType.nodeReference)
          .toList() ??
      const <CanvasObject>[];
  if (nativeObjects.isNotEmpty) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Header(level: 0, child: pw.Text('$title - Board objects')),
            for (final object in nativeObjects)
              pw.Text(
                object.type == CanvasObjectType.column
                    ? '${object.type.name}: ${object.columnTitle}'
                    : '${object.type.name}: ${object.payload['text'] ?? object.payload['title'] ?? object.id}',
              ),
          ],
        ),
      ),
    );
  }
  return pdf.save();
}

pw.Widget _buildNodePdfWidget(MindmapNode node) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              node.title.isEmpty ? 'Untitled (${node.type.name})' : node.title,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              node.type.name.toUpperCase(),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ],
        ),
        if (node.body.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(node.body, style: const pw.TextStyle(fontSize: 11)),
        ],
        if (node.checklist.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Checklist (${node.completedChecklistCount}/${node.checklist.length}):',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          for (final item in node.checklist)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 8, top: 2),
              child: pw.Text(
                '${item.isDone ? "[x]" : "[ ]"} ${item.title}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
        ],
      ],
    ),
  );
}
