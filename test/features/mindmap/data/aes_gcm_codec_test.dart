import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/data/aes_gcm_sembast_codec.dart';

void main() {
  group('AES-GCM-256 Sembast Codec Test', () {
    final keyBytes = List<int>.generate(32, (i) => i);
    final sembastCodec = getAesGcmSembastCodec(keyBytes);

    test('Enkripsi dan Dekripsi berhasil mengembalikan objek asli', () {
      final data = {'id': 'test-node', 'title': 'Task Rahasia', 'priority': 3};
      final codec = sembastCodec.codec!;
      final encrypted = codec.encoder.convert(data);

      expect(encrypted, isNot(contains('Task Rahasia')));

      final decrypted =
          codec.decoder.convert(encrypted) as Map<String, Object?>;
      expect(decrypted['title'], equals('Task Rahasia'));
      expect(decrypted['priority'], equals(3));
    });

    test('Deteksi tampering: dekripsi gagal jika payload dimodifikasi', () {
      final data = {'secret': 'highly-sensitive-info'};
      final codec = sembastCodec.codec!;
      final encrypted = codec.encoder.convert(data);

      final bytes = base64Decode(encrypted);
      bytes[bytes.length - 1] ^= 0xFF;
      final tamperedPayload = base64Encode(bytes);

      expect(
        () => codec.decoder.convert(tamperedPayload),
        throwsA(isA<Exception>()),
      );
    });
  });
}
