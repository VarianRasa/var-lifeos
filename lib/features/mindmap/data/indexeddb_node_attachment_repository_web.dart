library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import '../domain/node_attachment.dart';

const String _metadataStore = 'metadata';
const String _blobStore = 'blobs';
const int _databaseVersion = 1;
const Uuid _uuid = Uuid();

final class IndexedDbNodeAttachmentRepository
    implements NodeAttachmentRepository, NodeAttachmentRestoreRepository {
  IndexedDbNodeAttachmentRepository._(
    this._database, {
    Future<String?> Function(web.IDBTransaction transaction)?
    afterWriteStartedForTesting,
    Future<void> Function(bool retained)? onManifestBlobRetentionForTesting,
  }) : _afterWriteStartedForTesting = afterWriteStartedForTesting,
       _onManifestBlobRetentionForTesting = onManifestBlobRetentionForTesting;

  final web.IDBDatabase _database;
  final Future<String?> Function(web.IDBTransaction transaction)?
  _afterWriteStartedForTesting;
  final Future<void> Function(bool retained)?
  _onManifestBlobRetentionForTesting;
  Future<void> _operationTail = Future<void>.value();

  static Future<IndexedDbNodeAttachmentRepository> open({
    String databaseName = 'var_node_attachments',
    Future<String?> Function(web.IDBTransaction transaction)?
    afterWriteStartedForTesting,
    Future<void> Function(bool retained)? onManifestBlobRetentionForTesting,
  }) async {
    final request = web.window.indexedDB.open(databaseName, _databaseVersion);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result! as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_metadataStore)) {
        database.createObjectStore(_metadataStore);
      }
      if (!database.objectStoreNames.contains(_blobStore)) {
        database.createObjectStore(_blobStore);
      }
    }).toJS;
    final database = await _requestResult<web.IDBDatabase>(request);
    database.onversionchange = ((web.Event _) => database.close()).toJS;
    final repository = IndexedDbNodeAttachmentRepository._(
      database,
      afterWriteStartedForTesting: afterWriteStartedForTesting,
      onManifestBlobRetentionForTesting: onManifestBlobRetentionForTesting,
    );
    await repository._enqueue(repository._reconcile);
    return repository;
  }

  void close() => _database.close();

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => _enqueue(() async {
    final validated = await _validatedAttachment(
      id: _uuid.v4(),
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      createdAt: DateTime.now().toUtc(),
    );
    await _writePair(validated.attachment, validated.bytes, insertOnly: true);
    return validated.attachment;
  });

  @override
  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  }) => _enqueue(() async {
    _validateAttachmentId(attachment.id);
    final current = await _readPair(attachment.id);
    if (current != null) {
      throw const FormatException('Attachment ID already exists.');
    }
    final validated = await _validatedAttachment(
      id: attachment.id,
      bytes: bytes,
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      createdAt: attachment.createdAt.toUtc(),
      expectedLength: attachment.byteLength,
      expectedChecksum: attachment.checksum,
    );
    await _writePair(validated.attachment, validated.bytes, insertOnly: true);
    return validated.attachment;
  });

  @override
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  ) => _enqueue(() async {
    final seen = <String>{};
    final itemsToImport = <NodeAttachmentRestoreItem>[];
    final identicalIds = <String>{};
    for (final item in items) {
      if (!seen.add(item.attachment.id)) {
        throw const FormatException('Duplicate attachment ID.');
      }
      final validated = await _validatedAttachment(
        id: item.attachment.id,
        bytes: item.bytes,
        fileName: item.attachment.fileName,
        mimeType: item.attachment.mimeType,
        createdAt: item.attachment.createdAt.toUtc(),
        expectedLength: item.attachment.byteLength,
        expectedChecksum: item.attachment.checksum,
      );
      final current = await _readPair(item.attachment.id);
      if (current == null) {
        itemsToImport.add(item);
      } else if (_sameAttachment(current.attachment, validated.attachment) &&
          _sameBytes(current.bytes, validated.bytes)) {
        identicalIds.add(item.attachment.id);
      } else {
        throw const FormatException('Attachment ID collision.');
      }
    }
    return NodeAttachmentRestorePlan(
      itemsToImport: List.unmodifiable(itemsToImport),
      identicalAttachmentIds: Set.unmodifiable(identicalIds),
    );
  });

  @override
  Future<NodeAttachment?> resolve(String attachmentId) => _enqueue(() async {
    _validateAttachmentId(attachmentId);
    return (await _readVerifiedPair(attachmentId))?.attachment;
  });

  @override
  Future<List<int>?> readBytes(String attachmentId) => _enqueue(() async {
    _validateAttachmentId(attachmentId);
    return (await _readVerifiedPair(attachmentId))?.bytes;
  });

  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      readBytes(attachmentId);

  @override
  Future<void> delete(String attachmentId) => _enqueue(() async {
    _validateAttachmentId(attachmentId);
    final transaction = _database.transaction(
      [_metadataStore.toJS, _blobStore.toJS].toJS,
      'readwrite',
    );
    final completion = _transactionComplete(transaction);
    transaction.objectStore(_metadataStore).delete(attachmentId.toJS);
    transaction.objectStore(_blobStore).delete(attachmentId.toJS);
    await completion;
  });

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() =>
      _enqueue(() async {
        final metadataRecords = await _cursorRecords(_metadataStore);
        final entries = <NodeAttachmentManifestEntry>[];
        for (final record in metadataRecords) {
          final id = record.dartKey;
          final attachment = _decodeAttachment(record.value);
          if (id is! String || attachment == null || attachment.id != id) {
            await _deleteRawKey(record.key);
            continue;
          }
          final pair = await _readPair(id);
          if (pair == null) {
            await _deletePair(id);
            continue;
          }
          await _onManifestBlobRetentionForTesting?.call(true);
          try {
            if (await _isVerified(pair)) {
              entries.add(
                NodeAttachmentManifestEntry(
                  version: nodeAttachmentManifestVersion,
                  attachment: pair.attachment,
                ),
              );
            } else {
              await _deletePair(id);
            }
          } finally {
            await _onManifestBlobRetentionForTesting?.call(false);
          }
        }
        entries.sort(
          (left, right) => left.attachment.id.compareTo(right.attachment.id),
        );
        return List.unmodifiable(entries);
      });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _reconcile() async {
    final metadataRecords = await _cursorRecords(_metadataStore);
    final validIds = <String>{};
    for (final record in metadataRecords) {
      final id = record.dartKey;
      final attachment = _decodeAttachment(record.value);
      if (id is! String || attachment == null || attachment.id != id) {
        await _deleteRawKey(record.key);
        continue;
      }
      final pair = await _readPair(id);
      if (pair == null || !await _isVerified(pair)) {
        await _deletePair(id);
        continue;
      }
      validIds.add(id);
    }
    final blobKeys = await _cursorRecords(_blobStore, keysOnly: true);
    for (final record in blobKeys) {
      final id = record.dartKey;
      if (id is! String || !validIds.contains(id)) {
        await _deleteRawKey(record.key);
      }
    }
  }

  Future<_StoredPair?> _readPair(String id) async {
    final transaction = _database.transaction(
      [_metadataStore.toJS, _blobStore.toJS].toJS,
      'readonly',
    );
    final completion = _transactionComplete(transaction);
    final metadataRequest = transaction
        .objectStore(_metadataStore)
        .get(id.toJS);
    final blobRequest = transaction.objectStore(_blobStore).get(id.toJS);
    final metadataRaw = await _requestObject(metadataRequest);
    final blobRaw = await _requestObject(blobRequest);
    await completion;
    final attachment = _decodeAttachment(metadataRaw);
    final bytes = _decodeBytes(blobRaw);
    if (attachment == null || bytes == null || attachment.id != id) return null;
    return _StoredPair(attachment, bytes);
  }

  Future<_StoredPair?> _readVerifiedPair(String id) async {
    final pair = await _readPair(id);
    if (pair == null || !await _isVerified(pair)) {
      await _deletePair(id);
      return null;
    }
    return pair;
  }

  Future<List<_CursorRecord>> _cursorRecords(
    String storeName, {
    bool keysOnly = false,
  }) async {
    final transaction = _database.transaction(storeName.toJS, 'readonly');
    final completion = _transactionComplete(transaction);
    final request = keysOnly
        ? transaction.objectStore(storeName).openKeyCursor()
        : transaction.objectStore(storeName).openCursor();
    final records = <_CursorRecord>[];
    final cursorDone = Completer<void>();
    request.onsuccess = ((web.Event _) {
      if (cursorDone.isCompleted) return;
      final result = request.result;
      if (result == null) {
        cursorDone.complete();
        return;
      }
      final cursor = result as web.IDBCursor;
      final key = cursor.key!;
      records.add(
        _CursorRecord(
          key: key,
          dartKey: key.dartify(),
          value: keysOnly
              ? null
              : (result as web.IDBCursorWithValue).value?.dartify(),
        ),
      );
      cursor.continue_();
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!cursorDone.isCompleted) {
        cursorDone.completeError(
          request.error ?? StateError('IndexedDB cursor failed.'),
        );
      }
    }).toJS;
    await cursorDone.future;
    await completion;
    return records;
  }

  Future<void> _writePair(
    NodeAttachment attachment,
    Uint8List bytes, {
    required bool insertOnly,
  }) async {
    final transaction = _database.transaction(
      [_metadataStore.toJS, _blobStore.toJS].toJS,
      'readwrite',
    );
    final completion = _transactionComplete(transaction);
    final metadataStore = transaction.objectStore(_metadataStore);
    final blobStore = transaction.objectStore(_blobStore);
    final metadata = _encodeAttachment(attachment).jsify();
    final key = attachment.id.toJS;
    if (insertOnly) {
      metadataStore.add(metadata, key);
      blobStore.add(bytes.toJS, key);
    } else {
      metadataStore.put(metadata, key);
      blobStore.put(bytes.toJS, key);
    }
    final injectedErrorName = await _afterWriteStartedForTesting?.call(
      transaction,
    );
    try {
      await completion;
    } catch (_) {
      if (injectedErrorName == null) {
        if (transaction.error?.name == 'QuotaExceededError') {
          throw const FormatException('Web attachment storage is full.');
        }
        rethrow;
      }
    }
    if (injectedErrorName == 'QuotaExceededError') {
      throw const FormatException('Web attachment storage is full.');
    }
  }

  Future<void> _deleteRawKey(JSAny key) async {
    final transaction = _database.transaction(
      [_metadataStore.toJS, _blobStore.toJS].toJS,
      'readwrite',
    );
    final completion = _transactionComplete(transaction);
    transaction.objectStore(_metadataStore).delete(key);
    transaction.objectStore(_blobStore).delete(key);
    await completion;
  }

  Future<void> _deletePair(String id) async {
    final transaction = _database.transaction(
      [_metadataStore.toJS, _blobStore.toJS].toJS,
      'readwrite',
    );
    final completion = _transactionComplete(transaction);
    transaction.objectStore(_metadataStore).delete(id.toJS);
    transaction.objectStore(_blobStore).delete(id.toJS);
    await completion;
  }
}

