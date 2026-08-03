import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/search/application/content_extraction_pipeline.dart';
import 'package:var_app/features/search/application/search_document_projector.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';
import 'package:var_app/features/search/domain/content_extraction.dart';
import 'package:var_app/features/search/domain/search_document.dart';

class CaptureService {
  final MindmapRepository _mindmapRepository;
  final UrlClassifierService _urlClassifierService;
  final ContentExtractionPipeline? _extractionPipeline;
  final SearchIndexCoordinator? _indexCoordinator;
  final SearchDocumentProjector _projector;

  CaptureService({
    required MindmapRepository mindmapRepository,
    UrlClassifierService? urlClassifierService,
    ContentExtractionPipeline? extractionPipeline,
    SearchIndexCoordinator? indexCoordinator,
    SearchDocumentProjector projector = const SearchDocumentProjector(),
  }) : _mindmapRepository = mindmapRepository,
       _urlClassifierService = urlClassifierService ?? UrlClassifierService(),
       _extractionPipeline = extractionPipeline,
       _indexCoordinator = indexCoordinator,
       _projector = projector;

  Future<MindmapNode> saveCapture({
    required CapturePayload payload,
    required CaptureDestination destination,
  }) async {
    final validation = CaptureValidator.validate(
      payload,
      destination: destination,
    );
    if (!validation.isValid) {
      throw ArgumentError(validation.errors.join('; '));
    }

    final today = DateTime.now();
    NodeType nodeType = NodeType.note;
    String title = payload.text ?? 'Captured item';
    final nodeData = <String, Object?>{
      'boardId': destination.boardId,
      'workspaceId': destination.workspaceId,
      'capturedAt': DateTime.now().toIso8601String(),
    };

    if (payload.attachments.isNotEmpty) {
      nodeData['attachments'] = payload.attachments
          .map(
            (a) => {
              'fileName': a.fileName,
              'mimeType': a.mimeType,
              if (a.localPath != null) 'localPath': a.localPath,
              'bytes': base64Encode(a.bytes),
            },
          )
          .toList();
    }

    if (payload.urls.isNotEmpty) {
      final urlResult = await _urlClassifierService.processUrl(
        payload.urls.first,
      );
      nodeType = NodeType.link;
      title = urlResult.title;
      nodeData['url'] = urlResult.url;
      nodeData['canonicalUrl'] = urlResult.canonicalUrl;
      if (urlResult.extractedText != null) {
        nodeData['extractedText'] = urlResult.extractedText;
      }
      if (urlResult.htmlSnapshot != null) {
        nodeData['htmlSnapshot'] = urlResult.htmlSnapshot;
      }
    }

    final now = DateTime.now();
    final node = MindmapNode.create(
      id: 'capture-${now.millisecondsSinceEpoch}',
      type: nodeType,
      title: title,
      day: today,
      data: nodeData,
      now: now,
    );

    await _mindmapRepository.saveNode(node);

    if (_extractionPipeline != null || _indexCoordinator != null) {
      final pipeline = _extractionPipeline;
      final coordinator = _indexCoordinator;
      final projector = _projector;
      final savedNode = node;

      unawaited(
        Future.microtask(() async {
          final extractions = <Map<String, Object?>>[];
          if (pipeline != null && payload.attachments.isNotEmpty) {
            for (final attachment in payload.attachments) {
              try {
                final result = await pipeline.extract(
                  ContentExtractionRequest(
                    sourceId: savedNode.id,
                    bytes: attachment.bytes,
                    mimeType: attachment.mimeType,
                    fileName: attachment.fileName,
                  ),
                );
                if (result != null && result.text.trim().isNotEmpty) {
                  extractions.add({
                    'fileName': attachment.fileName,
                    'mimeType': attachment.mimeType,
                    'text': result.text,
                    'locations': [
                      for (final location in result.locations)
                        {'kind': location.kind.name, 'value': location.value},
                    ],
                  });

                  if (coordinator != null) {
                    final attachmentDoc = projector.projectAttachment(
                      NodeAttachment(
                        id: attachment.fileName,
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        byteLength: attachment.bytes.length,
                        checksum: sha256.convert(attachment.bytes).toString(),
                        createdAt: now,
                      ),
                      sourceId: savedNode.id,
                      workspaceId: destination.workspaceId,
                      boardId: destination.boardId,
                    );
                    final enhancedDoc = SearchDocument(
                      id: attachmentDoc.id,
                      sourceId: attachmentDoc.sourceId,
                      fragmentId: attachmentDoc.fragmentId,
                      sourceKind: attachmentDoc.sourceKind,
                      workspaceId: attachmentDoc.workspaceId,
                      boardId: attachmentDoc.boardId,
                      title: attachmentDoc.title,
                      snippet: attachmentDoc.snippet,
                      text: '${attachmentDoc.text} ${result.text}',
                      date: attachmentDoc.date,
                      modifiedAt: attachmentDoc.modifiedAt,
                    );
                    await coordinator.indexDocuments([enhancedDoc]);
                  }
                }
              } on Object {
                continue;
              }
            }
          }

          if (extractions.isNotEmpty) {
            final updatedData = Map<String, Object?>.from(savedNode.data)
              ..['extractions'] = extractions;
            final nodeWithExtractions = savedNode.copyWith(data: updatedData);
            await _mindmapRepository.saveNode(nodeWithExtractions);
          }

          if (coordinator != null) {
            try {
              final docs = projector.projectNode(
                savedNode,
                workspaceId: destination.workspaceId,
              );
              await coordinator.indexDocuments(docs);
            } on Object {
              return;
            }
          }
        }),
      );
    }

    return node;
  }
}
