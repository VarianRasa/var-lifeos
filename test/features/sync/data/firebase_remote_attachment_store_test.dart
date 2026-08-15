import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/data/firebase_remote_attachment_store.dart';
import 'package:var_app/features/sync/domain/remote_attachment_store.dart';

void main() {
  test('firebase.json registers hardened Storage rules', () {
    final firebaseConfig =
        jsonDecode(File('firebase.json').readAsStringSync())
            as Map<String, Object?>;
    final storage = firebaseConfig['storage']! as Map<String, Object?>;
    final rules = File(storage['rules']! as String).readAsStringSync();
    expect(storage['rules'], 'storage.rules');
    expect(rules, contains('match /attachments/{userId}/{attachmentId}'));
    expect(rules, contains('allow delete: if false;'));
    expect(rules, contains('match /{path=**}'));
  });

  test('upload validates stream then writes canonical metadata', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final gateway = _FakeGateway();
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );
    final attachment = await _attachment(bytes);
    await store.upload(
      metadata: attachment,
      bytes: Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]),
    );
    expect(gateway.lastKey, 'attachments/user_123/${attachment.id}');
    expect(gateway.lastBytes, bytes);
    expect(gateway.lastContentType, 'image/png');
    expect(gateway.lastMetadata, {
      'schemaVersion': '1',
      'attachmentId': attachment.id,
      'checksum': attachment.checksum,
      'byteLength': '4',
      'mimeType': 'image/png',
      'fileName': 'photo.png',
    });
  });

  test('upload rejects invalid content before put', () async {
    final gateway = _FakeGateway();
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );
    final attachment = await _attachment(Uint8List.fromList([1, 2, 3, 4]));
    for (final stream in <Stream<List<int>>>[
      Stream.value([1, 2, 999, 4]),
      Stream.value([1, 2, 3]),
      Stream.value([4, 3, 2, 1]),
    ]) {
      await expectLater(
        store.upload(metadata: attachment, bytes: stream),
        throwsA(
          isA<RemoteAttachmentException>().having(
            (e) => e.kind,
            'kind',
            RemoteAttachmentFailureKind.integrity,
          ),
        ),
      );
    }
    expect(gateway.putCount, 0);
  });

  test('head validates metadata and missing returns null', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final attachment = await _attachment(bytes);
    final gateway = _FakeGateway()..object = _objectFor(attachment, bytes);
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );
    expect(
      await store.head(attachment.id),
      RemoteAttachmentMetadata.fromNodeAttachment(attachment),
    );
    gateway.object = null;
    expect(await store.head(attachment.id), isNull);
  });

  test('head rejects metadata for a different attachment ID', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final attachment = await _attachment(bytes);
    final gateway = _FakeGateway()
      ..object = FirebaseStorageObject(
        bytes: bytes,
        contentType: attachment.mimeType,
        customMetadata: {
          ..._objectFor(attachment, bytes).customMetadata!,
          'attachmentId': '123e4567-e89b-12d3-a456-426614174001',
        },
      );
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );

    await expectLater(
      store.head(attachment.id),
      throwsA(
        isA<RemoteAttachmentException>().having(
          (error) => error.kind,
          'kind',
          RemoteAttachmentFailureKind.invalidMetadata,
        ),
      ),
    );
  });

  test('download enforces max size and verifies checksum', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final attachment = await _attachment(bytes);
    final gateway = _FakeGateway()..object = _objectFor(attachment, bytes);
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );
    expect((await store.download(attachment.id)).bytes, bytes);
    expect(gateway.lastMaxDownloadBytes, maxRemoteAttachmentBytes);
    gateway.object = _objectFor(attachment, Uint8List.fromList([4, 3, 2, 1]));
    await expectLater(
      store.download(attachment.id),
      throwsA(
        isA<RemoteAttachmentException>().having(
          (e) => e.kind,
          'kind',
          RemoteAttachmentFailureKind.integrity,
        ),
      ),
    );
  });

  test('unauthenticated calls reject before gateway access', () async {
    final gateway = _FakeGateway();
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => null,
    );
    await expectLater(
      store.head(_id),
      throwsA(
        isA<RemoteAttachmentException>().having(
          (e) => e.kind,
          'kind',
          RemoteAttachmentFailureKind.unauthorized,
        ),
      ),
    );
    expect(gateway.accessCount, 0);
  });

  test('gateway failures map to stable kinds', () async {
    final expected = <String, RemoteAttachmentFailureKind>{
      'unauthorized': RemoteAttachmentFailureKind.unauthorized,
      'object-not-found': RemoteAttachmentFailureKind.notFound,
      'retry-limit-exceeded': RemoteAttachmentFailureKind.unavailable,
      'invalid-checksum': RemoteAttachmentFailureKind.integrity,
      'unknown': RemoteAttachmentFailureKind.transport,
    };
    for (final entry in expected.entries) {
      final gateway = _FakeGateway()
        ..error = FirebaseStorageGatewayException(entry.key);
      final store = FirebaseRemoteAttachmentStore(
        gateway: gateway,
        userIdProvider: () => 'user_123',
      );
      await expectLater(
        store.head(_id),
        throwsA(
          isA<RemoteAttachmentException>().having(
            (e) => e.kind,
            entry.key,
            entry.value,
          ),
        ),
      );
    }
  });

  test('delete remains unsupported despite valid tombstone', () async {
    final gateway = _FakeGateway();
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => 'user_123',
    );
    await expectLater(
      store.delete(attachmentId: _id, tombstoneVersion: 'v1'),
      throwsA(
        isA<RemoteAttachmentException>().having(
          (e) => e.kind,
          'kind',
          RemoteAttachmentFailureKind.unavailable,
        ),
      ),
    );
    expect(gateway.accessCount, 0);
  });

  test(
    'upload rejects account change before write and never uses UID B',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final attachment = await _attachment(bytes);
      final controller = StreamController<List<int>>();
      final gateway = _FakeGateway();
      var userId = 'user_A';
      final store = FirebaseRemoteAttachmentStore(
        gateway: gateway,
        userIdProvider: () => userId,
      );

      final upload = store.upload(
        metadata: attachment,
        bytes: controller.stream,
      );
      controller.add(bytes);
      await Future<void>.delayed(Duration.zero);
      userId = 'user_B';
      await controller.close();

      await expectLater(upload, _unauthorized);
      expect(gateway.putCount, 0);
      expect(gateway.lastKey, isNot(contains('user_B')));
    },
  );

  test('head discards account A response after UID changes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final attachment = await _attachment(bytes);
    final gateway = _FakeGateway()
      ..headCompleter = Completer<FirebaseStorageObjectMetadata?>();
    var userId = 'user_A';
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => userId,
    );

    final head = store.head(attachment.id);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.lastKey, 'attachments/user_A/${attachment.id}');
    userId = 'user_B';
    gateway.headCompleter!.complete(_objectFor(attachment, bytes));

    await expectLater(head, _unauthorized);
    expect(gateway.lastKey, isNot(contains('user_B')));
  });

  test('download discards account A bytes after UID changes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final attachment = await _attachment(bytes);
    final gateway = _FakeGateway()
      ..getCompleter = Completer<FirebaseStorageObject?>();
    var userId = 'user_A';
    final store = FirebaseRemoteAttachmentStore(
      gateway: gateway,
      userIdProvider: () => userId,
    );

    final download = store.download(attachment.id);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.lastKey, 'attachments/user_A/${attachment.id}');
    userId = 'user_B';
    gateway.getCompleter!.complete(_objectFor(attachment, bytes));

    await expectLater(download, _unauthorized);
    expect(gateway.lastKey, isNot(contains('user_B')));
  });
}

