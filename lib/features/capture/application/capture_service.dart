import 'dart:async';

import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/search/application/content_extraction_pipeline.dart';
import 'package:var_app/features/search/application/search_document_projector.dart';
import 'package:var_app/features/search/application/search_index_coordinator.dart';
import 'package:var_app/features/search/domain/content_extraction.dart';

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
    final validation = CaptureValidator.validate(payload);
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

    if (_extractionPipeline != null && payload.attachments.isNotEmpty) {
      final pipeline = _extractionPipeline;
      unawaited(
        Future.microtask(() async {
          for (final attachment in payload.attachments) {
            await pipeline.extract(
              ContentExtractionRequest(
                sourceId: node.id,
                bytes: attachment.bytes,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName,
              ),
            );
          }
        }),
      );
    }
    if (_indexCoordinator != null) {
      final coordinator = _indexCoordinator;
      final docs = _projector.projectNode(
        node,
        workspaceId: destination.workspaceId,
      );
      unawaited(Future.microtask(() => coordinator.indexDocuments(docs)));
    }

    return node;
  }
}
