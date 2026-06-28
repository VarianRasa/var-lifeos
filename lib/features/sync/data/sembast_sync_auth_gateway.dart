/// Sembast-backed local auth state for sync.
library;

import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/sync_account.dart';

final class SembastSyncAuthGateway implements SyncAuthGateway {
  SembastSyncAuthGateway({required FutureOr<Database> database})
    : _databaseSource = database;

  static const String _storeName = 'sync_auth';
  static const String _stateKey = 'state';

  final FutureOr<Database> _databaseSource;
  final StoreRef<String, Map<String, Object?>> _store = stringMapStoreFactory
      .store(_storeName);
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final opened = await Future<Database>.value(_databaseSource);
    _database = opened;
    return opened;
  }

  @override
  Future<SyncAuthState> currentState() async {
    final db = await _db;
    final value = await _store.record(_stateKey).get(db);
    if (value == null) return const SyncAuthState.signedOut();

    final rawUser = value['user'];
    if (rawUser is! Map) return const SyncAuthState.signedOut();

    final user = _userFromJson(rawUser.cast<String, Object?>());
    return SyncAuthState.signedIn(user);
  }

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String displayName = '',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError.value(email, 'email', 'Email is required.');
    }

    final user = SyncUser(
      id: 'local-$normalizedEmail',
      email: normalizedEmail,
      displayName: displayName.trim(),
    );
    final db = await _db;
    await _store.record(_stateKey).put(db, {
      'status': SyncAuthStatus.signedIn.name,
      'user': _userToJson(user),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    return SyncAuthState.signedIn(user);
  }

  @override
  Future<void> signOut() async {
    final db = await _db;
    await _store.record(_stateKey).delete(db);
  }
}

SyncUser _userFromJson(Map<String, Object?> json) {
  return SyncUser(
    id: json['id'] as String? ?? '',
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
  );
}

Map<String, Object?> _userToJson(SyncUser user) => {
  'id': user.id,
  'email': user.email,
  'displayName': user.displayName,
};