const String _id = '123e4567-e89b-12d3-a456-426614174000';

final Matcher _unauthorized = throwsA(
  isA<RemoteAttachmentException>().having(
    (error) => error.kind,
    'kind',
    RemoteAttachmentFailureKind.unauthorized,
  ),
);

Future<NodeAttachment> _attachment(Uint8List bytes) async {
  final checksum = await Sha256().hash(bytes);
  return NodeAttachment(
    id: _id,
    fileName: 'photo.png',
    mimeType: 'image/png',
    byteLength: bytes.length,
    checksum: checksum.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
    createdAt: DateTime.utc(2026, 7, 15),
  );
}

FirebaseStorageObject _objectFor(NodeAttachment attachment, Uint8List bytes) =>
    FirebaseStorageObject(
      bytes: bytes,
      contentType: attachment.mimeType,
      customMetadata: {
        'schemaVersion': '1',
        'attachmentId': attachment.id,
        'checksum': attachment.checksum,
        'byteLength': attachment.byteLength.toString(),
        'mimeType': attachment.mimeType,
        'fileName': attachment.fileName,
      },
    );

final class _FakeGateway implements FirebaseStorageGateway {
  FirebaseStorageObject? object;
  FirebaseStorageGatewayException? error;
  Completer<FirebaseStorageObject?>? getCompleter;
  Completer<FirebaseStorageObjectMetadata?>? headCompleter;
  String? lastKey;
  Uint8List? lastBytes;
  String? lastContentType;
  Map<String, String>? lastMetadata;
  int? lastMaxDownloadBytes;
  int accessCount = 0;
  int putCount = 0;

  @override
  Future<FirebaseStorageObject?> get(
    String key, {
    required int maxBytes,
  }) async {
    accessCount++;
    lastKey = key;
    lastMaxDownloadBytes = maxBytes;
    if (error case final failure?) throw failure;
    if (getCompleter case final completer?) return completer.future;
    return object;
  }

  @override
  Future<FirebaseStorageObjectMetadata?> head(String key) async {
    accessCount++;
    lastKey = key;
    if (error case final failure?) throw failure;
    if (headCompleter case final completer?) return completer.future;
    final value = object;
    return value == null
        ? null
        : FirebaseStorageObjectMetadata(
            contentType: value.contentType,
            customMetadata: value.customMetadata,
          );
  }

  @override
  Future<void> put({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    accessCount++;
    putCount++;
    if (error case final failure?) throw failure;
    lastKey = key;
    lastBytes = bytes;
    lastContentType = contentType;
    lastMetadata = customMetadata;
  }
}
