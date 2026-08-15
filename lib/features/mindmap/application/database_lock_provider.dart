import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseLockState {
  DatabaseLockState({
    required this.isLocked,
    required this.hasPin,
    required this.unlockedPin,
    this.keyBytes,
  });

  final bool isLocked;
  final bool hasPin;
  final String? unlockedPin;
  final List<int>? keyBytes;

  DatabaseLockState copyWith({
    bool? isLocked,
    bool? hasPin,
    String? unlockedPin,
    List<int>? keyBytes,
  }) {
    return DatabaseLockState(
      isLocked: isLocked ?? this.isLocked,
      hasPin: hasPin ?? this.hasPin,
      unlockedPin: unlockedPin ?? this.unlockedPin,
      keyBytes: keyBytes ?? this.keyBytes,
    );
  }
}

class DatabaseLockNotifier extends StateNotifier<DatabaseLockState> {
  DatabaseLockNotifier()
    : super(
        DatabaseLockState(
          isLocked: false,
          hasPin: false,
          unlockedPin: null,
          keyBytes: null,
        ),
      ) {
    _init();
  }

  static const _pinKey = 'db_pin_hash';
  static const _saltKey = 'db_pin_salt';

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString(_pinKey);
      if (hash != null && hash.isNotEmpty) {
        state = DatabaseLockState(
          isLocked: true,
          hasPin: true,
          unlockedPin: null,
          keyBytes: null,
        );
      }
    } catch (_) {}
  }

  Future<bool> unlock(String pin) async {
    if (!state.hasPin) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_pinKey);
      final saltBase64 = prefs.getString(_saltKey);

      if (saltBase64 == null) {
        final enteredHash = _legacyHashPin(pin);
        if (storedHash == enteredHash) {
          state = state.copyWith(
            isLocked: false,
            unlockedPin: pin,
            keyBytes: null,
          );
          return true;
        }
        return false;
      }

      final salt = base64Decode(saltBase64);
      final derivedKey = await _derivePbkdf2Key(pin, salt);
      final enteredHash = base64Encode(derivedKey);

      if (storedHash == enteredHash) {
        state = state.copyWith(
          isLocked: false,
          unlockedPin: pin,
          keyBytes: derivedKey,
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> setPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final salt = List<int>.generate(16, (i) => (i * 31 + pin.length) % 256);
      final secretKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );
      final derivedKeyBytes = await secretKey.extractBytes();

      await prefs.setString(_saltKey, base64Encode(salt));
      await prefs.setString(_pinKey, base64Encode(derivedKeyBytes));

      state = DatabaseLockState(
        isLocked: false,
        hasPin: true,
        unlockedPin: pin,
        keyBytes: derivedKeyBytes,
      );
    } catch (_) {}
  }

  Future<void> removePin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pinKey);
      await prefs.remove(_saltKey);
      state = DatabaseLockState(
        isLocked: false,
        hasPin: false,
        unlockedPin: null,
        keyBytes: null,
      );
    } catch (_) {}
  }

  Future<List<int>> _derivePbkdf2Key(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  String _legacyHashPin(String pin) {
    return pin.codeUnits
        .fold<int>(0, (prev, val) => prev * 31 + val)
        .toString();
  }
}

final databaseLockProvider =
    StateNotifierProvider<DatabaseLockNotifier, DatabaseLockState>((ref) {
      return DatabaseLockNotifier();
    });
