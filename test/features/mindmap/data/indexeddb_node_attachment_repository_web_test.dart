@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:var_app/features/mindmap/data/indexeddb_node_attachment_repository_web.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:web/web.dart' as web;

void main() {
  late String databaseName;
  IndexedDbNodeAttachmentRepository? repository;

  setUp(() {
    databaseName = 'var_attachment_test_${const Uuid().v4()}';
  });

  tearDown(() async {
    repository?.close();
    await _deleteDatabase(databaseName);
  });

  test('persists raw attachment bytes across reopen', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final attachment = await repository!.importBytes(
      bytes: [1, 2, 3, 4],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    repository!.close();

    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );

    expect(
      (await repository!.resolve(attachment.id))?.checksum,
      attachment.checksum,
    );
    expect(await repository!.readBytes(attachment.id), [1, 2, 3, 4]);
    expect(await repository!.buildManifest(), hasLength(1));
  });

  test('stores metadata and raw Uint8List in separate stores', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final attachment = await repository!.importBytes(
      bytes: [7, 8, 9],
      fileName: 'clip.mp4',
      mimeType: 'video/mp4',
    );
    repository!.close();
    repository = null;

    final database = await _openRaw(databaseName);
    final transaction = database.transaction(
      ['metadata'.toJS, 'blobs'.toJS].toJS,
      'readonly',
    );
    final completion = _transactionComplete(transaction);
    final metadataRequest = transaction
        .objectStore('metadata')
        .get(attachment.id.toJS);
    final blobRequest = transaction
        .objectStore('blobs')
        .get(attachment.id.toJS);
    final metadata = await _requestObject(metadataRequest);
    final blob = await _requestObject(blobRequest);
    await completion;
    database.close();

    expect(metadata, isA<Map<Object?, Object?>>());
    expect((metadata! as Map<Object?, Object?>)['id'], attachment.id);
    expect(blob, isA<Uint8List>());
    expect(blob, [7, 8, 9]);
  });

  test('removes metadata-only incomplete write on reopen', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    repository!.close();
    repository = null;
    final id = const Uuid().v4();
    await _putRaw(
      databaseName,
      storeName: 'metadata',
      key: id,
      value: {
        'id': id,
        'fileName': 'orphan.png',
        'mimeType': 'image/png',
        'byteLength': 3,
        'checksum': '0' * 64,
        'createdAt': DateTime.utc(2026).toIso8601String(),
      }.jsify(),
    );

    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );

    expect(await repository!.resolve(id), isNull);
    expect(await _countRaw(databaseName, 'metadata'), 0);
    expect(await _countRaw(databaseName, 'blobs'), 0);
  });

  test('removes blob-only incomplete write on reopen', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    repository!.close();
    repository = null;
    final id = const Uuid().v4();
    await _putRaw(
      databaseName,
      storeName: 'blobs',
      key: id,
      value: Uint8List.fromList([4, 5, 6]).toJS,
    );

    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );

    expect(await repository!.resolve(id), isNull);
    expect(await _countRaw(databaseName, 'metadata'), 0);
    expect(await _countRaw(databaseName, 'blobs'), 0);
  });

  test('removes checksum-corrupt pair on reopen', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final attachment = await repository!.importBytes(
      bytes: [1, 2, 3],
      fileName: 'photo.png',
      mimeType: 'image/png',
    );
    repository!.close();
    repository = null;
    await _putRaw(
      databaseName,
      storeName: 'blobs',
      key: attachment.id,
      value: Uint8List.fromList([9, 9, 9]).toJS,
    );

    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );

    expect(await repository!.resolve(attachment.id), isNull);
    expect(await repository!.readBytes(attachment.id), isNull);
  });

  test('serializes concurrent imports without losing records', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );

    final attachments = await Future.wait(
      List.generate(
        12,
        (index) => repository!.importBytes(
          bytes: [index + 1, index + 2],
          fileName: 'image_$index.png',
          mimeType: 'image/png',
        ),
      ),
    );

    expect(attachments.map((value) => value.id).toSet(), hasLength(12));
    expect(await repository!.buildManifest(), hasLength(12));
  });

  test(
    'reconcile removes malformed non-string keys without alignment loss',
    () async {
      repository = await IndexedDbNodeAttachmentRepository.open(
        databaseName: databaseName,
      );
      repository!.close();
      repository = null;
      final id = const Uuid().v4();
      final metadata = {
        'id': id,
        'fileName': 'malformed.png',
        'mimeType': 'image/png',
        'byteLength': 3,
        'checksum': '0' * 64,
        'createdAt': DateTime.utc(2026).toIso8601String(),
      }.jsify();
      await _putRawKey(
        databaseName,
        storeName: 'metadata',
        key: 42.toJS,
        value: metadata,
      );
      await _putRawKey(
        databaseName,
        storeName: 'blobs',
        key: 42.toJS,
        value: Uint8List.fromList([1, 2, 3]).toJS,
      );

      repository = await IndexedDbNodeAttachmentRepository.open(
        databaseName: databaseName,
      );

      expect(await repository!.buildManifest(), isEmpty);
      expect(await _countRaw(databaseName, 'metadata'), 0);
      expect(await _countRaw(databaseName, 'blobs'), 0);
    },
  );

  test('manifest verifies blob records one at a time', () async {
    var activeReads = 0;
    var maxActiveReads = 0;
    var completedReads = 0;
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
      onManifestBlobRetentionForTesting: (retained) async {
        if (retained) {
          activeReads += 1;
          if (activeReads > maxActiveReads) maxActiveReads = activeReads;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          completedReads += 1;
        } else {
          activeReads -= 1;
        }
      },
    );
    await Future.wait(
      List.generate(
        8,
        (index) => repository!.importBytes(
          bytes: [index + 1, index + 2, index + 3],
          fileName: 'bounded_$index.png',
          mimeType: 'image/png',
        ),
      ),
    );

    final manifest = await repository!.buildManifest();

    expect(manifest, hasLength(8));
    expect(completedReads, 8);
    expect(maxActiveReads, 1);
  });
  test('exportBytes returns verified raw bytes', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final attachment = await repository!.importBytes(
      bytes: [8, 6, 4, 2],
      fileName: 'export.png',
      mimeType: 'image/png',
    );

    expect(await repository!.exportBytes(attachment.id), [8, 6, 4, 2]);
  });

  test('delete removes metadata and blob', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final attachment = await repository!.importBytes(
      bytes: [5, 4, 3],
      fileName: 'delete.png',
      mimeType: 'image/png',
    );

    await repository!.delete(attachment.id);

    expect(await repository!.resolve(attachment.id), isNull);
    expect(await repository!.readBytes(attachment.id), isNull);
    expect(await _countRaw(databaseName, 'metadata'), 0);
    expect(await _countRaw(databaseName, 'blobs'), 0);
  });

  test('manifest stays deleted after reopen', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final kept = await repository!.importBytes(
      bytes: [1, 1, 1],
      fileName: 'kept.png',
      mimeType: 'image/png',
    );
    final deleted = await repository!.importBytes(
      bytes: [2, 2, 2],
      fileName: 'deleted.png',
      mimeType: 'image/png',
    );
    await repository!.delete(deleted.id);
    repository!.close();

    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
    );
    final manifest = await repository!.buildManifest();

    expect(manifest.map((entry) => entry.attachment.id), [kept.id]);
    expect(await repository!.resolve(deleted.id), isNull);
  });

  test('quota failure has stable FormatException', () async {
    repository = await IndexedDbNodeAttachmentRepository.open(
      databaseName: databaseName,
      afterWriteStartedForTesting: (transaction) async {
        transaction.abort();
        return 'QuotaExceededError';
      },
    );

    await expectLater(
      repository!.importBytes(
        bytes: [1, 2, 3],
        fileName: 'quota.png',
        mimeType: 'image/png',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Web attachment storage is full.',
        ),
      ),
    );
    expect(await repository!.buildManifest(), isEmpty);
    expect(await _countRaw(databaseName, 'metadata'), 0);
    expect(await _countRaw(databaseName, 'blobs'), 0);
  });
  test(
    'restore validates checksum and preserves identical collision',
    () async {
      repository = await IndexedDbNodeAttachmentRepository.open(
        databaseName: databaseName,
      );
      final source = await repository!.importBytes(
        bytes: [3, 2, 1],
        fileName: 'photo.png',
        mimeType: 'image/png',
      );

      final plan = await repository!.preflightRestore([
        NodeAttachmentRestoreItem(attachment: source, bytes: [3, 2, 1]),
      ]);

      expect(plan.itemsToImport, isEmpty);
      expect(plan.identicalAttachmentIds, {source.id});
      await expectLater(
        repository!.restoreBytes(attachment: source, bytes: [3, 2, 0]),
        throwsFormatException,
      );
    },
  );
}

