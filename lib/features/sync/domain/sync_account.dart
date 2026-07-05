/// Account and remote-store contracts for sync.
library;

import 'mindmap_backup_document.dart';

enum SyncAuthStatus { signedOut, signedIn }

final class SyncUser {
  const SyncUser({
    required this.id,
    required this.email,
    this.displayName = '',
  });

  final String id;
  final String email;
  final String displayName;

  @override
  bool operator ==(Object other) {
    return other is SyncUser &&
        other.id == id &&
        other.email == email &&
        other.displayName == displayName;
  }

  @override
  int get hashCode => Object.hash(id, email, displayName);
}

final class SyncAuthState {
  const SyncAuthState._({required this.status, this.user, this.accessToken});

  const SyncAuthState.signedOut()
    : this._(status: SyncAuthStatus.signedOut, accessToken: null);

  const SyncAuthState.signedIn(SyncUser user, {String? accessToken})
    : this._(
        status: SyncAuthStatus.signedIn,
        user: user,
        accessToken: accessToken,
      );

  final SyncAuthStatus status;
  final SyncUser? user;
  final String? accessToken;

  bool get isSignedIn => status == SyncAuthStatus.signedIn && user != null;
}

final class SyncAuthException implements Exception {
  const SyncAuthException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SyncAuthException: $message';
}

abstract interface class SyncAuthGateway {
  Future<SyncAuthState> currentState();

  Future<SyncAuthState> signIn({
    required String email,
    String password = '',
    String displayName = '',
  });

  Future<SyncAuthState> register({
    required String email,
    required String password,
    String displayName = '',
  });

  Future<void> sendPasswordResetEmail({required String email});

  Future<void> signOut();
}

abstract interface class SyncRemoteBackupStore {
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user);

  Future<void> uploadBackup(SyncUser user, MindmapBackupDocument document);
}
