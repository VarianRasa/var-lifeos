library;

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/node_attachment.dart';
import 'indexeddb_node_attachment_repository_stub.dart'
    if (dart.library.js_interop) 'indexeddb_node_attachment_repository_web.dart';

Future<NodeAttachmentRepository> openLocalNodeAttachmentRepository() async {
  return IndexedDbNodeAttachmentRepository.open();
}

final class MemoryNodeAttachmentRepository
    implements NodeAttachmentRepository, NodeAttachmentRestoreRepository {
  MemoryNodeAttachmentRepository({required this.maxTotalBytes});
  final int maxTotalBytes;
  final Map<String, NodeAttachment> _attachments = {};
  final Map<String, List<int>> _bytes = {};
  int _totalBytes = 0;

  @override
  Future<NodeAttachmentRestorePlan> preflightRestore(
    List<NodeAttachmentRestoreItem> items,
  ) async {
    final seen = <String>{};
    final itemsToImport = <NodeAttachmentRestoreItem>[];
    final identicalIds = <String>{};
    var pendingBytes = 0;
    for (final item in items) {
      final attachment = item.attachment;
      if (!seen.add(attachment.id)) {
        throw const FormatException('Duplicate attachment ID.');
      }
      _validateWebAttachmentId(attachment.id);
      final name = _normalizeWebFileName(attachment.fileName);
      final mime = attachment.mimeType.trim().toLowerCase();
      if (item.bytes.isEmpty ||
          item.bytes.length > maxNodeAttachmentBytes ||
          item.bytes.any((value) => value < 0 || value > 255) ||
          !supportedNodeAttachmentMimeTypes.contains(mime) ||
          (mime == 'application/octet-stream' &&
              _unsafeWebGenericExtensions.contains(
                p.extension(name).toLowerCase(),
              )) ||
          (mime != 'application/octet-stream' &&
              !_webExtensionsForMime(
                mime,
              ).contains(p.extension(name).toLowerCase()))) {
        throw const FormatException('Invalid attachment metadata.');
      }
      final hash = await Sha256().hash(item.bytes);
      final checksum = hash.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      if (attachment.fileName != name ||
          attachment.mimeType != mime ||
          attachment.byteLength != item.bytes.length ||
          attachment.checksum != checksum) {
        throw const FormatException('Attachment metadata is invalid.');
      }
      final current = _attachments[attachment.id];
      if (current == null) {
        pendingBytes += item.bytes.length;
        itemsToImport.add(item);
        continue;
      }
      final currentBytes = _bytes[attachment.id];
      if (current.fileName != attachment.fileName ||
          current.mimeType != attachment.mimeType ||
          current.byteLength != attachment.byteLength ||
          current.checksum != attachment.checksum ||
          currentBytes == null ||
          !_sameWebBytes(currentBytes, item.bytes)) {
        throw const FormatException('Attachment ID collision.');
      }
      identicalIds.add(attachment.id);
    }
    if (_totalBytes + pendingBytes > maxTotalBytes) {
      throw const FormatException('Web attachment storage is full.');
    }
    return NodeAttachmentRestorePlan(
      itemsToImport: List.unmodifiable(itemsToImport),
      identicalAttachmentIds: Set.unmodifiable(identicalIds),
    );
  }

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (bytes.isEmpty ||
        bytes.length > maxNodeAttachmentBytes ||
        _totalBytes + bytes.length > maxTotalBytes ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw const FormatException(
        'Attachment size is invalid or web storage is full.',
      );
    }
    final mime = mimeType.trim().toLowerCase();
    final name = _normalizeWebFileName(fileName);
    if (!supportedNodeAttachmentMimeTypes.contains(mime) ||
        (mime == 'application/octet-stream' &&
            _unsafeWebGenericExtensions.contains(
              p.extension(name).toLowerCase(),
            )) ||
        (mime != 'application/octet-stream' &&
            !_webExtensionsForMime(
              mime,
            ).contains(p.extension(name).toLowerCase()))) {
      throw const FormatException('Invalid attachment metadata.');
    }
    final id = const Uuid().v4();
    final hash = await Sha256().hash(bytes);
    final attachment = NodeAttachment(
      id: id,
      fileName: name,
      mimeType: mime,
      byteLength: bytes.length,
      checksum: hash.bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join(),
      createdAt: DateTime.now().toUtc(),
    );
    _attachments[id] = attachment;
    _bytes[id] = List.unmodifiable(bytes);
    _totalBytes += bytes.length;
    return attachment;
  }

  @override
  Future<NodeAttachment> restoreBytes({
    required NodeAttachment attachment,
    required List<int> bytes,
  }) async {
    _validateWebAttachmentId(attachment.id);
    if (_attachments.containsKey(attachment.id)) {
      throw const FormatException('Attachment ID already exists.');
    }
    if (bytes.isEmpty ||
        bytes.length > maxNodeAttachmentBytes ||
        _totalBytes + bytes.length > maxTotalBytes ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw const FormatException(
        'Attachment size is invalid or web storage is full.',
      );
    }
    final name = _normalizeWebFileName(attachment.fileName);
    final mime = attachment.mimeType.trim().toLowerCase();
    if (!supportedNodeAttachmentMimeTypes.contains(mime) ||
        (mime == 'application/octet-stream' &&
            _unsafeWebGenericExtensions.contains(
              p.extension(name).toLowerCase(),
            )) ||
        (mime != 'application/octet-stream' &&
            !_webExtensionsForMime(
              mime,
            ).contains(p.extension(name).toLowerCase()))) {
      throw const FormatException('Invalid attachment metadata.');
    }
    final hash = await Sha256().hash(bytes);
    final checksum = hash.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    if (attachment.byteLength != bytes.length ||
        attachment.checksum != checksum) {
      throw const FormatException('Attachment checksum or size is invalid.');
    }
    final restored = NodeAttachment(
      id: attachment.id,
      fileName: name,
      mimeType: mime,
      byteLength: bytes.length,
      checksum: checksum,
      createdAt: attachment.createdAt.toUtc(),
    );
    _attachments[restored.id] = restored;
    _bytes[restored.id] = List.unmodifiable(bytes);
    _totalBytes += bytes.length;
    return restored;
  }

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async {
    _validateWebAttachmentId(attachmentId);
    return _attachments[attachmentId];
  }

  @override
  Future<List<int>?> readBytes(String attachmentId) async {
    _validateWebAttachmentId(attachmentId);
    return _bytes[attachmentId];
  }

  @override
  Future<List<int>?> exportBytes(String attachmentId) =>
      readBytes(attachmentId);
  @override
  Future<void> delete(String attachmentId) async {
    _validateWebAttachmentId(attachmentId);
    _totalBytes -= _bytes.remove(attachmentId)?.length ?? 0;
    _attachments.remove(attachmentId);
  }

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async =>
      List.unmodifiable(
        _attachments.values.map(
          (value) => NodeAttachmentManifestEntry(
            version: nodeAttachmentManifestVersion,
            attachment: value,
          ),
        ),
      );
}

String _normalizeWebFileName(String fileName) {
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

void _validateWebAttachmentId(String id) {
  if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) || id.split('-').length != 5) {
    throw const FormatException('Invalid attachment ID.');
  }
}

const Set<String> _unsafeWebGenericExtensions = {
  '.bat',
  '.cmd',
  '.com',
  '.dll',
  '.exe',
  '.msi',
  '.ps1',
  '.scr',
};

Set<String> _webExtensionsForMime(String mime) => switch (mime) {
  'application/pdf' => {'.pdf'},
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

bool _sameWebBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
