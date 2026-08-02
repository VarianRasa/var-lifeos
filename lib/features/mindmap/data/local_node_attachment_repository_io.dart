library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/node_attachment.dart';

const Uuid _uuid = Uuid();

Future<NodeAttachmentRepository> openLocalNodeAttachmentRepository() async {
  final directory = await getApplicationSupportDirectory();
  return LocalNodeAttachmentRepository(
    root: Directory(p.join(directory.path, 'node_attachments')),
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
  if (raw is! Map<String, Object?>) return null;
  final id = raw['id'];
  final name = raw['fileName'];
  final mime = raw['mimeType'];
  final length = raw['byteLength'];
  final checksum = raw['checksum'];
  final created = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
  if (id is! String ||
      name is! String ||
      mime is! String ||
      length is! int ||
      checksum is! String ||
      created == null) {
    return null;
  }
  try {
    _validateAttachmentId(id);
    final safeName = _normalizeFileName(name);
    final safeMime = _validateMimeType(mime, safeName);
    if (length <= 0 || length > maxNodeAttachmentBytes) return null;
    return NodeAttachment(
      id: id,
      fileName: safeName,
      mimeType: safeMime,
      byteLength: length,
      checksum: checksum,
      createdAt: created.toUtc(),
    );
  } on FormatException {
    return null;
  }
}

void _validateBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    throw const FormatException('Attachment must not be empty.');
  }
  if (bytes.length > maxNodeAttachmentBytes) {
    throw const FormatException('Attachment exceeds maximum size.');
  }
  if (bytes.any((value) => value < 0 || value > 255)) {
    throw const FormatException('Attachment contains invalid bytes.');
  }
}

String _validateMimeType(String mimeType, String fileName) {
  final mime = mimeType.trim().toLowerCase();
  if (!supportedNodeAttachmentMimeTypes.contains(mime)) {
    throw const FormatException('Unsupported attachment MIME type.');
  }
  if (mime == 'application/octet-stream' &&
      _unsafeGenericExtensions.contains(p.extension(fileName).toLowerCase())) {
    throw const FormatException('Executable attachments are not allowed.');
  }
  if (mime != 'application/octet-stream' &&
      !_extensionsForMime(mime).contains(p.extension(fileName).toLowerCase())) {
    throw const FormatException(
      'Attachment extension does not match MIME type.',
    );
  }
  return mime;
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

String _normalizeFileName(String fileName) {
  final name = p.basename(fileName.trim()).trim();
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
  final invalid =
      name.isEmpty ||
      name == '.' ||
      name == '..' ||
      reserved.contains(stem) ||
      name.codeUnits.any((value) => value < 32 || invalidCodes.contains(value));
  if (invalid) throw const FormatException('Invalid attachment filename.');
  if (name.length <= 120) return name;
  return '${p.basenameWithoutExtension(name).substring(0, 100)}${p.extension(name)}';
}

void _validateAttachmentId(String id) {
  if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) || id.split('-').length != 5) {
    throw const FormatException('Invalid attachment ID.');
  }
}

