/// Versioned backup document for portable mindmap data.
library;

import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/domain/mindmap_node.dart';
import '../../mindmap/domain/node_attachment.dart';
import '../../mindmap/domain/node_type_payloads.dart';

enum MindmapBackupWarningCode { missingAttachmentPayload }

const int maxPortableBackupAttachmentCount = 256;
const int maxPortableBackupAttachmentBytes = 256 * 1024 * 1024;

void validatePortableBackupAttachmentSizes(Iterable<int> byteLengths) {
  var count = 0;
  var total = 0;
  for (final byteLength in byteLengths) {
    count += 1;
    if (count > maxPortableBackupAttachmentCount) {
      throw const FormatException('Backup contains too many attachments.');
    }
    if (byteLength <= 0 || byteLength > maxNodeAttachmentBytes) {
      throw const FormatException('Backup attachment size is invalid.');
    }
    total += byteLength;
    if (total > maxPortableBackupAttachmentBytes) {
      throw const FormatException('Backup attachments exceed size limit.');
    }
  }
}

final class MindmapBackupWarning {
  const MindmapBackupWarning({
    required this.code,
    required this.attachmentId,
    required this.message,
  });

  factory MindmapBackupWarning.fromJson(Map<String, Object?> json) {
    final codeName = json['code'];
    final attachmentId = json['attachmentId'];
    final message = json['message'];
    if (codeName is! String || attachmentId is! String || message is! String) {
      throw const FormatException('Backup warning is invalid.');
    }
    final code = MindmapBackupWarningCode.values.where(
      (candidate) => candidate.name == codeName,
    );
    if (code.isEmpty) {
      throw const FormatException('Backup warning code is invalid.');
    }
    return MindmapBackupWarning(
      code: code.single,
      attachmentId: attachmentId,
      message: message,
    );
  }

  final MindmapBackupWarningCode code;
  final String attachmentId;
  final String message;

  Map<String, Object?> toJson() => {
    'code': code.name,
    'attachmentId': attachmentId,
    'message': message,
  };
}

final class MindmapBackupAttachment {
  const MindmapBackupAttachment({
    required this.version,
    required this.attachment,
    required this.payload,
  });

  factory MindmapBackupAttachment.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final rawAttachment = json['attachment'];
    final rawPayload = json['payload'];
    if (version != nodeAttachmentManifestVersion ||
        rawAttachment is! Map<Object?, Object?> ||
        rawPayload is! String) {
      throw const FormatException('Backup attachment entry is invalid.');
    }
    final metadata = <String, Object?>{};
    for (final entry in rawAttachment.entries) {
      if (entry.key is! String) {
        throw const FormatException('Backup attachment metadata is invalid.');
      }
      metadata[entry.key as String] = entry.value;
    }
    final id = metadata['id'];
    final fileName = metadata['fileName'];
    final mimeType = metadata['mimeType'];
    final byteLength = metadata['byteLength'];
    final checksum = metadata['checksum'];
    final rawCreatedAt = metadata['createdAt'];
    if (id is! String ||
        fileName is! String ||
        mimeType is! String ||
        byteLength is! int ||
        checksum is! String ||
        rawCreatedAt is! String) {
      throw const FormatException('Backup attachment metadata is invalid.');
    }
    if (byteLength <= 0 || byteLength > maxNodeAttachmentBytes) {
      throw const FormatException('Backup attachment size is invalid.');
    }
    final estimatedLength = _decodedBase64Length(rawPayload);
    if (estimatedLength != byteLength) {
      throw const FormatException('Backup attachment payload size is invalid.');
    }
    final createdAt = DateTime.tryParse(rawCreatedAt);
    final attachment = NodeAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: byteLength,
      checksum: checksum,
      createdAt:
          createdAt ??
          (throw const FormatException('Backup attachment date is invalid.')),
    );
    return MindmapBackupAttachment(
      version: version as int,
      attachment: attachment,
      payload: rawPayload,
    );
  }

  final int version;
  final NodeAttachment attachment;
  final String payload;

  List<int> decodePayload() {
    try {
      return base64Decode(payload);
    } on FormatException {
      throw const FormatException('Backup attachment payload is invalid.');
    }
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'attachment': {
      'id': attachment.id,
      'fileName': attachment.fileName,
      'mimeType': attachment.mimeType,
      'byteLength': attachment.byteLength,
      'checksum': attachment.checksum,
      'createdAt': attachment.createdAt.toIso8601String(),
    },
    'payload': payload,
  };
}

