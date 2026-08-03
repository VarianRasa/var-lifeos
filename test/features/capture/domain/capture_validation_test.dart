import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/capture/domain/capture_payload.dart';
import 'package:var_app/features/capture/domain/capture_validation.dart';

void main() {
  group('CaptureValidator', () {
    test('rejects empty payload', () {
      const payload = CapturePayload();
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Capture payload cannot be empty'));
    });

    test('rejects private network URLs', () {
      const payload = CapturePayload(
        text: 'test',
        urls: ['http://127.0.0.1/secret', 'http://localhost:8080'],
      );
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(
        result.errors.first,
        contains('Private or local network URL rejected'),
      );
    });

    test('rejects invalid URL schemes', () {
      const payload = CapturePayload(urls: ['ftp://files.example.com/doc.pdf']);
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('Invalid URL scheme'));
    });

    test('accepts valid public payload', () {
      const payload = CapturePayload(
        text: 'Read this article',
        urls: ['https://example.com/article'],
      );
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isTrue);
    });
  });
}
