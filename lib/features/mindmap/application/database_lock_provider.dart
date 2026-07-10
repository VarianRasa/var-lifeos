import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseLockState {
  DatabaseLockState({
    required this.isLocked,
    required this.hasPin,
    required this.unlockedPin,
  });

  final bool isLocked;
  final bool hasPin;
  final String? unlockedPin;

  DatabaseLockState copyWith({
    bool? isLocked,
    bool? hasPin,
    String? unlockedPin,
  }) {
    return DatabaseLockState(
      isLocked: isLocked ?? this.isLocked,
      hasPin: hasPin ?? this.hasPin,
      unlockedPin: unlockedPin ?? this.unlockedPin,
    );
  }
}

class DatabaseLockNotifier extends StateNotifier<DatabaseLockState> {
  DatabaseLockNotifier()
      : super(DatabaseLockState(isLocked: false, hasPin: false, unlockedPin: null)) {
    _init();
  }

  static const _pinKey = 'db_pin_hash';

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = prefs.getString(_pinKey);
      if (hash != null && hash.isNotEmpty) {
        state = DatabaseLockState(
          isLocked: true,
          hasPin: true,
          unlockedPin: null,
        );
      }
    } catch (_) {}
  }

  Future<bool> unlock(String pin) async {
    if (!state.hasPin) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_pinKey);
      final enteredHash = _hashPin(pin);
      if (storedHash == enteredHash) {
        state = state.copyWith(isLocked: false, unlockedPin: pin);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> setPin(String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hash = _hashPin(pin);
      await prefs.setString(_pinKey, hash);
      state = DatabaseLockState(
        isLocked: false,
        hasPin: true,
        unlockedPin: pin,
      );
    } catch (_) {}
  }

  Future<void> removePin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pinKey);
      state = DatabaseLockState(
        isLocked: false,
        hasPin: false,
        unlockedPin: null,
      );
    } catch (_) {}
  }

  String _hashPin(String pin) {
    // Simple hash function to avoid plain text PIN storage
    return pin.codeUnits.fold<int>(0, (prev, val) => prev * 31 + val).toString();
  }
}

final databaseLockProvider =
    StateNotifierProvider<DatabaseLockNotifier, DatabaseLockState>((ref) {
  return DatabaseLockNotifier();
});