final class SyncDeviceIdentity {
  const SyncDeviceIdentity({required this.id, required this.label});

  factory SyncDeviceIdentity.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final label = json['label'];
    if (id is! String || label is! String) {
      throw const FormatException('Backup device identity is invalid.');
    }
    if (id.trim().isEmpty) {
      throw const FormatException('Backup device id is required.');
    }

    return SyncDeviceIdentity(id: id.trim(), label: label.trim());
  }

  final String id;
  final String label;

  Map<String, Object?> toJson() => {'id': id, 'label': label};

  @override
  bool operator ==(Object other) {
    return other is SyncDeviceIdentity &&
        other.id == id &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(id, label);
}

final class MindmapBackupDocument {
  MindmapBackupDocument._({
    required this.schemaVersion,
    required this.type,
    required this.exportedAt,
    required this.sourceDevice,
    required List<MindmapNode> nodes,
    required List<MindmapBackupAttachment> attachments,
    required List<MindmapBackupWarning> warnings,
  }) : nodes = List.unmodifiable(_sortNodes(nodes)),
       attachments = List.unmodifiable(attachments),
       warnings = List.unmodifiable(warnings);

  factory MindmapBackupDocument.create({
    required SyncDeviceIdentity sourceDevice,
    required DateTime exportedAt,
    required Iterable<MindmapNode> nodes,
    Iterable<MindmapBackupAttachment> attachments = const [],
    Iterable<MindmapBackupWarning> warnings = const [],
  }) {
    final document = MindmapBackupDocument._(
      schemaVersion: currentSchemaVersion,
      type: documentType,
      exportedAt: exportedAt,
      sourceDevice: sourceDevice,
      nodes: nodes.toList(),
      attachments: attachments.toList(),
      warnings: warnings.toList(),
    );
    document.validateForImport();
    return document;
  }

  factory MindmapBackupDocument.fromJson(Map<String, Object?> json) {
    final rawType = json['type'];
    if (rawType is! String || rawType != documentType) {
      throw const FormatException('Unsupported backup document type.');
    }
    final type = rawType;

    final rawSchemaVersion = json['schemaVersion'];
    if (rawSchemaVersion is! int ||
        (rawSchemaVersion != 1 && rawSchemaVersion != currentSchemaVersion)) {
      throw const FormatException('Unsupported backup schema version.');
    }
    final schemaVersion = rawSchemaVersion;

    final exportedAtValue = json['exportedAt'];
    final exportedAt = exportedAtValue is String
        ? DateTime.tryParse(exportedAtValue)
        : null;
    if (exportedAt == null) {
      throw const FormatException('Backup exportedAt is invalid.');
    }

    final rawDevice = json['sourceDevice'];
    final sourceDevice = rawDevice is Map<Object?, Object?>
        ? SyncDeviceIdentity.fromJson(_stringKeyedMap(rawDevice))
        : throw const FormatException('Backup sourceDevice is invalid.');

    final rawNodes = json['nodes'];
    if (rawNodes is! List<Object?>) {
      throw const FormatException('Backup nodes must be a list.');
    }

    if (rawNodes.length > maxNodeCount) {
      throw const FormatException('Backup contains too many nodes.');
    }
    final nodes = <MindmapNode>[];
    final nodeIds = <String>{};
    for (final rawNode in rawNodes) {
      if (rawNode is! Map<Object?, Object?>) {
        throw const FormatException('Backup node entry is invalid.');
      }
      final MindmapNode node;
      try {
        node = MindmapNode.fromJson(_stringKeyedMap(rawNode));
      } on Object {
        throw const FormatException('Backup node entry is invalid.');
      }
      if (node.id.trim().isEmpty) {
        throw const FormatException('Backup node id is required.');
      }
      if (!nodeIds.add(node.id)) {
        throw const FormatException('Backup contains duplicate node ids.');
      }
      _validateTypedDrawingPayload(node);
      nodes.add(node);
    }

    final attachments = <MindmapBackupAttachment>[];
    final attachmentIds = <String>{};
    final rawAttachments = json['attachments'];
    if (rawAttachments != null) {
      if (rawAttachments is! List<Object?>) {
        throw const FormatException('Backup attachments must be a list.');
      }
      if (rawAttachments.length > maxPortableBackupAttachmentCount) {
        throw const FormatException('Backup contains too many attachments.');
      }
      final attachmentLengths = <int>[];
      for (final rawAttachment in rawAttachments) {
        if (rawAttachment is! Map<Object?, Object?>) {
          throw const FormatException('Backup attachment entry is invalid.');
        }
        final entry = MindmapBackupAttachment.fromJson(
          _stringKeyedMap(rawAttachment),
        );
        if (!attachmentIds.add(entry.attachment.id)) {
          throw const FormatException(
            'Backup contains duplicate attachment ids.',
          );
        }
        attachmentLengths.add(entry.attachment.byteLength);
        attachments.add(entry);
      }
      validatePortableBackupAttachmentSizes(attachmentLengths);
    }

    final warnings = <MindmapBackupWarning>[];
    final rawWarnings = json['warnings'];
    if (rawWarnings != null) {
      if (rawWarnings is! List<Object?>) {
        throw const FormatException('Backup warnings must be a list.');
      }
      for (final rawWarning in rawWarnings) {
        if (rawWarning is! Map<Object?, Object?>) {
          throw const FormatException('Backup warning is invalid.');
        }
        warnings.add(
          MindmapBackupWarning.fromJson(_stringKeyedMap(rawWarning)),
        );
      }
    }

    final document = MindmapBackupDocument._(
      schemaVersion: schemaVersion,
      type: type,
      exportedAt: exportedAt,
      sourceDevice: sourceDevice,
      nodes: nodes,
      attachments: attachments,
      warnings: warnings,
    );
    document.validateForImport();
    return document;
  }

