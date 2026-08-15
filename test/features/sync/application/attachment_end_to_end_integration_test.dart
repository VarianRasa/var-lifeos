import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/local_node_attachment_repository_io.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/sync/application/attachment_sync_executor.dart';
import 'package:var_app/features/sync/application/mindmap_backup_service.dart';
import 'package:var_app/features/sync/application/portable_backup_codec.dart';
import 'package:var_app/features/sync/data/firebase_remote_attachment_store.dart';
import 'package:var_app/features/sync/data/http_remote_attachment_store.dart';
import 'package:var_app/features/sync/data/in_memory_attachment_sync_progress_store.dart';
import 'package:var_app/features/sync/data/sembast_attachment_sync_progress_store.dart';
import 'package:var_app/features/sync/domain/attachment_sync.dart';
import 'package:var_app/features/sync/domain/attachment_sync_progress.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/remote_attachment_store.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('var-attachment-e2e-');
  });
  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  LocalNodeAttachmentRepository repository(String name) =>
      LocalNodeAttachmentRepository(
        root: Directory(p.join(sandbox.path, name)),
      );

  test(
    'HTTP adapter resumes migrated Sembast queue after database reopen',
    () async {
      final attachments = repository('http-upload');
      final attachment = await attachments.importBytes(
        bytes: const [137, 80, 78, 71],
        fileName: 'capture.png',
        mimeType: 'image/png',
      );
      final nodes = InMemoryMindmapRepository(
        seedNodes: [_mediaNode('image', NodeType.image, attachment.id)],
      );
      final server = _StrictHttpAttachmentServer();
      final remote = await _connectHttp(server);
      final databaseName = 'attachment-restart-${attachment.id}.db';
      final rawStore = stringMapStoreFactory.store(
        'attachment_sync_progress_v1',
      );
      final firstDatabase = await databaseFactoryMemory.openDatabase(
        databaseName,
      );
      final legacyProgress = AttachmentSyncProgress(
        attachmentId: attachment.id,
        direction: AttachmentSyncDirection.upload,
        remoteStoreKind: AttachmentRemoteStoreKind.http,
        attempt: 1,
        nextRetryAt: DateTime.utc(2026, 7, 15, 8, 30),
        lastError: 'Offline.',
        state: AttachmentSyncProgressState.waitingRetry,
      );
      await rawStore
          .record('upload:${attachment.id}')
          .put(firstDatabase, legacyProgress.toJson());
      await firstDatabase.close();

      final reopenedDatabase = await databaseFactoryMemory.openDatabase(
        databaseName,
      );
      addTearDown(reopenedDatabase.close);
      final progressStore = SembastAttachmentSyncProgressStore(
        database: reopenedDatabase,
      );
      final migrated = await progressStore.readAll();
      expect(migrated.single.key, legacyProgress.key);
      expect(
        (await rawStore.find(reopenedDatabase)).single.key,
        legacyProgress.key,
      );

      final report = await _executor(
        nodes: nodes,
        attachments: attachments,
        remote: remote,
        progress: progressStore,
        storeKind: AttachmentRemoteStoreKind.http,
        now: DateTime.utc(2026, 7, 15, 9),
      ).run();

      expect(report.completed, 1);
      expect(report.pending, 0);
      expect(server.bytesById[attachment.id], [137, 80, 78, 71]);
      final persisted = (await progressStore.readAll()).single.toJson();
      expect(persisted['state'], AttachmentSyncProgressState.completed.name);
      expect(persisted.keys, isNot(contains('bytes')));
      expect(persisted.keys, isNot(contains('path')));
      expect(persisted.keys, isNot(contains('token')));
    },
  );

  test(
    'Firebase adapter uploads verified attachment through executor',
    () async {
      final attachments = repository('firebase-upload');
      final attachment = await attachments.importBytes(
        bytes: const [137, 80, 78, 71],
        fileName: 'firebase.png',
        mimeType: 'image/png',
      );
      final nodes = InMemoryMindmapRepository(
        seedNodes: [_mediaNode('image', NodeType.image, attachment.id)],
      );
      final gateway = _StrictFirebaseGateway();
      final remote = FirebaseRemoteAttachmentStore(
        gateway: gateway,
        userIdProvider: () => 'user_A',
      );

      final report = await _executor(
        nodes: nodes,
        attachments: attachments,
        remote: remote,
        progress: InMemoryAttachmentSyncProgressStore(),
        storeKind: AttachmentRemoteStoreKind.firebase,
      ).run();

      expect(report.completed, 1);
      expect(gateway.objects['attachments/user_A/${attachment.id}']?.bytes, [
        137,
        80,
        78,
        71,
      ]);
    },
  );

  test(
    'Firebase adapter download restores stable id and verified bytes',
    () async {
      final source = repository('firebase-download-source');
      final attachment = await source.importBytes(
        bytes: const [0, 0, 0, 24],
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
      );
      final gateway = _StrictFirebaseGateway();
      await gateway.seed(
        key: 'attachments/user_A/${attachment.id}',
        metadata: attachment,
        bytes: (await source.readBytes(attachment.id))!,
      );
      final remote = FirebaseRemoteAttachmentStore(
        gateway: gateway,
        userIdProvider: () => 'user_A',
      );
      final target = repository('firebase-download-target');
      final nodes = InMemoryMindmapRepository(
        seedNodes: [_mediaNode('video', NodeType.video, attachment.id)],
      );

      final report = await _executor(
        nodes: nodes,
        attachments: target,
        remote: remote,
        progress: InMemoryAttachmentSyncProgressStore(),
        storeKind: AttachmentRemoteStoreKind.firebase,
      ).run();

      expect(report.completed, 1);
      expect((await target.resolve(attachment.id))?.id, attachment.id);
      expect(await target.readBytes(attachment.id), [0, 0, 0, 24]);
    },
  );

  test('adapter-backed conflict preserves local and remote content', () async {
    final local = repository('firebase-conflict');
    final localAttachment = await local.importBytes(
      bytes: const [1, 2, 3],
      fileName: 'local.png',
      mimeType: 'image/png',
    );
    const remoteBytes = [9, 8, 7];
    final conflictingMetadata = await _attachmentWithId(
      id: localAttachment.id,
      bytes: remoteBytes,
      fileName: 'remote.png',
      mimeType: 'image/png',
    );
    final gateway = _StrictFirebaseGateway();
    await gateway.seed(
      key: 'attachments/user_A/${localAttachment.id}',
      metadata: conflictingMetadata,
      bytes: remoteBytes,
    );
    final remote = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_A',
    );
    final nodes = InMemoryMindmapRepository(
      seedNodes: [_mediaNode('image', NodeType.image, localAttachment.id)],
    );

    final report = await _executor(
      nodes: nodes,
      attachments: local,
      remote: remote,
      progress: InMemoryAttachmentSyncProgressStore(),
      storeKind: AttachmentRemoteStoreKind.firebase,
    ).run();

    expect(report.conflicts, 1);
    expect(await local.readBytes(localAttachment.id), [1, 2, 3]);
    expect(
      gateway.objects['attachments/user_A/${localAttachment.id}']?.bytes,
      remoteBytes,
    );
  });

  test(
    'portable backup round-trip preserves attachment bytes and node id',
    () async {
      final sourceAttachments = repository('backup-source');
      final attachment = await sourceAttachments.importBytes(
        bytes: const [137, 80, 78, 71],
        fileName: 'backup.png',
        mimeType: 'image/png',
      );
      final sourceNodes = InMemoryMindmapRepository(
        seedNodes: [_mediaNode('image', NodeType.image, attachment.id)],
      );
      final targetAttachments = repository('backup-target');
      final targetNodes = InMemoryMindmapRepository();

      final package = await _backupService(
        sourceNodes,
        sourceAttachments,
      ).createPortableBackup(passphrase: 'secret');
      final report = await _backupService(
        targetNodes,
        targetAttachments,
      ).importPortableBackup(package.package, passphrase: 'secret');

      expect(report.warnings, isEmpty);
      expect(await targetAttachments.readBytes(attachment.id), [
        137,
        80,
        78,
        71,
      ]);
      expect(
        ImagePayload.fromNode(
          (await targetNodes.getNode('image'))!,
        ).attachmentId,
        attachment.id,
      );
    },
  );
}

