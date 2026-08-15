import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/application/media_file_import_service.dart';
import 'package:var_app/features/mindmap/domain/node_attachment.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  group('MediaFileImportService', () {
    test('cancel is harmless and does not import', () async {
      final repository = _RecordingAttachmentRepository();
      final service = MediaFileImportService(
        repository: repository,
        picker: const _FakePicker(null),
      );

      expect(await service.pickImage(), isNull);
      expect(repository.importCount, 0);
    });

    test('imports generic attachment with safe fallback MIME', () async {
      final repository = _RecordingAttachmentRepository();
      final service = MediaFileImportService(
        repository: repository,
        picker: const _FakePicker(
          PickedMediaFile(
            fileName: 'receipt.pdf',
            byteLength: 4,
            bytes: [0x25, 0x50, 0x44, 0x46],
          ),
        ),
      );

      final attachment = await service.pickAttachment();

      expect(attachment, isNotNull);
      expect(attachment!.fileName, 'receipt.pdf');
      expect(attachment.mimeType, 'application/pdf');
      expect(repository.lastBytes, [0x25, 0x50, 0x44, 0x46]);
    });

    test(
      'imports image bytes and preserves existing presentation fields',
      () async {
        final repository = _RecordingAttachmentRepository();
        final service = MediaFileImportService(
          repository: repository,
          picker: const _FakePicker(
            PickedMediaFile(
              fileName: 'photo.png',
              byteLength: 8,
              mimeType: 'image/png',
              bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
            ),
          ),
        );

        final payload = await service.pickImage(
          existing: const ImagePayload(
            url: 'https://example.com/old.png',
            caption: 'Keep caption',
            altText: 'Keep alt',
            fitMode: ImageFitMode.cover,
            width: 640,
            height: 480,
          ),
        );

        expect(payload, isNotNull);
        expect(payload!.attachmentId, _RecordingAttachmentRepository.id);
        expect(payload.url, isEmpty);
        expect(payload.fileName, 'photo.png');
        expect(payload.mimeType, 'image/png');
        expect(payload.byteLength, 8);
        expect(payload.caption, 'Keep caption');
        expect(payload.altText, 'Keep alt');
        expect(payload.fitMode, ImageFitMode.cover);
        expect(payload.width, 640);
        expect(payload.height, 480);
        expect(repository.lastBytes, [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]);
      },
    );

    test(
      'imports video from bounded read stream and preserves playback fields',
      () async {
        final repository = _RecordingAttachmentRepository();
        final service = MediaFileImportService(
          repository: repository,
          picker: _FakePicker(
            PickedMediaFile(
              fileName: 'clip.webm',
              byteLength: 4,
              mimeType: 'video/webm',
              readStream: Stream.fromIterable(const [
                [0x1a, 0x45],
                [0xdf, 0xa3],
              ]),
            ),
          ),
        );

        final payload = await service.pickVideo(
          existing: const VideoPayload(
            url: 'https://example.com/old.webm',
            durationSeconds: 90,
            playbackPositionSeconds: 12,
            muted: true,
            caption: 'Keep caption',
            altText: 'Keep alt',
            fitMode: VideoFitMode.cover,
          ),
        );

        expect(payload, isNotNull);
        expect(payload!.attachmentId, _RecordingAttachmentRepository.id);
        expect(payload.url, isEmpty);
        expect(payload.durationSeconds, 90);
        expect(payload.playbackPositionSeconds, 12);
        expect(payload.muted, isTrue);
        expect(payload.caption, 'Keep caption');
        expect(payload.altText, 'Keep alt');
        expect(payload.fitMode, VideoFitMode.cover);
      },
    );

    test('imports audio into app-owned attachment storage', () async {
      final repository = _RecordingAttachmentRepository();
      final service = MediaFileImportService(
        repository: repository,
        picker: const _FakePicker(
          PickedMediaFile(
            fileName: 'memo.mp3',
            byteLength: 6,
            mimeType: 'audio/mpeg',
            bytes: <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00],
          ),
        ),
        maxBytes: 25 * 1024 * 1024,
      );

      final payload = await service.pickAudio();

      expect(payload, isNotNull);
      expect(payload!.sourceType, AudioSourceType.attachment);
      expect(payload.attachmentId, _RecordingAttachmentRepository.id);
      expect(payload.fileName, 'memo.mp3');
      expect(payload.mimeType, 'audio/mpeg');
      expect(payload.sizeBytes, 6);
    });

    for (final invalid in <({PickedMediaFile file, String message})>[
      (
        file: const PickedMediaFile(
          fileName: 'empty.png',
          byteLength: 0,
          mimeType: 'image/png',
          bytes: [],
        ),
        message: 'Selected media file is empty.',
      ),
      (
        file: const PickedMediaFile(
          fileName: 'huge.png',
          byteLength: maxNodeAttachmentBytes + 1,
          mimeType: 'image/png',
          bytes: [1],
        ),
        message: 'Selected media file exceeds 100 MB.',
      ),
      (
        file: const PickedMediaFile(
          fileName: 'photo.bmp',
          byteLength: 1,
          mimeType: 'image/bmp',
          bytes: [1],
        ),
        message: 'Unsupported image file extension.',
      ),
      (
        file: const PickedMediaFile(
          fileName: 'photo.png',
          byteLength: 1,
          mimeType: 'application/octet-stream',
          bytes: [1],
        ),
        message: 'Unsupported image MIME type.',
      ),
      (
        file: const PickedMediaFile(
          fileName: 'photo.png',
          byteLength: 1,
          mimeType: 'image/jpeg',
          bytes: [1],
        ),
        message: 'Selected media extension does not match its MIME type.',
      ),
      (
        file: const PickedMediaFile(
          fileName: 'photo.png',
          byteLength: 1,
          mimeType: 'image/png',
        ),
        message: 'Selected media data is unavailable.',
      ),
    ]) {
      test(invalid.message, () async {
        final repository = _RecordingAttachmentRepository();
        final service = MediaFileImportService(
          repository: repository,
          picker: _FakePicker(invalid.file),
        );

        await expectLater(
          service.pickImage(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              invalid.message,
            ),
          ),
        );
        expect(repository.importCount, 0);
      });
    }

    test('rejects MIME spoof with valid extension', () async {
      final repository = _RecordingAttachmentRepository();
      final service = MediaFileImportService(
        repository: repository,
        picker: const _FakePicker(
          PickedMediaFile(
            fileName: 'spoof.png',
            byteLength: 8,
            mimeType: 'image/png',
            bytes: [1, 2, 3, 4, 5, 6, 7, 8],
          ),
        ),
      );

      await expectLater(
        service.pickImage(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Selected media content does not match its MIME type.',
          ),
        ),
      );
      expect(repository.importCount, 0);
    });

    test(
      'rejects stream beyond injected boundary without large allocation',
      () async {
        final repository = _RecordingAttachmentRepository();
        final service = MediaFileImportService(
          repository: repository,
          picker: _FakePicker(
            PickedMediaFile(
              fileName: 'near-limit.png',
              byteLength: 8,
              mimeType: 'image/png',
              readStream: Stream.fromIterable(const [
                [0x89, 0x50, 0x4e, 0x47],
                [0x0d, 0x0a, 0x1a, 0x0a, 0x00],
              ]),
            ),
          ),
          maxBytes: 8,
        );

        await expectLater(
          service.pickImage(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Selected media file exceeds allowed size.',
            ),
          ),
        );
        expect(repository.importCount, 0);
      },
    );
  });
}

final class _FakePicker implements MediaFilePicker {
  const _FakePicker(this.file);

  final PickedMediaFile? file;

  @override
  Future<PickedMediaFile?> pick(MediaFileKind kind) async => file;
}

final class _RecordingAttachmentRepository implements NodeAttachmentRepository {
  static const id = '123e4567-e89b-12d3-a456-426614174000';

  int importCount = 0;
  List<int>? lastBytes;

  @override
  Future<NodeAttachment> importBytes({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
  }) async {
    importCount += 1;
    lastBytes = List<int>.of(bytes);
    return NodeAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
      checksum: 'a' * 64,
      createdAt: DateTime.utc(2026, 7, 15),
    );
  }

  @override
  Future<List<NodeAttachmentManifestEntry>> buildManifest() async => const [];

  @override
  Future<void> delete(String attachmentId) async {}

  @override
  Future<List<int>?> exportBytes(String attachmentId) async => null;

  @override
  Future<List<int>?> readBytes(String attachmentId) async => null;

  @override
  Future<NodeAttachment?> resolve(String attachmentId) async => null;
}
