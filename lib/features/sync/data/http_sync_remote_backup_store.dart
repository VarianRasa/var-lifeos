/// REST-backed remote backup store for real multi-device sync endpoints.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/mindmap_backup_document.dart';
import '../domain/sync_account.dart';

final class SyncRemoteStoreException implements Exception {
  const SyncRemoteStoreException(
    this.message, {
    this.statusCode,
    this.body = '',
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String body;
  final Object? cause;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' status=$statusCode';
    return 'SyncRemoteStoreException:$code $message';
  }
}

final class HttpSyncRemoteBackupStore implements SyncRemoteBackupStore {
  HttpSyncRemoteBackupStore({
    required Uri endpoint,
    http.Client? client,
    FutureOr<String?> Function()? tokenProvider,
    this.requestTimeout = const Duration(seconds: 20),
    this.maxPayloadBytes = 10 * 1024 * 1024,
  }) : _endpoint = _normalizeEndpoint(endpoint),
       _client = client ?? http.Client(),
       _tokenProvider = tokenProvider;

  final Uri _endpoint;
  final http.Client _client;
  final FutureOr<String?> Function()? _tokenProvider;
  final Duration requestTimeout;
  final int maxPayloadBytes;

  @override
  Future<MindmapBackupDocument?> fetchLatestBackup(SyncUser user) async {
    final response = await _send(
      () async => _client.get(_backupUri(user), headers: await _headers()),
    );
    if (response.statusCode == 404 || response.statusCode == 204) {
      return null;
    }
    _requireSuccess(response, accepted: const {200});
    _requirePayloadSize(response.bodyBytes.length);
    return _decodeDocument(response.body, expectedUser: user);
  }

  @override
  Future<void> uploadBackup(
    SyncUser user,
    MindmapBackupDocument document,
  ) async {
    if (document.attachments.isNotEmpty) {
      throw const SyncRemoteStoreException(
        'Remote backup cannot contain attachment payloads.',
      );
    }
    final body = jsonEncode(document.toJson());
    _requirePayloadSize(utf8.encode(body).length);
    final response = await _send(
      () async => _client.put(
        _backupUri(user),
        headers: await _headers(hasBody: true),
        body: body,
      ),
    );
    _requireSuccess(response, accepted: const {200, 201, 204});
  }

  Uri _backupUri(SyncUser user) {
    final userId = Uri.encodeComponent(user.id);
    return _endpoint.resolve('users/$userId/mindmap-backup/latest');
  }

  Future<Map<String, String>> _headers({bool hasBody = false}) async {
    final headers = <String, String>{'accept': 'application/json'};
    if (hasBody) {
      headers['content-type'] = 'application/json; charset=utf-8';
    }

    final token = (await _tokenProvider?.call())?.trim() ?? '';
    if (token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    return headers;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(requestTimeout);
    } on SyncRemoteStoreException {
      rethrow;
    } on Object catch (error) {
      throw SyncRemoteStoreException(
        'Remote sync request failed.',
        cause: error,
      );
    }
  }

  void _requirePayloadSize(int bytes) {
    if (bytes <= maxPayloadBytes) return;
    throw SyncRemoteStoreException(
      'Remote backup payload is too large.',
      body: '$bytes bytes',
    );
  }

  void _requireSuccess(http.Response response, {required Set<int> accepted}) {
    if (accepted.contains(response.statusCode)) {
      return;
    }

    throw SyncRemoteStoreException(
      'Remote sync request was rejected.',
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  MindmapBackupDocument _decodeDocument(
    String body, {
    required SyncUser expectedUser,
  }) {
    try {
      final decoded = jsonDecode(body);
      final Object? payload;
      if (decoded is Map<Object?, Object?> &&
          decoded['backup'] is Map<Object?, Object?>) {
        final responseUserId = decoded['userId'];
        if (responseUserId != null && responseUserId is! String) {
          throw const FormatException('Backup response userId is invalid.');
        }
        if (responseUserId is String && responseUserId != expectedUser.id) {
          throw const FormatException(
            'Backup response belongs to another user.',
          );
        }
        payload = decoded['backup'];
      } else {
        payload = decoded;
      }
      if (payload is! Map<Object?, Object?>) {
        throw const FormatException('Backup response must be a JSON object.');
      }
      return MindmapBackupDocument.fromJson(payload.cast<String, Object?>());
    } on FormatException catch (error) {
      throw SyncRemoteStoreException(
        'Remote backup response is invalid.',
        cause: error,
      );
    }
  }
}

Uri _normalizeEndpoint(Uri endpoint) {
  final value = endpoint.toString();
  return Uri.parse(value.endsWith('/') ? value : '$value/');
}
