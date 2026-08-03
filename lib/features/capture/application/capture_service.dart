import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/utils/date_utils.dart';
import 'package:var_app/features/capture/application/url_classifier_service.dart';
import 'package:var_app/features/capture/domain/capture_destination.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';
import 'package:var_app/features/capture/domain/captured_url_result.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';

abstract class ContentExtractionPipeline {
  Future<void> enqueue(MindmapNode node);
}

abstract class SearchIndexCoordinator {
  Future<void> indexNode(MindmapNode node);
}

class CaptureService {
  final MindmapRepository _mindmapRepository;
  final UrlClassifierService _urlClassifierService;
  final ContentExtractionPipeline? _extractionPipeline;
  final SearchIndexCoordinator? _indexCoordinator;

  CaptureService({
    required MindmapRepository mindmapRepository,
    UrlClassifierService? urlClassifierService,
    ContentExtractionPipeline? extractionPipeline,
    SearchIndexCoordinator? indexCoordinator,
  }) : _mindmapRepository = mindmapRepository,
       _urlClassifierService = urlClassifierService ?? UrlClassifierService(),
       _extractionPipeline = extractionPipeline,
       _indexCoordinator = indexCoordinator;

  Future<MindmapNode> saveCapture({
    required CapturePayload payload,
    required CaptureDestination destination,
  }) async {
    final validation = CaptureValidator.validate(payload);
    if (!validation.isValid) {
      throw ArgumentError(validation.errors.join('; '));
    }

    final today = dayKey(DateTime.now());
    NodeType nodeType = NodeType.note;
    String label = payload.text ?? 'Captured item';
    final nodeData = <String, Object?>{
      'boardId': destination.boardId,
      'workspaceId': destination.workspaceId,
      'capturedAt': DateTime.now().toIso8601String(),
    };

    if (payload.urls.isNotEmpty) {
      final urlResult = await _urlClassifierService.processUrl(
        payload.urls.first,
      );
      nodeType = urlResult.type == CapturedUrlType.article
          ? NodeType.article
          : NodeType.link;
      label = urlResult.title;
      nodeData['url'] = urlResult.url;
      nodeData['canonicalUrl'] = urlResult.canonicalUrl;
      if (urlResult.extractedText != null) {
        nodeData['extractedText'] = urlResult.extractedText;
      }
      if (urlResult.htmlSnapshot != null) {
        nodeData['htmlSnapshot'] = urlResult.htmlSnapshot;
      }
    }

    final node = MindmapNode(
      id: 'capture-${DateTime.now().millisecondsSinceEpoch}',
      day: today,
      type: nodeType,
      label: label,
      data: nodeData,
    );

    await _mindmapRepository.saveNode(node);

    if (_extractionPipeline != null) {
      Future.microtask(() => _extractionPipeline.enqueue(node));
    }
    if (_indexCoordinator != null) {
      Future.microtask(() => _indexCoordinator.indexNode(node));
    }

    return node;
  }
}