Future<String> _checksum(List<int> bytes) async {
  final hash = await Sha256().hash(bytes);
  return hash.bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

final class LocalNodeAttachmentRepository
    implements NodeAttachmentRepository, NodeAttachmentRestoreRepository {
  LocalNodeAttachmentRepository({
    required Directory root,
    Future<void> Function()? beforeManifestReplace,
    Future<void> Function()? beforeTombstoneCleanup,
  }) : _root = root,
       _beforeManifestReplace = beforeManifestReplace,
       _beforeTombstoneCleanup = beforeTombstoneCleanup;
  final Directory _root;
  final Future<void> Function()? _beforeManifestReplace;
  final Future<void> Function()? _beforeTombstoneCleanup;
  Future<void> _transactionTail = Future.value();
  bool _initialized = false;

  @override
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  ) => _runTransaction(() async {
    final seen = <String>{};
    final existing = await _readManifest();
    final itemsToImport = <NodeAttachmentRestoreItem>[];
    final identicalIds = <String>{};
    for (final item in items) {
      final attachment = item.attachment;
      if (!seen.add(attachment.id)) {
        throw const FormatException('Duplicate attachment ID.');
      }
      _validateBytes(item.bytes);
      _validateAttachmentId(attachment.id);
      final safeName = _normalizeFileName(attachment.fileName);
      final safeMime = _validateMimeType(attachment.mimeType, safeName);
      final checksum = await _checksum(item.bytes);
      if (attachment.byteLength != item.bytes.length ||
          attachment.checksum != checksum ||
          attachment.fileName != safeName ||
          attachment.mimeType.trim().toLowerCase() != safeMime) {
        throw const FormatException('Attachment metadata is invalid.');
      }
      final current = existing[attachment.id];
      if (current == null) {
        if (await _attachmentFile(attachment.id).exists()) {
          throw const FormatException('Attachment path already exists.');
        }
        itemsToImport.add(item);
        continue;
      }
      final currentBytes = await _verifiedBytes(current);
      if (current.fileName != attachment.fileName ||
          current.mimeType != attachment.mimeType ||
          current.byteLength != attachment.byteLength ||
          current.checksum != attachment.checksum ||
          currentBytes == null ||
          !_sameBytes(currentBytes, item.bytes)) {
        throw const FormatException('Attachment ID collision.');
      }
      identicalIds.add(attachment.id);
    }
    return NodeAttachmentRestorePlan(
      itemsToImport: List.unmodifiable(itemsToImport),
      identicalAttachmentIds: Set.unmodifiable(identicalIds),
    );
  });

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) => _runTransaction(() async {
    _validateBytes(bytes);
    final safeName = _normalizeFileName(fileName);
    final safeMime = _validateMimeType(mimeType, safeName);
    final id = _uuid.v4();
    final attachment = NodeAttachment(
      id: id,
      fileName: safeName,
      mimeType: safeMime,
      byteLength: bytes.length,
      checksum: await _checksum(bytes),
      createdAt: DateTime.now().toUtc(),
    );
    await _root.create(recursive: true);
    final destination = _attachmentFile(id);
    final temporary = File('${destination.path}.tmp-${_uuid.v4()}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
      final entries = await _readManifest()
        ..[id] = attachment;
      await _writeManifest(entries);
      return attachment;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  });

  @override
  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  }) => _runTransaction(() async {
    _validateBytes(bytes);
    _validateAttachmentId(attachment.id);
    final safeName = _normalizeFileName(attachment.fileName);
    final safeMime = _validateMimeType(attachment.mimeType, safeName);
    final checksum = await _checksum(bytes);
    if (attachment.byteLength != bytes.length ||
        attachment.checksum != checksum) {
      throw const FormatException('Attachment checksum or size is invalid.');
    }
    final entries = await _readManifest();
    if (entries.containsKey(attachment.id) ||
        await _attachmentFile(attachment.id).exists()) {
      throw const FormatException('Attachment ID already exists.');
    }
    final restored = NodeAttachment(
      id: attachment.id,
      fileName: safeName,
      mimeType: safeMime,
      byteLength: bytes.length,
      checksum: checksum,
      createdAt: attachment.createdAt.toUtc(),
    );
    await _root.create(recursive: true);
    final destination = _attachmentFile(restored.id);
    final temporary = File('${destination.path}.tmp-${_uuid.v4()}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
      entries[restored.id] = restored;
      await _writeManifest(entries);
      return restored;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  });

  @override
  Future<NodeAttachment?> resolve(String attachmentId) =>
      _runTransaction(() async {
        _validateAttachmentId(attachmentId);
        final attachment = (await _readManifest())[attachmentId];
        return attachment != null && await _verifiedBytes(attachment) != null
            ? attachment
            : null;
      });

  @override
  Future<List<int>?> readBytes(String attachmentId) =>
      _runTransaction(() async {
        _validateAttachmentId(attachmentId);
        final attachment = (await _readManifest())[attachmentId];
        return attachment == null ? null : _verifiedBytes(attachment);
      });

  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      readBytes(attachmentId);

  @override
  Future<void> delete(String attachmentId) => _runTransaction(() async {
    _validateAttachmentId(attachmentId);
    final entries = await _readManifest();
    if (entries.remove(attachmentId) == null) return;
    final file = _attachmentFile(attachmentId);
    final tombstone = File('${file.path}.delete-${_uuid.v4()}');
    if (await file.exists()) {
      await file.rename(tombstone.path);
    }
    try {
      await _writeManifest(entries);
    } catch (_) {
      if (await tombstone.exists() && !await file.exists()) {
        await tombstone.rename(file.path);
      }
      rethrow;
    }
    try {
      await _beforeTombstoneCleanup?.call();
      if (await tombstone.exists()) {
        await tombstone.delete();
      }
    } on FileSystemException {
      // Committed metadata wins. Orphan stays confined inside root for later cleanup.
    } on StateError {
      // Test seam and cleanup failures must never resurrect committed deletion.
    }
  });

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() =>
      _runTransaction(() async {
        final result = <NodeAttachmentManifestEntry>[];
        for (final attachment in (await _readManifest()).values) {
          if (await _verifiedBytes(attachment) != null) {
            result.add(
              NodeAttachmentManifestEntry(
                version: nodeAttachmentManifestVersion,
                attachment: attachment,
              ),
            );
          }
        }
        result.sort((a, b) => a.attachment.id.compareTo(b.attachment.id));
        return List.unmodifiable(result);
      });

  Future<T> _runTransaction<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _transactionTail = _transactionTail.then((_) async {
      try {
        await _ensureInitialized();
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _root.create(recursive: true);
    final backups = await _knownFiles('manifest.json.backup-');
    final active = await _loadManifest(_manifestFile);
    Map<String, NodeAttachment>? recovered = active;
    if (active == null) {
      for (final backup in backups.reversed) {
        final candidate = await _loadManifest(backup);
        if (candidate != null) {
          if (await _manifestFile.exists()) await _manifestFile.delete();
          await backup.rename(_manifestFile.path);
          recovered = candidate;
          break;
        }
      }
    }
    final entries = recovered ?? <String, NodeAttachment>{};
    await _reconcileKnownOrphans(entries.keys.toSet());
    _initialized = true;
  }

  Future<List<int>?> _verifiedBytes(NodeAttachment attachment) async {
    final file = _attachmentFile(attachment.id);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length != attachment.byteLength ||
        await _checksum(bytes) != attachment.checksum) {
      return null;
    }
    return bytes;
  }

  Future<List<File>> _knownFiles(String prefix) async {
    final files = await _root
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    return files
        .where((file) => p.basename(file.path).startsWith(prefix))
        .toList();
  }

  Future<void> _reconcileKnownOrphans(Set<String> referencedIds) async {
    final files = await _root
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final blobPattern = RegExp(r'^([0-9a-f-]{36})\.bin$');
    for (final file in files) {
      final name = p.basename(file.path);
      final blob = blobPattern.firstMatch(name);
      final knownOrphan =
          name.startsWith('manifest.json.tmp-') ||
          name.startsWith('manifest.json.backup-') ||
          RegExp(r'^[0-9a-f-]{36}\.bin\.(tmp|delete)-').hasMatch(name);
      if (knownOrphan ||
          (blob != null && !referencedIds.contains(blob.group(1)))) {
        try {
          await file.delete();
        } on FileSystemException {
          // Best-effort cleanup; unknown files are never touched.
        }
      }
    }
  }

  File _attachmentFile(String id) {
    _validateAttachmentId(id);
    final rootPath = p.canonicalize(_root.absolute.path);
    final filePath = p.canonicalize(p.join(rootPath, '$id.bin'));
    if (!p.isWithin(rootPath, filePath)) {
      throw const FormatException('Attachment path escapes storage root.');
    }
    return File(filePath);
  }

  File get _manifestFile => File(p.join(_root.absolute.path, 'manifest.json'));

  Future<Map<String, NodeAttachment>> _readManifest() async =>
      await _loadManifest(_manifestFile) ?? {};

  Future<Map<String, NodeAttachment>?> _loadManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded['entries'] is! List<Object?>) {
        return null;
      }
      final result = <String, NodeAttachment>{};
      for (final raw in decoded['entries']! as List<Object?>) {
        final attachment = _decodeAttachment(raw);
        if (attachment != null) result[attachment.id] = attachment;
      }
      return result;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _writeManifest(Map<String, NodeAttachment> entries) async {
    await _root.create(recursive: true);
    final temporary = File('${_manifestFile.path}.tmp-${_uuid.v4()}');
    final backup = File('${_manifestFile.path}.backup-${_uuid.v4()}');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'version': nodeAttachmentManifestVersion,
          'entries': entries.values.map(_encodeAttachment).toList(),
        }),
        flush: true,
      );
      final hadManifest = await _manifestFile.exists();
      if (hadManifest) {
        await _manifestFile.rename(backup.path);
      }
      await _beforeManifestReplace?.call();
      await temporary.rename(_manifestFile.path);
      if (await backup.exists()) {
        await backup.delete();
      }
    } catch (_) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (await backup.exists()) {
        if (await _manifestFile.exists()) {
          await _manifestFile.delete();
        }
        await backup.rename(_manifestFile.path);
      }
      rethrow;
    }
  }
}
