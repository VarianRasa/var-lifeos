import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/sync/data/http_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';

void main() {
  test(
    'uploads the latest backup document with bearer authorization',
    () async {
      http.Request? capturedRequest;
      final store = HttpSyncRemoteBackupStore(
        endpoint: Uri.parse('https://api.var.app/sync'),
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response('', 204);
        }),
        tokenProvider: () async => 'token-123',
      );
      final document = MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime(2026, 6, 19, 9),
        nodes: [_node(id: 'note-1', title: 'Remote note')],
      );

      await store.uploadBackup(_user, document);

      final request = capturedRequest;
      expect(request, isNotNull);
      expect(request!.method, 'PUT');
      expect(
        request.url.toString(),
        'https://api.var.app/sync/users/user-1/mindmap-backup/latest',
      );
      expect(request.headers['authorization'], 'Bearer token-123');
      expect(request.headers['content-type'], contains('application/json'));
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['type'], MindmapBackupDocument.documentType);
      expect(
        (body['nodes'] as List).single,
        containsPair('title', 'Remote note'),
      );
    },
  );

  test('rejects attachment payloads in cloud backup documents', () async {
    final store = HttpSyncRemoteBackupStore(
      endpoint: Uri.parse('https://api.var.app/sync'),
      client: MockClient((request) async => http.Response('', 204)),
    );
    final document = MindmapBackupDocument.fromJson({
      ...MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime(2026, 6, 19, 9),
        nodes: const [],
      ).toJson(),
      'attachments': [
        {
          'version': 1,
          'attachment': {
            'id': '00000000-0000-4000-8000-000000000001',
            'fileName': 'photo.png',
            'mimeType': 'image/png',
            'byteLength': 1,
            'checksum': '00',
            'createdAt': DateTime(2026, 6, 19, 9).toIso8601String(),
          },
          'payload': 'AA==',
        },
      ],
    });

    await expectLater(
      store.uploadBackup(_user, document),
      throwsA(
        isA<SyncRemoteStoreException>().having(
          (error) => error.message,
          'message',
          'Remote backup cannot contain attachment payloads.',
        ),
      ),
    );
  });

  test(
    'fetches the latest backup document and treats 404 as no backup',
    () async {
      final document = MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
        exportedAt: DateTime(2026, 6, 19, 10),
        nodes: [_node(id: 'note-2', title: 'Fetched note')],
      );
      var requestCount = 0;
      final store = HttpSyncRemoteBackupStore(
        endpoint: Uri.parse('https://api.var.app/sync/'),
        client: MockClient((request) async {
          requestCount += 1;
          if (requestCount == 1) {
            return http.Response(
              jsonEncode(document.toJson()),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 404);
        }),
        tokenProvider: () async => null,
      );

      final fetched = await store.fetchLatestBackup(_user);
      final missing = await store.fetchLatestBackup(_user);

      expect(fetched?.nodes.single.title, 'Fetched note');
      expect(missing, isNull);
    },
  );

  test('rejects backup envelopes for another account', () async {
    final document = MindmapBackupDocument.create(
      sourceDevice: const SyncDeviceIdentity(id: 'phone', label: 'Phone'),
      exportedAt: DateTime(2026, 6, 19, 10),
      nodes: const [],
    );
    final store = HttpSyncRemoteBackupStore(
      endpoint: Uri.parse('https://api.var.app/sync'),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({'userId': 'other-user', 'backup': document.toJson()}),
          200,
        ),
      ),
    );

    expect(
      () => store.fetchLatestBackup(_user),
      throwsA(
        isA<SyncRemoteStoreException>().having(
          (error) => error.message,
          'message',
          'Remote backup response is invalid.',
        ),
      ),
    );
  });

  test('rejects oversized remote backup payloads', () async {
    final store = HttpSyncRemoteBackupStore(
      endpoint: Uri.parse('https://api.var.app/sync'),
      maxPayloadBytes: 8,
      client: MockClient(
        (request) async => http.Response('{"backup":{}}', 200),
      ),
    );

    expect(
      () => store.fetchLatestBackup(_user),
      throwsA(
        isA<SyncRemoteStoreException>().having(
          (error) => error.message,
          'message',
          'Remote backup payload is too large.',
        ),
      ),
    );
  });
  test(
    'throws a typed exception when the remote server rejects the request',
    () async {
      final store = HttpSyncRemoteBackupStore(
        endpoint: Uri.parse('https://api.var.app/sync'),
        client: MockClient((request) async => http.Response('Nope', 500)),
      );

      expect(
        () => store.fetchLatestBackup(_user),
        throwsA(isA<SyncRemoteStoreException>()),
      );
    },
  );
}

const _user = SyncUser(id: 'user-1', email: 'user@example.com');

MindmapNode _node({required String id, required String title}) {
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: title,
    day: DateTime(2026, 6, 19),
    now: DateTime(2026, 6, 19, 8),
  );
}
