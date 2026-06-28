/// REST-backed sync auth gateway that stores the returned session locally.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';

import '../domain/sync_account.dart';
import 'http_sync_remote_backup_store.dart';

final class HttpSyncAuthGateway implements SyncAuthGateway {
  HttpSyncAuthGateway({
    required Uri endpoint,
    required FutureOr<Database> database,
    http.Client? client,
  }) : _endpoint = _normalizeEndpoint(endpoint),
       _databaseSource = database,
       _client = client ?? http.Client();

  static const String _storeName = 'sync_auth';
  static const String _stateKey = 'state';

  final Uri _endpoint;
  final FutureOr<Database> _databaseSource;
  final http.Client _client;
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

    final accessToken = value['accessToken'] as String?;
    return SyncAuthState.signedIn(
      _userFromJson(rawUser.cast<String, Object?>()),
      accessToken: accessToken?.trim().isEmpty == true ? null : accessToken,
    );
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

    final response = await _send(
      () => _client.post(
        _endpoint.resolve('auth/sign-in'),
        headers: const {
          'accept': 'application/json',
          'content-type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'email': normalizedEmail,
          'displayName': displayName.trim(),
        }),
      ),
    );
    _requireSuccess(response, accepted: const {200, 201});

    final state = _authStateFromResponse(response.body);
    await _saveState(state);
    return state;
  }

  @override
  Future<void> signOut() async {
    final previous = await currentState();
    final token = previous.accessToken?.trim() ?? '';
    if (token.isNotEmpty) {
      await _send(
        () => _client.post(
          _endpoint.resolve('auth/sign-out'),
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer $token',
          },
        ),
        ignoreRemoteErrors: true,
      );
    }

    final db = await _db;
    await _store.record(_stateKey).delete(db);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    bool ignoreRemoteErrors = false,
  }) async {
    try {
      final response = await request();
      if (ignoreRemoteErrors) return response;
      return response;
    } on Object catch (error) {
      if (ignoreRemoteErrors) {
        return http.Response('', 503);
      }
      throw SyncRemoteStoreException(
        'Remote auth request failed.',
        cause: error,
      );
    }
  }

  void _requireSuccess(http.Response response, {required Set<int> accepted}) {
    if (accepted.contains(response.statusCode)) return;

    throw SyncRemoteStoreException(
      'Remote auth request was rejected.',
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  SyncAuthState _authStateFromResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Auth response must be an object.');
      }
      final json = decoded.cast<String, Object?>();
      final rawUser = json['user'];
      final accessToken = json['accessToken'] as String? ?? '';
      if (rawUser is! Map || accessToken.trim().isEmpty) {
        throw const FormatException('Auth response is missing session data.');
      }

      return SyncAuthState.signedIn(
        _userFromJson(rawUser.cast<String, Object?>()),
        accessToken: accessToken.trim(),
      );
    } on FormatException catch (error) {
      throw SyncRemoteStoreException(
        'Remote auth response is invalid.',
        cause: error,
      );
    }
  }

  Future<void> _saveState(SyncAuthState state) async {
    final user = state.user;
    if (!state.isSignedIn || user == null) return;

    final db = await _db;
    await _store.record(_stateKey).put(db, {
      'status': SyncAuthStatus.signedIn.name,
      'user': _userToJson(user),
      'accessToken': state.accessToken,
      'updatedAt': DateTime.now().toIso8601String(),
    });
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

Uri _normalizeEndpoint(Uri endpoint) {
  final value = endpoint.toString();
  return Uri.parse(value.endsWith('/') ? value : '$value/');
}
