import 'dart:convert';
import 'dart:typed_data';

import '../domain/canvas_board.dart';
import '../domain/node_attachment.dart';

const String canvasBoardPackageKind = 'var.project.canvas.package';
const int canvasBoardPackageVersion = 1;
const int maxCanvasBoardPackageBytes = 250 * 1024 * 1024;

final class CanvasBoardPackageService {
  const CanvasBoardPackageService({required this.attachmentRepository});

  final NodeAttachmentRepository attachmentRepository;

  Future<Uint8List> exportPackage(CanvasBoard board) async {
    if (board.kind != CanvasBoardKind.project) {
      throw const FormatException('Only project boards can be exported.');
    }
    final attachmentIds = <String>{};
    for (final object in board.objects) {
      if (object.type != CanvasObjectType.image) continue;
      final attachmentId = object.payload['attachmentId'];
      if (attachmentId is String && attachmentId.isNotEmpty) {
        attachmentIds.add(attachmentId);
      }
    }
    final attachments = <Map<String, Object?>>[];
    for (final attachmentId in attachmentIds) {
      final attachment = await attachmentRepository.resolve(attachmentId);
      final bytes = await attachmentRepository.exportBytes(attachmentId);
      if (attachment == null || bytes == null || bytes.isEmpty) {
        throw FormatException('Canvas attachment is missing: $attachmentId');
      }
      attachments.add(<String, Object?>{
        'sourceId': attachmentId,
        'fileName': attachment.fileName,
        'mimeType': attachment.mimeType,
        'byteLength': bytes.length,
        'bytes': base64Encode(bytes),
      });
    }
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'kind': canvasBoardPackageKind,
          'version': canvasBoardPackageVersion,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
          'board': board.toJson(),
          'attachments': attachments,
        }),
      ),
    );
    if (bytes.length > maxCanvasBoardPackageBytes) {
      throw const FormatException('Canvas board package exceeds 250 MB.');
    }
    return bytes;
  }

  Future<CanvasBoard> importPackage(
    List<int> bytes, {
    required String workspaceName,
    required DateTime now,
  }) async {
    if (bytes.isEmpty || bytes.length > maxCanvasBoardPackageBytes) {
      throw const FormatException('Invalid canvas board package size.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Invalid canvas board package.');
    }
    final json = Map<String, Object?>.from(decoded);
    if (json['kind'] != canvasBoardPackageKind ||
        json['version'] != canvasBoardPackageVersion ||
        json['board'] is! Map) {
      throw const FormatException('Unsupported canvas board package.');
    }
    final source = CanvasBoard.fromJson(
      Map<String, Object?>.from(json['board']! as Map),
    );
    if (source.kind != CanvasBoardKind.project) {
      throw const FormatException('Package does not contain a project board.');
    }
    final rawAttachments = json['attachments'];
    if (rawAttachments is! List) {
      throw const FormatException('Package attachments are invalid.');
    }
    final importedIds = <String>[];
    final idMap = <String, NodeAttachment>{};
    try {
      for (final value in rawAttachments) {
        if (value is! Map) {
          throw const FormatException('Package attachment is invalid.');
        }
        final attachment = Map<String, Object?>.from(value);
        final sourceId = attachment['sourceId'] as String? ?? '';
        final fileName = attachment['fileName'] as String? ?? '';
        final mimeType = attachment['mimeType'] as String? ?? '';
        final encoded = attachment['bytes'] as String? ?? '';
        if (sourceId.isEmpty || fileName.isEmpty || mimeType.isEmpty) {
          throw const FormatException(
            'Package attachment metadata is invalid.',
          );
        }
        final attachmentBytes = base64Decode(encoded);
        if (attachmentBytes.isEmpty ||
            attachmentBytes.length != attachment['byteLength']) {
          throw const FormatException('Package attachment data is invalid.');
        }
        final imported = await attachmentRepository.importBytes(
          bytes: attachmentBytes,
          fileName: fileName,
          mimeType: mimeType,
        );
        importedIds.add(imported.id);
        idMap[sourceId] = imported;
      }
      final objects = <CanvasObject>[
        for (final object in source.objects)
          _remapAttachment(object, idMap, now),
      ];
      return CanvasBoard(
        id: '${projectCanvasBoardId(workspaceName)}:import:${now.microsecondsSinceEpoch}',
        kind: CanvasBoardKind.project,
        title: '${source.title} imported',
        workspaceName: workspaceName,
        viewport: source.viewport,
        settings: source.settings,
        votingSession: source.votingSession.reset(),
        schemaVersion: source.schemaVersion,
        objects: objects,
        createdAt: now,
        updatedAt: now,
      ).recordActivity(
        type: CanvasActivityType.boardImported,
        summary: 'Imported ${source.title}',
        now: now,
      );
    } on Object {
      for (final attachmentId in importedIds) {
        await attachmentRepository.delete(attachmentId);
      }
      rethrow;
    }
  }
}

CanvasObject _remapAttachment(
  CanvasObject object,
  Map<String, NodeAttachment> idMap,
  DateTime now,
) {
  if (object.type != CanvasObjectType.image) return object;
  final sourceId = object.payload['attachmentId'];
  if (sourceId is! String || sourceId.isEmpty) return object;
  final attachment = idMap[sourceId];
  if (attachment == null) {
    throw FormatException('Package image attachment is missing: $sourceId');
  }
  return object.copyWith(
    payload: <String, Object?>{
      ...object.payload,
      'attachmentId': attachment.id,
      'fileName': attachment.fileName,
      'mimeType': attachment.mimeType,
      'byteLength': attachment.byteLength,
    },
    updatedAt: now,
  );
}
