/// Local development auth gateway for sync flows.
library;

import '../domain/sync_account.dart';

final class LocalSyncAuthGateway implements SyncAuthGateway {
  SyncAuthState _state = const SyncAuthState.signedOut();

  @override
  Future<SyncAuthState> currentState() async => _state;

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String displayName = '',
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError.value(email, 'email', 'Email is required.');
    }

    _state = SyncAuthState.signedIn(
      SyncUser(
        id: 'local-$normalizedEmail',
        email: normalizedEmail,
        displayName: displayName.trim(),
      ),
    );
    return _state;
  }

  @override
  Future<void> signOut() async {
    _state = const SyncAuthState.signedOut();
  }
}
