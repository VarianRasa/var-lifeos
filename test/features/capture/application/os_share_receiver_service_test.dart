import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/application/os_share_receiver_service.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';

void main() {
  group('OsShareReceiverService', () {
    test('parses raw text and url share data into CapturePayload', () async {
      final service = OsShareReceiverService();
      final payload = await service.parseShareData(
        text: 'Check this out https://example.com/article',
      );

      expect(payload.urls, contains('https://example.com/article'));
      expect(payload.text, equals('Check this out'));
    });

    test('rejects private or localhost URLs', () async {
      final service = OsShareReceiverService();
      final payload = await service.parseShareData(
        text: 'Private link http://localhost:8080/test and http://192.168.1.1/admin',
      );

      expect(payload.urls, isEmpty);
      expect(payload.text, equals('Private link  and'));
    });

    test('validates file size limit', () {
      final service = OsShareReceiverService(maxFileBytes: 100 * 1024 * 1024);

      expect(service.validateFileSize(fileSizeBytes: 100 * 1024 * 1024), isTrue);
      expect(service.validateFileSize(fileSizeBytes: 101 * 1024 * 1024), isFalse);
    });

    test('parses file attachments below size limit and skips oversized or non-existent files', () async {
      final service = OsShareReceiverService(maxFileBytes: 1024);
      final tempDir = await Directory.systemTemp.createTemp('os_share_test');

      try {
        final validFile = File('${tempDir.path}/valid.txt');
        await validFile.writeAsString('small content');

        final oversizedFile = File('${tempDir.path}/large.bin');
        await oversizedFile.writeAsBytes(List<int>.filled(2000, 0));

        final payload = await service.parseShareData(
          filePaths: [
            validFile.path,
            oversizedFile.path,
            '${tempDir.path}/non_existent.txt',
          ],
        );

        expect(payload.attachments.length, equals(1));
        expect(payload.attachments.first.fileName, equals('valid.txt'));
        expect(payload.attachments.first.localPath, equals(validFile.path));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('emitShareData parses, emits on stream, and returns payload', () async {
      final service = OsShareReceiverService();
      final streamExpectation = expectLater(
        service.onShareReceived,
        emits(
          predicate<CapturePayload>((payload) {
            return payload.text == 'Shared content' &&
                payload.urls.contains('https://flutter.dev');
          }),
        ),
      );

      final payload = await service.emitShareData(
        text: 'Shared content https://flutter.dev',
      );

      expect(payload.text, equals('Shared content'));
      expect(payload.urls, contains('https://flutter.dev'));
      await streamExpectation;
    });
  });
}
