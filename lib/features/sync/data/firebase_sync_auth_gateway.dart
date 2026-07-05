/// Firebase Authentication adapter for sync accounts.
library;

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../domain/sync_account.dart';

final class FirebaseSyncAuthGateway implements SyncAuthGateway {
  FirebaseSyncAuthGateway({firebase_auth.FirebaseAuth? auth})
    : _authInstance = auth;

  final firebase_auth.FirebaseAuth? _authInstance;

  firebase_auth.FirebaseAuth get _auth =>
      _authInstance ?? firebase_auth.FirebaseAuth.instance;

  @override
  Future<SyncAuthState> currentState() async {
    final user = _auth.currentUser;
    if (user == null) return const SyncAuthState.signedOut();
    return _stateFromUser(user);
  }

  @override
  Future<SyncAuthState> signIn({
    required String email,
    String password = '',
    String displayName = '',
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedPassword = _requirePassword(password);
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: normalizedPassword,
      );
      final user = credential.user;
      if (user == null) {
        throw const SyncAuthException('Sign-in failed. Please try again.');
      }
      return _stateFromUser(user);
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw SyncAuthException(_messageForCode(error.code), cause: error);
    } on SyncAuthException {
      rethrow;
    } on Object catch (error) {
      throw SyncAuthException(
        'Sign-in failed. Please try again.',
        cause: error,
      );
    }
  }

  @override
  Future<SyncAuthState> register({
    required String email,
    required String password,
    String displayName = '',
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final normalizedPassword = _requirePassword(password);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: normalizedPassword,
      );
      final user = credential.user;
      if (user == null) {
        throw const SyncAuthException(
          'Account creation failed. Please try again.',
        );
      }
      final normalizedDisplayName = displayName.trim();
      if (normalizedDisplayName.isNotEmpty &&
          user.displayName != normalizedDisplayName) {
        await user.updateDisplayName(normalizedDisplayName);
        await user.reload();
      }
      return _stateFromUser(_auth.currentUser ?? user);
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw SyncAuthException(_messageForCode(error.code), cause: error);
    } on SyncAuthException {
      rethrow;
    } on Object catch (error) {
      throw SyncAuthException(
        'Account creation failed. Please try again.',
        cause: error,
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalizedEmail = _normalizeEmail(email);
    try {
      await _auth.sendPasswordResetEmail(email: normalizedEmail);
    } on firebase_auth.FirebaseAuthException catch (error) {
      throw SyncAuthException(_messageForCode(error.code), cause: error);
    } on SyncAuthException {
      rethrow;
    } on Object catch (error) {
      throw SyncAuthException(
        'Password reset failed. Please try again.',
        cause: error,
      );
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<SyncAuthState> _stateFromUser(firebase_auth.User user) async {
    final token = await user.getIdToken();
    return SyncAuthState.signedIn(
      SyncUser(
        id: user.uid,
        email: (user.email ?? '').trim().toLowerCase(),
        displayName: user.displayName?.trim() ?? '',
      ),
      accessToken: token?.trim().isEmpty == true ? null : token,
    );
  }
}

String _normalizeEmail(String email) {
  final normalized = email.trim().toLowerCase();
  if (normalized.isEmpty) {
    throw ArgumentError.value(email, 'email', 'Email is required.');
  }
  return normalized;
}

String _requirePassword(String password) {
  if (password.isEmpty) {
    throw ArgumentError.value(password, 'password', 'Password is required.');
  }
  return password;
}

String _messageForCode(String code) {
  return switch (code) {
    'invalid-email' => 'Enter a valid email address.',
    'user-disabled' => 'This account is disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'Email or password is incorrect.',
    'email-already-in-use' => 'An account already exists for this email.',
    'weak-password' => 'Use a stronger password.',
    'network-request-failed' => 'Network unavailable. Check your connection.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    _ => 'Authentication failed. Please try again.',
  };
}
