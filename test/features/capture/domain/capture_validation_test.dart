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

    test('rejects hostless HTTP(S) URLs', () {
      const payload = CapturePayload(urls: ['http://', 'https:///path']);
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(result.errors.first, contains('URL host cannot be empty'));
    });

    test(
      'rejects IPv4 private ranges, shorthand, loopback, and local domain variants',
      () {
        const payload = CapturePayload(
          text: 'test',
          urls: [
            'http://127.0.0.1/secret',
            'http://127.1/secret',
            'http://10.0.0.1',
            'http://192.168.1.1',
            'http://172.16.0.1',
            'http://172.31.255.255',
            'http://0.0.0.0',
            'http://localhost:8080',
            'http://app.local',
            'http://server.internal',
          ],
        );
        final result = CaptureValidator.validate(payload);
        expect(result.isValid, isFalse);
        expect(result.errors.length, equals(10));
        for (final error in result.errors) {
          expect(error, contains('Private or local network URL rejected'));
        }
      },
    );

    test('rejects IPv6 loopback, link-local, and ULA addresses', () {
      const payload = CapturePayload(
        urls: [
          'http://[::1]/secret',
          'http://[fe80::1]/secret',
          'http://[fd00::1]/secret',
          'http://[fc00::1]/secret',
        ],
      );
      final result = CaptureValidator.validate(payload);
      expect(result.isValid, isFalse);
      expect(result.errors.length, equals(4));
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

    test(
      'isPrivateOrLocalHost helper correctly identifies restricted hosts',
      () {
        expect(CaptureValidator.isPrivateOrLocalHost('localhost'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('127.0.0.1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('127.1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('10.255.0.1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('192.168.0.1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('172.20.0.1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('::1'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('fe80::1'), isTrue);
        expect(
          CaptureValidator.isPrivateOrLocalHost('fd12:3456:789a::1'),
          isTrue,
        );
        expect(CaptureValidator.isPrivateOrLocalHost('mybox.local'), isTrue);
        expect(CaptureValidator.isPrivateOrLocalHost('example.com'), isFalse);
        expect(CaptureValidator.isPrivateOrLocalHost('93.184.216.34'), isFalse);
      },
    );
  });
}