final class _CursorRecord {
  const _CursorRecord({
    required this.key,
    required this.dartKey,
    required this.value,
  });

  final JSAny key;
  final Object? dartKey;
  final Object? value;
}

final class _ValidatedAttachment {
  const _ValidatedAttachment(this.attachment, this.bytes);
  final NodeAttachment attachment;
  final Uint8List bytes;
}

final class _StoredPair {
  const _StoredPair(this.attachment, this.bytes);
  final NodeAttachment attachment;
  final Uint8List bytes;
}

Future<_ValidatedAttachment> _validatedAttachment({
  required String id,
  required List<int> bytes,
  required String fileName,
  required String mimeType,
  required DateTime createdAt,
  int? expectedLength,
  String? expectedChecksum,
}) async {
  _validateAttachmentId(id);
  if (bytes.isEmpty) {
    throw const FormatException('Attachment must not be empty.');
  }
  if (bytes.length > maxNodeAttachmentBytes) {
    throw const FormatException('Attachment exceeds maximum size.');
  }
  if (bytes.any((value) => value < 0 || value > 255)) {
    throw const FormatException('Attachment contains invalid bytes.');
  }
  final name = _normalizeFileName(fileName);
  final mime = _validateMimeType(mimeType, name);
  final immutableBytes = Uint8List.fromList(bytes);
  final checksum = await _checksum(immutableBytes);
  if ((expectedLength != null && expectedLength != immutableBytes.length) ||
      (expectedChecksum != null && expectedChecksum != checksum)) {
    throw const FormatException('Attachment checksum or size is invalid.');
  }
  return _ValidatedAttachment(
    NodeAttachment(
      id: id,
      fileName: name,
      mimeType: mime,
      byteLength: immutableBytes.length,
      checksum: checksum,
      createdAt: createdAt.toUtc(),
    ),
    immutableBytes,
  );
}