Future<web.IDBDatabase> _openRaw(String name) {
  final request = web.window.indexedDB.open(name, 1);
  final completer = Completer<web.IDBDatabase>();
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result! as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error ?? StateError('open failed'));
  }).toJS;
  return completer.future;
}

Future<void> _deleteDatabase(String name) {
  final request = web.window.indexedDB.deleteDatabase(name);
  final completer = Completer<void>();
  request.onsuccess = ((web.Event _) => completer.complete()).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error ?? StateError('delete failed'));
  }).toJS;
  request.onblocked = ((web.Event _) {
    completer.completeError(StateError('delete blocked'));
  }).toJS;
  return completer.future;
}

Future<void> _putRaw(
  String databaseName, {
  required String storeName,
  required String key,
  required JSAny? value,
}) async {
  final database = await _openRaw(databaseName);
  final transaction = database.transaction(storeName.toJS, 'readwrite');
  final completion = _transactionComplete(transaction);
  transaction.objectStore(storeName).put(value, key.toJS);
  await completion;
  database.close();
}

Future<void> _putRawKey(
  String databaseName, {
  required String storeName,
  required JSAny key,
  required JSAny? value,
}) async {
  final database = await _openRaw(databaseName);
  final transaction = database.transaction(storeName.toJS, 'readwrite');
  final completion = _transactionComplete(transaction);
  transaction.objectStore(storeName).put(value, key);
  await completion;
  database.close();
}

Future<int> _countRaw(String databaseName, String storeName) async {
  final database = await _openRaw(databaseName);
  final transaction = database.transaction(storeName.toJS, 'readonly');
  final completion = _transactionComplete(transaction);
  final request = transaction.objectStore(storeName).count();
  await _requestDone(request);
  final count = request.result!.dartify()! as int;
  await completion;
  database.close();
  return count;
}

Future<Object?> _requestObject(web.IDBRequest request) async {
  await _requestDone(request);
  return request.result?.dartify();
}

Future<void> _requestDone(web.IDBRequest request) {
  final completer = Completer<void>();
  request.onsuccess = ((web.Event _) => completer.complete()).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(request.error ?? StateError('request failed'));
  }).toJS;
  return completer.future;
}

Future<void> _transactionComplete(web.IDBTransaction transaction) {
  final completer = Completer<void>();
  transaction.oncomplete = ((web.Event _) => completer.complete()).toJS;
  transaction.onabort = ((web.Event _) {
    completer.completeError(
      transaction.error ?? StateError('transaction aborted'),
    );
  }).toJS;
  transaction.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        transaction.error ?? StateError('transaction failed'),
      );
    }
  }).toJS;
  return completer.future;
}
