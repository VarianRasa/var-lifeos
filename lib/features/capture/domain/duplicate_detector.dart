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
  static const _trackingParams = {
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'fbclid',
    'gclid',
  };

  static String? tryNormalizeUrl(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      return normalizeUrl(raw);
    } catch (_) {
      return null;
    }
  }

  static String normalizeUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    final isDefaultPort =
        (uri.scheme.toLowerCase() == 'http' && uri.port == 80) ||
        (uri.scheme.toLowerCase() == 'https' && uri.port == 443);

    Map<String, String>? queryParameters;
    if (uri.queryParameters.isNotEmpty) {
      final filtered = Map<String, String>.from(uri.queryParameters)
        ..removeWhere((key, _) => _trackingParams.contains(key.toLowerCase()));
      if (filtered.isNotEmpty) {
        queryParameters = filtered;
      }
    }

    String path = uri.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }

    final normalized = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: isDefaultPort ? null : (uri.hasPort ? uri.port : null),
      path: path,
      queryParameters: queryParameters,
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
    for (final rawPayloadUrl in payload.urls) {
      final targetNormalized = tryNormalizeUrl(rawPayloadUrl);
      if (targetNormalized == null) continue;

      for (final node in existingNodes) {
        final rawNodeUrl = node.data['url'];
        final storedNormalized = tryNormalizeUrl(rawNodeUrl);
        if (storedNormalized != null && storedNormalized == targetNormalized) {
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
        final rawContent = node.title.isNotEmpty
            ? node.title
            : (node.data['content'] is String
                  ? node.data['content'] as String
                  : null);
        if (rawContent != null && hashContent(rawContent) == targetHash) {
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
