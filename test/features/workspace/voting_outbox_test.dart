import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/workspace/data/http_voting_api_client.dart';
import 'package:var_app/features/workspace/data/sembast_voting_outbox.dart';
import 'package:var_app/features/workspace/domain/voting.dart';

final class _TokenProvider implements VotingIdTokenProvider {
  @override
  Future<String?> token() async => 'firebase-token';
}

void main() {
  VotingBallotMutation ballot(String id, Set<String> choices) =>
      VotingBallotMutation(
        mutationId: id,
        roomId: 'room',
        boardId: 'board',
        sessionId: 'session',
        uid: 'user',
        choices: choices,
        status: VotingDeliveryStatus.queued,
        attemptCount: 0,
        nextAttemptAt: DateTime.utc(2026, 7, 29),
      );

  test(
    'client sends exact authority path/body with Firebase bearer only',
    () async {
      late http.Request captured;
      final client = HttpVotingApiClient(
        endpoint: Uri.parse('https://vote.example'),
        client: MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
        idTokenProvider: _TokenProvider(),
      );
      await client.putBallot(ballot('mutation', <String>{'option'}));
      expect(
        captured.url.path,
        '/v1/rooms/room/boards/board/sessions/session/ballot',
      );
      expect(captured.headers['authorization'], 'Bearer firebase-token');
      expect(captured.headers.keys, isNot(contains('x-membership-grant')));
      expect(jsonDecode(captured.body), <String, Object?>{
        'roomId': 'room',
        'boardId': 'board',
        'sessionId': 'session',
        'mutationId': 'mutation',
        'choices': <String>['option'],
      });
    },
  );

  test(
    'coalesces desired ballot and stale delivery cannot replace it',
    () async {
      final db = await databaseFactoryMemory.openDatabase('voting.db');
      final outbox = SembastVotingOutbox(database: db);
      final first = ballot('first', <String>{'a'});
      final latest = ballot('latest', <String>{'b'});
      await outbox.enqueue(first);
      await outbox.enqueue(latest);
      final due = (await outbox.due(DateTime.utc(2026, 7, 30))).single;
      expect(due.mutationId, latest.mutationId);
      expect(due.choices, latest.choices);
      expect(
        await outbox.replaceIfCurrent(
          first.copyWith(status: VotingDeliveryStatus.accepted),
        ),
        isFalse,
      );
      expect((await outbox.get(latest.key))?.choices, <String>{'b'});
      await db.close();
    },
  );
}
