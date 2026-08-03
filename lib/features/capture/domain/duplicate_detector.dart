import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

class DuplicateMatchResult {
  final bool hasDuplicate;
  final String? existingNodeId;
  final String? matchedCanonicalUrl;
  final String? matchedContentHash;

  const DuplicateMatchResult({
    required this.hasDuplicate,
    this.existingNodeId,
    this.matchedCanonicalUrl,
    this.matchedContentHash,
  });

  static const none = DuplicateMatchResult(hasDuplicate: false);
}

class DuplicateDetector {
  static String normalizeUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    final normalized = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: (uri.port == 80 || uri.port == 443) ? 0 : uri.port,
      path: uri.path.endsWith('/') && uri.path.length > 1
          ? uri.path.substring(0, uri.path.length - 1)
          : uri.path,
    );
    return normalized.toString();
  }

  static String hashContent(String content) {
    return sha256.convert(utf8.encode(content.trim())).toString();
  }

  static DuplicateMatchResult check(
    CapturePayload payload,
    List<MindmapNode> existingNodes,
  ) {
    if (payload.urls.isNotEmpty) {
      final targetNormalized = normalizeUrl(payload.urls.first);
      for (final node in existingNodes) {
        final nodeUrl = node.data['url'] as String?;
        if (nodeUrl != null && normalizeUrl(nodeUrl) == targetNormalized) {
          return DuplicateMatchResult(
            hasDuplicate: true,
            existingNodeId: node.id,
            matchedCanonicalUrl: targetNormalized,
          );
        }
      }
    }

    if (payload.text != null && payload.text!.trim().isNotEmpty) {
      final targetHash = hashContent(payload.text!);
      for (final node in existingNodes) {
        final nodeContent = node.title.isNotEmpty
            ? node.title
            : (node.data['content'] as String?);
        if (nodeContent != null && hashContent(nodeContent) == targetHash) {
          return DuplicateMatchResult(
            hasDuplicate: true,
            existingNodeId: node.id,
            matchedContentHash: targetHash,
          );
        }
      }
    }

    return DuplicateMatchResult.none;
  }
}
