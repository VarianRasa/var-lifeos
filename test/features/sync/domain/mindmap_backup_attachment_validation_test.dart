import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/domain/mindmap_backup_document.dart';

void main() {
  test('factory rejects attachment count and declared total limits', () {
    final tiny = MindmapBackupAttachment(
      version: nodeAttachmentManifestVersion,
      attachment: NodeAttachment(
        id: '00000000-0000-4000-8000-000000000001',
        fileName: 'photo.png',
        mimeType: 'image/png',
        byteLength: 1,
        checksum: '00',
        createdAt: DateTime.utc(2026, 7, 14),
      ),
      payload: base64Encode(const [0]),
    );
    expect(
      () => MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime.utc(2026, 7, 14),
        nodes: const [],
        attachments: List<MindmapBackupAttachment>.filled(
          maxPortableBackupAttachmentCount + 1,
          tiny,
        ),
      ),
      throwsFormatException,
    );

    final huge = MindmapBackupAttachment(
      version: nodeAttachmentManifestVersion,
      attachment: NodeAttachment(
        id: '00000000-0000-4000-8000-000000000002',
        fileName: 'video.mp4',
        mimeType: 'video/mp4',
        byteLength: 100 * 1024 * 1024,
        checksum: '00',
        createdAt: DateTime.utc(2026, 7, 14),
      ),
      payload: base64Encode(const [0]),
    );
    expect(
      () => MindmapBackupDocument.create(
        sourceDevice: const SyncDeviceIdentity(id: 'device-a', label: 'Laptop'),
        exportedAt: DateTime.utc(2026, 7, 14),
        nodes: const [],
        attachments: [huge, huge, huge],
      ),
      throwsFormatException,
    );
  });

  test('rejects attachment count before parsing entries', () {
    final json = _documentJson()
      ..['attachments'] = List<Object?>.filled(
        maxPortableBackupAttachmentCount + 1,
        'not-an-entry',
      );

    expect(() => MindmapBackupDocument.fromJson(json), throwsFormatException);
  });

  test(
    'rejects total declared attachment size without allocating payloads',
    () {
      expect(
        () => validatePortableBackupAttachmentSizes(const [
          100 * 1024 * 1024,
          100 * 1024 * 1024,
          100 * 1024 * 1024,
        ]),
        throwsFormatException,
      );
      expect(
        () => validatePortableBackupAttachmentSizes(
          List<int>.filled(maxPortableBackupAttachmentCount + 1, 1),
        ),
        throwsFormatException,
      );
    },
  );

  test('malformed attachment metadata types always throw FormatException', () {
    final valid = _attachmentJson();
    final malformedAttachments = <Object?>[
      {...valid, 'version': '1'},
      {...valid, 'attachment': 'invalid'},
      {...valid, 'payload': 1},
      _withMetadata(valid, 'id', 1),
      _withMetadata(valid, 'fileName', 1),
      _withMetadata(valid, 'mimeType', 1),
      _withMetadata(valid, 'byteLength', '1'),
      _withMetadata(valid, 'checksum', 1),
      _withMetadata(valid, 'createdAt', 1),
      _withMetadata(valid, 'createdAt', 'invalid-date'),
      _withMetadata(valid, 'byteLength', maxNodeAttachmentBytes + 1),
      {...valid, 'payload': 'not-base64'},
      <Object?, Object?>{
        ...valid,
        'attachment': <Object?, Object?>{1: 'bad'},
      },
    ];

    for (final attachment in malformedAttachments) {
      final json = _documentJson()..['attachments'] = [attachment];
      expect(
        () => MindmapBackupDocument.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('malformed top-level and source device types are normalized', () {
    final malformed = <Map<String, Object?>>[
      _documentJson()..['type'] = 1,
      _documentJson()..['schemaVersion'] = '2',
      _documentJson()..['exportedAt'] = 1,
      _documentJson()..['sourceDevice'] = 'invalid',
      _documentJson()..['sourceDevice'] = {'id': 1, 'label': 'Laptop'},
      _documentJson()..['sourceDevice'] = {'id': 'device-a', 'label': 1},
      _documentJson()..['sourceDevice'] = <Object?, Object?>{1: 'invalid'},
      _documentJson()..['nodes'] = 'invalid',
      _documentJson()
        ..['nodes'] = [
          <Object?, Object?>{1: 'invalid'},
        ],
      _documentJson()..['attachments'] = 'invalid',
    ];

    for (final json in malformed) {
      expect(
        () => MindmapBackupDocument.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    }
  });
}

Map<String, Object?> _documentJson() => {
  'type': MindmapBackupDocument.documentType,
  'schemaVersion': MindmapBackupDocument.currentSchemaVersion,
  'exportedAt': DateTime.utc(2026, 7, 14).toIso8601String(),
  'sourceDevice': {'id': 'device-a', 'label': 'Laptop'},
  'nodes': <Object?>[],
};

Map<String, Object?> _attachmentJson() => {
  'version': nodeAttachmentManifestVersion,
  'attachment': {
    'id': '00000000-0000-4000-8000-000000000001',
    'fileName': 'photo.png',
    'mimeType': 'image/png',
    'byteLength': 1,
    'checksum': '00',
    'createdAt': DateTime.utc(2026, 7, 14).toIso8601String(),
  },
  'payload': base64Encode(const [0]),
};

Map<String, Object?> _withMetadata(
  Map<String, Object?> source,
  String key,
  Object? value,
) {
  return {
    ...source,
    'attachment': {
      ...(source['attachment']! as Map<String, Object?>),
      key: value,
    },
  };
}