Future<HttpRemoteAttachmentStore> _connectHttp(
  _StrictHttpAttachmentServer server,
) async {
  final store = await HttpRemoteAttachmentStore.connect(
    endpoint: Uri.parse('https://api.var.test/sync/'),
    client: server,
    authSnapshotProvider: () => HttpAttachmentAuthSnapshot(
      accountId: 'account-a',
      revision: 'session-1',
      headers: const {'authorization': 'Bearer integration-token'},
    ),
  );
  expect(store, isNotNull);
  return store!;
}

AttachmentSyncExecutor _executor({
  required InMemoryMindmapRepository nodes,
  required NodeAttachmentRepository attachments,
  required RemoteAttachmentStore remote,
  required AttachmentSyncProgressStore progress,
  required AttachmentRemoteStoreKind storeKind,
  DateTime? now,
}) => AttachmentSyncExecutor(
  mindmapRepository: nodes,
  attachmentRepository: attachments,
  remoteStore: remote,
  progressStore: progress,
  remoteStoreKind: storeKind,
  now: () => now ?? _now,
  delay: (_) async {},
);

MindmapBackupService _backupService(
  InMemoryMindmapRepository nodes,
  NodeAttachmentRepository attachments,
) => MindmapBackupService(
  repository: nodes,
  sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
  now: () => _now,
  portableCodec: PortableMindmapBackupCodec(
    iterations: PortableMindmapBackupCodec.minKdfIterations,
    randomBytes: (length) => List<int>.generate(length, (index) => index + 1),
  ),
  attachmentRepository: attachments,
);