Map<String, Object?> _encodeAttachment(NodeAttachment value) => {
  'id': value.id,
  'fileName': value.fileName,
  'mimeType': value.mimeType,
  'byteLength': value.byteLength,
  'checksum': value.checksum,
  'createdAt': value.createdAt.toIso8601String(),
};

NodeAttachment? _decodeAttachment(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  final id = raw['id'];
  final fileName = raw['fileName'];
  final mimeType = raw['mimeType'];
  final byteLength = raw['byteLength'];
  final checksum = raw['checksum'];
  final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
  if (id is! String ||
      fileName is! String ||
      mimeType is! String ||
      byteLength is! int ||
      checksum is! String ||
      createdAt == null ||
      checksum.length != 64 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
    return null;
  }
  try {
    _validateAttachmentId(id);
    final name = _normalizeFileName(fileName);
    final mime = _validateMimeType(mimeType, name);
    if (name != fileName ||
        mime != mimeType ||
        byteLength <= 0 ||
        byteLength > maxNodeAttachmentBytes) {
      return null;
    }
    return NodeAttachment(
      id: id,
      fileName: name,
      mimeType: mime,
      byteLength: byteLength,
      checksum: checksum,
      createdAt: createdAt.toUtc(),
    );
  } on FormatException {
    return null;
  }
}