  static const int currentSchemaVersion = 2;
  static const String documentType = 'var.mindmap.backup';
  static const int maxNodeCount = 100000;

  final int schemaVersion;
  final String type;
  final DateTime exportedAt;
  final SyncDeviceIdentity sourceDevice;
  final List<MindmapNode> nodes;
  final List<MindmapBackupAttachment> attachments;
  final List<MindmapBackupWarning> warnings;

  void validateForImport() {
    if (type != documentType ||
        (schemaVersion != 1 && schemaVersion != currentSchemaVersion)) {
      throw const FormatException('Backup document header is invalid.');
    }
    if (sourceDevice.id.trim().isEmpty) {
      throw const FormatException('Backup device id is required.');
    }
    if (nodes.length > maxNodeCount ||
        nodes.map((node) => node.id).toSet().length != nodes.length) {
      throw const FormatException('Backup nodes are invalid.');
    }
    if (warnings.length > maxPortableBackupAttachmentCount) {
      throw const FormatException('Backup contains too many warnings.');
    }
    validatePortableBackupAttachmentSizes(
      attachments.map((entry) => entry.attachment.byteLength),
    );
    final attachmentIds = <String>{};
    for (final entry in attachments) {
      if (entry.version != nodeAttachmentManifestVersion ||
          !attachmentIds.add(entry.attachment.id) ||
          _decodedBase64Length(entry.payload) != entry.attachment.byteLength) {
        throw const FormatException('Backup attachment entry is invalid.');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toIso8601String(),
    'sourceDevice': sourceDevice.toJson(),
    'nodes': [for (final node in nodes) node.toJson()],
    if (attachments.isNotEmpty)
      'attachments': [
        for (final attachment in attachments) attachment.toJson(),
      ],
    if (warnings.isNotEmpty)
      'warnings': [for (final warning in warnings) warning.toJson()],
  };
}

int _decodedBase64Length(String value) {
  if (value.isEmpty || value.length % 4 != 0) {
    throw const FormatException('Backup attachment payload is invalid.');
  }
  var padding = 0;
  if (value.endsWith('=')) padding += 1;
  if (value.endsWith('==')) padding += 1;
  final result = (value.length ~/ 4) * 3 - padding;
  if (result <= 0 || result > maxNodeAttachmentBytes) {
    throw const FormatException('Backup attachment payload size is invalid.');
  }
  return result;
}

Map<String, Object?> _stringKeyedMap(Map<Object?, Object?> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key is! String) {
      throw const FormatException('Backup object keys are invalid.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _validateTypedDrawingPayload(MindmapNode node) {
  final errors = switch (node.type) {
    NodeType.canvas => CanvasPayload.fromNode(node).validate(title: node.title),
    NodeType.image => ImagePayload.fromNode(node).validate(title: node.title),
    _ => const <String>[],
  };
  if (errors.isNotEmpty) {
    throw const FormatException('Backup typed drawing payload is invalid.');
  }
}

List<MindmapNode> _sortNodes(List<MindmapNode> nodes) {
  return nodes..sort((a, b) {
    final day = a.day.dateOnly.compareTo(b.day.dateOnly);
    if (day != 0) return day;
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    return a.title.compareTo(b.title);
  });
}