MindmapNode _mediaNode(String id, NodeType type, String attachmentId) =>
    MindmapNode.create(
      id: id,
      type: type,
      title: id,
      day: _now,
      now: _now,
    ).copyWith(
      data: type == NodeType.image
          ? ImagePayload(attachmentId: attachmentId).toData()
          : {'attachmentId': attachmentId},
    );

Future<NodeAttachment> _attachmentWithId({
  required String id,
  required List<int> bytes,
  required String fileName,
  required String mimeType,
}) async => NodeAttachment(
  id: id,
  fileName: fileName,
  mimeType: mimeType,
  byteLength: bytes.length,
  checksum: await _checksum(bytes),
  createdAt: _now,
);

Future<String> _checksum(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

Map<String, String> _httpMetadataHeaders(NodeAttachment metadata) => {
  'x-var-attachment-schema-version': '1',
  'x-var-attachment-id': metadata.id,
  'x-var-attachment-sha256': metadata.checksum,
  'x-var-attachment-byte-length': '${metadata.byteLength}',
  'x-var-attachment-file-name': Uri.encodeComponent(metadata.fileName),
  'content-type': metadata.mimeType,
  'content-length': '${metadata.byteLength}',
};

Map<String, String> _firebaseMetadata(NodeAttachment metadata) => {
  'schemaVersion': '1',
  'attachmentId': metadata.id,
  'checksum': metadata.checksum,
  'byteLength': '${metadata.byteLength}',
  'mimeType': metadata.mimeType,
  'fileName': metadata.fileName,
};

final _now = DateTime.utc(2026, 7, 15, 8);

final class _StrictHttpAttachmentServer extends http.BaseClient {
  final Map<String, NodeAttachment> metadataById = {};
  final Map<String, List<int>> bytesById = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.headers['authorization'], 'Bearer integration-token');
    final body = await request.finalize().fold<List<int>>(
      <int>[],
      (value, chunk) => value..addAll(chunk),
    );
    if (request.url.path.endsWith('/capabilities')) {
      expect(request.method, 'GET');
      return _response(
        200,
        utf8.encode(
          jsonEncode({
            'attachments': {
              'version': 1,
              'upload': true,
              'download': true,
              'delete': false,
              'maxBytes': 1024 * 1024,
            },
          }),
        ),
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    final id = request.url.pathSegments.last;
    final metadata = metadataById[id];
    switch (request.method) {
      case 'HEAD':
        return metadata == null
            ? _response(404, const [], request: request)
            : _response(
                200,
                const [],
                headers: _httpMetadataHeaders(metadata),
                request: request,
              );
      case 'PUT':
        final uploaded = RemoteAttachmentMetadata.validated(
          attachmentId: request.headers['x-var-attachment-id'],
          checksum: request.headers['x-var-attachment-sha256'],
          byteLength: int.tryParse(
            request.headers['x-var-attachment-byte-length'] ?? '',
          ),
          mimeType: request.headers['content-type'],
          fileName: Uri.decodeComponent(
            request.headers['x-var-attachment-file-name'] ?? '',
          ),
        );
        expect(uploaded.attachmentId, id);
        expect(request.contentLength, uploaded.byteLength);
        expect(body.length, uploaded.byteLength);
        expect(await _checksum(body), uploaded.checksum);
        final existing = metadataById[id];
        if (existing != null &&
            RemoteAttachmentMetadata.fromNodeAttachment(existing) != uploaded) {
          return _response(409, const [], request: request);
        }
        final stored = NodeAttachment(
          id: uploaded.attachmentId,
          fileName: uploaded.fileName,
          mimeType: uploaded.mimeType,
          byteLength: uploaded.byteLength,
          checksum: uploaded.checksum,
          createdAt: _now,
        );
        metadataById[id] = stored;
        bytesById[id] = List<int>.unmodifiable(body);
        return _response(204, const [], request: request);
      case 'GET':
        if (metadata == null) return _response(404, const [], request: request);
        final bytes = bytesById[id]!;
        expect(bytes.length, metadata.byteLength);
        expect(await _checksum(bytes), metadata.checksum);
        return _response(
          200,
          bytes,
          headers: _httpMetadataHeaders(metadata),
          request: request,
        );
      default:
        return _response(405, const [], request: request);
    }
  }
}

http.StreamedResponse _response(
  int status,
  List<int> body, {
  Map<String, String> headers = const {},
  required http.BaseRequest request,
}) => http.StreamedResponse(
  Stream<List<int>>.value(List<int>.unmodifiable(body)),
  status,
  headers: headers,
  contentLength: body.length,
  request: request,
);

final class _StrictFirebaseGateway implements FirebaseStorageGateway {
  final Map<String, FirebaseStorageObject> objects = {};

  Future<void> seed({
    required String key,
    required NodeAttachment metadata,
    required List<int> bytes,
  }) async {
    expect(bytes.length, metadata.byteLength);
    expect(await _checksum(bytes), metadata.checksum);
    objects[key] = FirebaseStorageObject(
      bytes: Uint8List.fromList(bytes),
      contentType: metadata.mimeType,
      customMetadata: _firebaseMetadata(metadata),
    );
  }

  @override
  Future<FirebaseStorageObject?> get(
    String key, {
    required int maxBytes,
  }) async {
    final object = objects[key];
    if (object == null) return null;
    expect(object.bytes.length, lessThanOrEqualTo(maxBytes));
    final metadata = RemoteAttachmentMetadata.fromJson({
      'attachmentId': object.customMetadata?['attachmentId'],
      'checksum': object.customMetadata?['checksum'],
      'byteLength': int.tryParse(object.customMetadata?['byteLength'] ?? ''),
      'mimeType': object.contentType,
      'fileName': object.customMetadata?['fileName'],
    });
    expect(object.bytes.length, metadata.byteLength);
    expect(await _checksum(object.bytes), metadata.checksum);
    return object;
  }

  @override
  Future<FirebaseStorageObjectMetadata?> head(String key) async {
    final object = objects[key];
    return object == null
        ? null
        : FirebaseStorageObjectMetadata(
            contentType: object.contentType,
            customMetadata: object.customMetadata,
          );
  }

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    final metadata = RemoteAttachmentMetadata.fromJson({
      'attachmentId': customMetadata['attachmentId'],
      'checksum': customMetadata['checksum'],
      'byteLength': int.tryParse(customMetadata['byteLength'] ?? ''),
      'mimeType': contentType,
      'fileName': customMetadata['fileName'],
    });
    expect(key, endsWith('/${metadata.attachmentId}'));
    expect(
      customMetadata,
      _firebaseMetadata(
        NodeAttachment(
          id: metadata.attachmentId,
          fileName: metadata.fileName,
          mimeType: metadata.mimeType,
          byteLength: metadata.byteLength,
          checksum: metadata.checksum,
          createdAt: _now,
        ),
      ),
    );
    expect(bytes.length, metadata.byteLength);
    expect(await _checksum(bytes), metadata.checksum);
    final existing = objects[key];
    if (existing != null &&
        existing.customMetadata?['checksum'] != metadata.checksum) {
      throw const FirebaseStorageGatewayException('object-already-exists');
    }
    objects[key] = FirebaseStorageObject(
      bytes: Uint8List.fromList(bytes),
      contentType: contentType,
      customMetadata: Map<String, String>.unmodifiable(customMetadata),
    );
  }
}
