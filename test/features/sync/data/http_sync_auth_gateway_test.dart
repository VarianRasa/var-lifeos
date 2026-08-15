import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/sync/data/http_sync_auth_gateway.dart';
import 'package:var_app/features/sync/data/http_sync_remote_backup_store.dart';
import 'package:var_app/features/sync/domain/sync_account.dart';

void main() {
  test(
    'signs in through REST and persists the returned access token',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'http-sync-auth.db',
      );
      addTearDown(database.close);
      http.Request? capturedRequest;
      final gateway = HttpSyncAuthGateway(
        endpoint: Uri.parse('https://api.var.app/sync'),
        database: database,
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'user': {
                'id': 'user-1',
                'email': 'user@example.com',
                'displayName': 'User',
              },
              'accessToken': 'session-token-123',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final state = await gateway.signIn(
        email: 'USER@example.com',
        displayName: 'User',
      );
      final restored = await HttpSyncAuthGateway(
        endpoint: Uri.parse('https://api.var.app/sync'),
        database: database,
        client: MockClient((request) async => http.Response('', 500)),
      ).currentState();

      final request = capturedRequest;
      expect(request, isNotNull);
      expect(request!.method, 'POST');
      expect(request.url.toString(), 'https://api.var.app/sync/auth/sign-in');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['email'], 'user@example.com');
      expect(body['displayName'], 'User');
      expect(state.status, SyncAuthStatus.signedIn);
      expect(state.accessToken, 'session-token-123');
      expect(restored.user?.id, 'user-1');
      expect(restored.accessToken, 'session-token-123');
    },
  );

  test('rejects auth responses for another account', () async {
    final database = await databaseFactoryMemory.openDatabase('auth-mismatch');
    addTearDown(database.close);
    final gateway = HttpSyncAuthGateway(
      endpoint: Uri.parse('https://api.var.app/sync'),
      database: database,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'user': {'id': 'other-user', 'email': 'other@example.com'},
            'accessToken': 'token',
          }),
          200,
        ),
      ),
    );

    expect(
      () => gateway.signIn(email: 'user@example.com'),
      throwsA(isA<SyncRemoteStoreException>()),
    );
  });
  test('clears the persisted session after sign out', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'http-sync-auth-sign-out.db',
    );
    addTearDown(database.close);
    final gateway = HttpSyncAuthGateway(
      endpoint: Uri.parse('https://api.var.app/sync'),
      database: database,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/sign-in')) {
          return http.Response(
            jsonEncode({
              'user': {'id': 'user-1', 'email': 'user@example.com'},
              'accessToken': 'session-token-123',
            }),
            200,
          );
        }
        return http.Response('', 204);
      }),
    );

    await gateway.signIn(email: 'user@example.com');
    await gateway.signOut();

    final state = await gateway.currentState();
    expect(state.status, SyncAuthStatus.signedOut);
    expect(state.accessToken, isNull);
  });
}
