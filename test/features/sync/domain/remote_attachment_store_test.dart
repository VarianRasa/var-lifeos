import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/sync/domain/remote_attachment_store.dart';

void main() {
  group('RemoteAttachmentMetadata', () {
    test('normalizes valid immutable metadata', () {
      final metadata = RemoteAttachmentMetadata.validated(
        attachmentId: validId,
        checksum: validChecksum.toUpperCase(),
        byteLength: 42,
        mimeType: ' IMAGE/PNG ',
        fileName: ' image.png ',
      );

      expect(metadata.attachmentId, validId);
      expect(metadata.checksum, validChecksum);
      expect(metadata.mimeType, 'image/png');
      expect(metadata.fileName, 'image.png');
      expect(metadata.byteLength, 42);
    });

    test('rejects malformed identifiers, checksums, MIME, size, and names', () {
      for (final invalidId in [
        'not-a-uuid',
        validId.toUpperCase(),
        '123e4567-e89b-02d3-a456-426614174000',
      ]) {
        expect(() => _metadata(attachmentId: invalidId), throwsFormatException);
      }
      expect(() => _metadata(checksum: 'abc'), throwsFormatException);
      expect(() => _metadata(byteLength: 0), throwsFormatException);
      expect(
        () => _metadata(byteLength: maxRemoteAttachmentBytes + 1),
        throwsFormatException,
      );
      expect(() => _metadata(mimeType: 'image/'), throwsFormatException);
      expect(() => _metadata(mimeType: 'image/*'), throwsFormatException);
      expect(() => _metadata(fileName: '../image.png'), throwsFormatException);
      expect(
        () => _metadata(fileName: r'folder\image.png'),
        throwsFormatException,
      );
      expect(() => _metadata(fileName: 'CON.png'), throwsFormatException);
      expect(() => _metadata(fileName: 'image?.png'), throwsFormatException);
      expect(() => _metadata(fileName: 'image.'), throwsFormatException);
    });

    test('rejects malformed JSON field types', () {
      expect(
        () => RemoteAttachmentMetadata.fromJson(const {
          'attachmentId': validId,
          'checksum': validChecksum,
          'byteLength': '42',
          'mimeType': 'image/png',
          'fileName': 'image.png',
        }),
        throwsFormatException,
      );
    });

    test('compares content using checksum, size, and MIME', () {
      final metadata = _metadata();

      expect(
        metadata.hasSameContent(_metadata(fileName: 'renamed.png')),
        isTrue,
      );
      expect(
        metadata.hasSameContent(_metadata(checksum: alternateChecksum)),
        isFalse,
      );
      expect(metadata.hasSameContent(_metadata(byteLength: 43)), isFalse);
      expect(
        metadata.hasSameContent(_metadata(mimeType: 'image/jpeg')),
        isFalse,
      );
      expect(metadata, _metadata());
      expect(metadata.hashCode, _metadata().hashCode);
    });
  });

  group('remote addressing', () {
    test('builds canonical Firebase key from validated UID and UUID', () {
      expect(
        firebaseAttachmentObjectKey(
          userId: 'user_123-abc',
          attachmentId: validId,
        ),
        'attachments/user_123-abc/$validId',
      );
    });

    test('rejects unsafe Firebase UID segments', () {
      for (final userId in [
        '',
        '.',
        '..',
        '../user',
        'user/name',
        r'user\name',
      ]) {
        expect(
          () => firebaseAttachmentObjectKey(
            userId: userId,
            attachmentId: validId,
          ),
          throwsFormatException,
        );
      }
    });

    test('HTTP route is derived from ID and never accepts arbitrary path', () {
      expect(httpAttachmentRoute(validId), '/attachments/$validId');
      expect(
        () => httpAttachmentRoute('../private/file'),
        throwsFormatException,
      );
    });
  });

  test('download verifies real SHA and owns immutable bytes', () async {
    final source = <int>[1, 2, 3];
    final download = await RemoteAttachmentDownload.verified(
      metadata: _metadata(byteLength: 3, checksum: bytes123Checksum),
      bytes: source,
    );
    source[0] = 9;

    expect(download.bytes, [1, 2, 3]);
    expect(() => download.bytes.add(4), throwsUnsupportedError);
  });

  test('download rejects checksum mismatch with stable integrity error', () {
    expect(
      () => RemoteAttachmentDownload.verified(
        metadata: _metadata(byteLength: 3),
        bytes: const [1, 2, 3],
      ),
      throwsA(
        isA<RemoteAttachmentException>().having(
          (error) => error.kind,
          'kind',
          RemoteAttachmentFailureKind.integrity,
        ),
      ),
    );
  });

  test('identical verified downloads have value equality', () async {
    final first = await RemoteAttachmentDownload.verified(
      metadata: _metadata(byteLength: 3, checksum: bytes123Checksum),
      bytes: const [1, 2, 3],
    );
    final second = await RemoteAttachmentDownload.verified(
      metadata: _metadata(byteLength: 3, checksum: bytes123Checksum),
      bytes: const [1, 2, 3],
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('store contract carries bytes but never local paths', () async {
    final store = _RecordingStore();
    final metadata = _nodeAttachment();
    final remoteMetadata = RemoteAttachmentMetadata.fromNodeAttachment(
      metadata,
    );

    await store.upload(metadata: metadata, bytes: Stream.value([1, 2, 3]));
    await store.download(validId);
    await store.delete(attachmentId: validId, tombstoneVersion: 'v1');

    expect(store.capability, AttachmentSyncCapability.supported);
    expect(store.uploadedAttachment, same(metadata));
    expect(store.deletedTombstoneVersion, 'v1');
    expect(remoteMetadata.toJson(), isNot(contains('localPath')));
  });

  test('transfer exceptions expose stable failure kind', () {
    const exception = RemoteAttachmentException(
      RemoteAttachmentFailureKind.integrity,
      'Checksum mismatch.',
    );

    expect(exception.kind, RemoteAttachmentFailureKind.integrity);
    expect(exception.toString(), contains('Checksum mismatch.'));
  });

  test('delete tombstone versions require safe non-empty tokens', () {
    expect(
      validateRemoteAttachmentTombstoneVersion('revision-1'),
      'revision-1',
    );
    expect(
      () => validateRemoteAttachmentTombstoneVersion(''),
      throwsFormatException,
    );
    expect(
      () => validateRemoteAttachmentTombstoneVersion('../revision'),
      throwsFormatException,
    );
  });
}

RemoteAttachmentMetadata _metadata({
  String attachmentId = validId,
  String checksum = validChecksum,
  int byteLength = 42,
  String mimeType = 'image/png',
  String fileName = 'image.png',
}) => RemoteAttachmentMetadata.validated(
  attachmentId: attachmentId,
  checksum: checksum,
  byteLength: byteLength,
  mimeType: mimeType,
  fileName: fileName,
);

final class _RecordingStore implements RemoteAttachmentStore {
  NodeAttachment? uploadedAttachment;
  String? deletedTombstoneVersion;

  @override
  AttachmentSyncCapability get capability => AttachmentSyncCapability.supported;

  @override
  Future<void> delete({
    required String attachmentId,
    required String tombstoneVersion,
  }) async {
    deletedTombstoneVersion = tombstoneVersion;
  }

  @override
  Future<RemoteAttachmentDownload> download(String attachmentId) async {
    return RemoteAttachmentDownload.verified(
      metadata: _metadata(byteLength: 3, checksum: bytes123Checksum),
      bytes: const [1, 2, 3],
    );
  }

  @override
  Future<RemoteAttachmentMetadata?> head(String attachmentId) async => null;

  @override
  Future<void> upload({
    required NodeAttachment metadata,
    required Stream<List<int>> bytes,
  }) async {
    uploadedAttachment = metadata;
    await bytes.drain<void>();
  }
}

NodeAttachment _nodeAttachment() => NodeAttachment(
  id: validId,
  fileName: 'image.png',
  mimeType: 'image/png',
  byteLength: 3,
  checksum: bytes123Checksum,
  createdAt: DateTime.utc(2026, 7, 15),
);

const validId = '123e4567-e89b-42d3-a456-426614174000';
const validChecksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const alternateChecksum =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const bytes123Checksum =
    '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81';
