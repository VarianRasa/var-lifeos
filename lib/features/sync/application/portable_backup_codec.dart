/// Encrypts/decrypts portable backup packages for manual sync flows.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../domain/mindmap_backup_document.dart';

class PortableBackupException implements Exception {
  const PortableBackupException(
    this.message, {
    this.primaryError,
    this.cleanupErrors = const [],
  });

  final String message;
  final Object? primaryError;
  final List<Object> cleanupErrors;

  @override
  String toString() => 'PortableBackupException: $message';
}

final class PortableMindmapBackupCodec {
  PortableMindmapBackupCodec({
    int iterations = 120000,
    List<int> Function(int length)? randomBytes,
  }) : _iterations = iterations,
       _randomBytes = randomBytes ?? _secureRandomBytes {
    if (iterations < minKdfIterations || iterations > maxKdfIterations) {
      throw const PortableBackupException('KDF iterations are invalid.');
    }
  }

  static const int schemaVersion = 1;
  static const int minKdfIterations = 100000;
  static const int maxKdfIterations = 1000000;
  static const int maxPackageBytes = 384 * 1024 * 1024;
  static const int maxCipherTextBytes = 288 * 1024 * 1024;
  static const int maxPlainTextBytes = 256 * 1024 * 1024;
  static const String packageType = 'var.mindmap.backup.encrypted';
  static const String algorithm = 'aes-gcm-256';
  static const String keyDerivation = 'pbkdf2-hmac-sha256';
  static const int _saltLength = 16;
  static const int _nonceLength = 12;

  final int _iterations;
  final List<int> Function(int length) _randomBytes;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<String> encode(
    MindmapBackupDocument document, {
    required String passphrase,
  }) async {
    final trimmedPassphrase = _requirePassphrase(passphrase);
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    if (salt.length != _saltLength || nonce.length != _nonceLength) {
      throw const PortableBackupException('Secure random bytes are invalid.');
    }
    final secretKey = await _deriveKey(trimmedPassphrase, salt, _iterations);
    final plainText = utf8.encode(jsonEncode(document.toJson()));
    if (plainText.length > maxPlainTextBytes) {
      throw const PortableBackupException(
        'Backup document exceeds size limit.',
      );
    }
    final secretBox = await _cipher.encrypt(
      plainText,
      secretKey: secretKey,
      nonce: nonce,
    );

    return jsonEncode({
      'type': packageType,
      'schemaVersion': schemaVersion,
      'algorithm': algorithm,
      'kdf': {
        'name': keyDerivation,
        'iterations': _iterations,
        'salt': base64Encode(salt),
      },
      'exportedAt': document.exportedAt.toIso8601String(),
      'sourceDevice': document.sourceDevice.toJson(),
      'nodeCount': document.nodes.length,
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<MindmapBackupDocument> decode(
    String package, {
    required String passphrase,
  }) async {
    final trimmedPassphrase = _requirePassphrase(passphrase);
    if (utf8.encode(package).length > maxPackageBytes) {
      throw const PortableBackupException('Backup package exceeds size limit.');
    }
    final packageJson = _decodePackageJson(package);
    final iterations = _readIterations(packageJson);
    final salt = _readKdfSalt(packageJson);
    final secretKey = await _deriveKey(trimmedPassphrase, salt, iterations);
    final cipherText = _readBase64(packageJson, 'cipherText');
    if (cipherText.length > maxCipherTextBytes) {
      throw const PortableBackupException(
        'Backup cipherText exceeds size limit.',
      );
    }
    final secretBox = SecretBox(
      cipherText,
      nonce: _readBase64(packageJson, 'nonce', exactLength: _nonceLength),
      mac: Mac(_readBase64(packageJson, 'mac', exactLength: 16)),
    );

    final plainText = await _decrypt(secretBox, secretKey);
    if (plainText.length > maxPlainTextBytes) {
      throw const PortableBackupException(
        'Backup document exceeds size limit.',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(plainText));
      if (decoded is! Map<Object?, Object?>) {
        throw const PortableBackupException('Backup document is invalid.');
      }

      return MindmapBackupDocument.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      throw const PortableBackupException('Backup document is invalid.');
    }
  }

  Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    int iterations,
  ) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  }

  Future<List<int>> _decrypt(SecretBox secretBox, SecretKey secretKey) async {
    try {
      return await _cipher.decrypt(secretBox, secretKey: secretKey);
    } on Object {
      throw const PortableBackupException(
        'Backup passphrase is incorrect or the package was changed.',
      );
    }
  }

  Map<String, Object?> _decodePackageJson(String package) {
    final Object? decoded;
    try {
      decoded = jsonDecode(package);
    } on FormatException {
      throw const PortableBackupException('Backup package is invalid.');
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const PortableBackupException('Backup package is invalid.');
    }
    final json = decoded.cast<String, Object?>();
    if (json['type'] != packageType) {
      throw const PortableBackupException('Unsupported backup package type.');
    }
    if (json['schemaVersion'] != schemaVersion) {
      throw const PortableBackupException(
        'Unsupported backup package schema version.',
      );
    }
    if (json['algorithm'] != algorithm) {
      throw const PortableBackupException('Unsupported backup algorithm.');
    }
    return json;
  }

  int _readIterations(Map<String, Object?> packageJson) {
    final kdf = _readKdf(packageJson);
    if (kdf['name'] != keyDerivation) {
      throw const PortableBackupException('Unsupported backup key derivation.');
    }
    final iterations = kdf['iterations'];
    if (iterations is! int ||
        iterations < minKdfIterations ||
        iterations > maxKdfIterations) {
      throw const PortableBackupException('Backup KDF iterations are invalid.');
    }
    return iterations;
  }

  List<int> _readKdfSalt(Map<String, Object?> packageJson) {
    return _readBase64(_readKdf(packageJson), 'salt', exactLength: _saltLength);
  }

  Map<String, Object?> _readKdf(Map<String, Object?> packageJson) {
    final rawKdf = packageJson['kdf'];
    if (rawKdf is! Map<Object?, Object?>) {
      throw const PortableBackupException('Backup KDF metadata is invalid.');
    }
    return rawKdf.cast<String, Object?>();
  }

  List<int> _readBase64(
    Map<String, Object?> json,
    String key, {
    int? exactLength,
  }) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw PortableBackupException('Backup $key is invalid.');
    }
    try {
      final bytes = base64Decode(value);
      if (exactLength != null && bytes.length != exactLength) {
        throw PortableBackupException('Backup $key is invalid.');
      }
      return bytes;
    } on FormatException {
      throw PortableBackupException('Backup $key is invalid.');
    }
  }

  String _requirePassphrase(String passphrase) {
    final trimmed = passphrase.trim();
    if (trimmed.isEmpty) {
      throw const PortableBackupException('Backup passphrase is required.');
    }
    return trimmed;
  }
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