Uint8List? _decodeBytes(Object? raw) {
  if (raw is Uint8List) return Uint8List.fromList(raw);
  return null;
}

Future<bool> _isVerified(_StoredPair pair) async =>
    pair.bytes.length == pair.attachment.byteLength &&
    await _checksum(pair.bytes) == pair.attachment.checksum;

Future<String> _checksum(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _normalizeFileName(String fileName) {
  final name = p.basename(fileName.replaceAll('\\', '/').trim()).trim();
  final stem = p.basenameWithoutExtension(name).toUpperCase();
  const reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };
  const invalidCodes = {34, 42, 47, 58, 60, 62, 63, 92, 124};
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      reserved.contains(stem) ||
      name.codeUnits.any(
        (value) => value < 32 || invalidCodes.contains(value),
      )) {
    throw const FormatException('Invalid attachment filename.');
  }
  return name;
}

String _validateMimeType(String mimeType, String fileName) {
  final mime = mimeType.trim().toLowerCase();
  if (!supportedNodeAttachmentMimeTypes.contains(mime) ||
      (mime == 'application/octet-stream' &&
          _unsafeGenericExtensions.contains(
            p.extension(fileName).toLowerCase(),
          )) ||
      (mime != 'application/octet-stream' &&
          !_extensionsForMime(
            mime,
          ).contains(p.extension(fileName).toLowerCase()))) {
    throw const FormatException('Invalid attachment metadata.');
  }
  return mime;
}

void _validateAttachmentId(String id) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(id)) {
    throw const FormatException('Invalid attachment ID.');
  }
}

const Set<String> _unsafeGenericExtensions = {
  '.bat',
  '.cmd',
  '.com',
  '.dll',
  '.exe',
  '.msi',
  '.ps1',
  '.scr',
};

Set<String> _extensionsForMime(String mime) => switch (mime) {
  'image/gif' => {'.gif'},
  'image/jpeg' => {'.jpg', '.jpeg'},
  'image/png' => {'.png'},
  'image/webp' => {'.webp'},
  'video/mp4' => {'.mp4'},
  'video/quicktime' => {'.mov'},
  'video/webm' => {'.webm'},
  'audio/aac' => {'.aac'},
  'audio/m4a' => {'.m4a'},
  'audio/mpeg' => {'.mp3'},
  'audio/mp4' => {'.m4a', '.mp4'},
  'audio/ogg' => {'.ogg', '.oga'},
  'audio/wav' => {'.wav'},
  'audio/webm' => {'.webm'},
  _ => const {},
};

bool _sameAttachment(NodeAttachment first, NodeAttachment second) =>
    first.id == second.id &&
    first.fileName == second.fileName &&
    first.mimeType == second.mimeType &&
    first.byteLength == second.byteLength &&
    first.checksum == second.checksum &&
    first.createdAt.toUtc() == second.createdAt.toUtc();

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

Future<T> _requestResult<T extends JSAny>(web.IDBRequest request) {
  final completer = Completer<T>();
  request.onsuccess = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(request.result! as T);
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        request.error ?? StateError('IndexedDB request failed.'),
      );
    }
  }).toJS;
  return completer.future;
}

Future<Object?> _requestObject(web.IDBRequest request) async {
  await _requestDone(request);
  return request.result?.dartify();
}

Future<void> _requestDone(web.IDBRequest request) {
  final completer = Completer<void>();
  request.onsuccess = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        request.error ?? StateError('IndexedDB request failed.'),
      );
    }
  }).toJS;
  return completer.future;
}

Future<void> _transactionComplete(web.IDBTransaction transaction) {
  final completer = Completer<void>();
  transaction.oncomplete = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  transaction.onabort = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        transaction.error ?? StateError('IndexedDB transaction aborted.'),
      );
    }
  }).toJS;
  transaction.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(
        transaction.error ?? StateError('IndexedDB transaction failed.'),
      );
    }
  }).toJS;
  return completer.future;
}
