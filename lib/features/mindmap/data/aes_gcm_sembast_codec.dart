import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:sembast/sembast.dart';

/// Mengembalikan [SembastCodec] berbasis AES-GCM-256 menggunakan 32-byte key.
SembastCodec getAesGcmSembastCodec(List<int> keyBytes) {
  return SembastCodec(signature: 'aes_gcm_256', codec: _AesGcmCodec(keyBytes));
}

class _AesGcmCodec extends Codec<Map<String, Object?>, String> {
  _AesGcmCodec(List<int> keyBytes) : _key = Key(Uint8List.fromList(keyBytes));
  final Key _key;

  @override
  Converter<Map<String, Object?>, String> get encoder => _AesGcmEncoder(_key);

  @override
  Converter<String, Map<String, Object?>> get decoder => _AesGcmDecoder(_key);
}

class _AesGcmEncoder extends Converter<Map<String, Object?>, String> {
  _AesGcmEncoder(this.key);
  final Key key;

  @override
  String convert(Map<String, Object?> input) {
    final jsonStr = json.encode(input);
    final iv = IV.fromSecureRandom(12); // Standard GCM 12-byte IV
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);

    final combined = BytesBuilder()
      ..add(iv.bytes)
      ..add(encrypted.bytes);
    return base64.encode(combined.toBytes());
  }
}

class _AesGcmDecoder extends Converter<String, Map<String, Object?>> {
  _AesGcmDecoder(this.key);
  final Key key;

  @override
  Map<String, Object?> convert(String input) {
    final data = base64.decode(input);
    if (data.length < 12) {
      throw const FormatException('Payload enkripsi terlalu pendek.');
    }
    final ivBytes = data.sublist(0, 12);
    final cipherBytes = data.sublist(12);

    final iv = IV(ivBytes);
    final encrypted = Encrypted(cipherBytes);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return json.decode(decrypted) as Map<String, Object?>;
  }
}
