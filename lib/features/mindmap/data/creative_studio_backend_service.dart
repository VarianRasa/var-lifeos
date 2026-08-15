import 'package:http/http.dart' as http;

/// Cloud storage & sync adapter for Creative Studio high-resolution media & render assets.
abstract interface class CreativeStudioAssetStorage {
  Future<String> uploadCanvasAsset({
    required String workspaceId,
    required String assetName,
    required List<int> bytes,
    required String contentType,
  });

  Future<void> deleteCanvasAsset(String assetUrl);
}

/// Cloudflare R2 / AWS S3 S3-compatible asset store client for Var Creative Studio.
class S3CompatibleAssetStorage implements CreativeStudioAssetStorage {
  S3CompatibleAssetStorage({
    required this.endpointUrl,
    required this.bucketName,
    required this.accessKeyId,
    required this.secretAccessKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final String endpointUrl;
  final String bucketName;
  final String accessKeyId;
  final String secretAccessKey;
  final http.Client _client;

  @override
  Future<String> uploadCanvasAsset({
    required String workspaceId,
    required String assetName,
    required List<int> bytes,
    required String contentType,
  }) async {
    final cleanEndpoint = endpointUrl.replaceAll(RegExp(r'/+$'), '');
    final uploadUri = Uri.parse(
      '$cleanEndpoint/$bucketName/workspaces/$workspaceId/$assetName',
    );

    // Standard Direct PUT upload
    final response = await _client.put(
      uploadUri,
      headers: {'Content-Type': contentType, 'x-amz-acl': 'public-read'},
      body: bytes,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return uploadUri.toString();
    }

    throw Exception(
      'Failed to upload asset to R2/S3 (${response.statusCode}): ${response.body}',
    );
  }

  @override
  Future<void> deleteCanvasAsset(String assetUrl) async {
    final uri = Uri.tryParse(assetUrl);
    if (uri == null) return;

    final response = await _client.delete(uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
  }
}

/// Serverpod / Realtime backend protocol contract for synchronizing Creative Studio elements.
final class CreativeCanvasSyncEnvelope {
  const CreativeCanvasSyncEnvelope({
    required this.boardId,
    required this.workspaceId,
    required this.senderUid,
    required this.revision,
    required this.timestamp,
    required this.boardJson,
  });

  final String boardId;
  final String workspaceId;
  final String senderUid;
  final int revision;
  final DateTime timestamp;
  final Map<String, Object?> boardJson;

  Map<String, Object?> toJson() => {
    'boardId': boardId,
    'workspaceId': workspaceId,
    'senderUid': senderUid,
    'revision': revision,
    'timestamp': timestamp.toIso8601String(),
    'boardJson': boardJson,
  };

  factory CreativeCanvasSyncEnvelope.fromJson(Map<String, Object?> json) {
    return CreativeCanvasSyncEnvelope(
      boardId: json['boardId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      senderUid: json['senderUid'] as String? ?? '',
      revision: (json['revision'] as num? ?? 0).toInt(),
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      boardJson: json['boardJson'] is Map<String, Object?>
          ? json['boardJson'] as Map<String, Object?>
          : <String, Object?>{},
    );
  }
}
