import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/config/runtime_config.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../data/firebase_voting_id_token_provider.dart';
import '../data/http_voting_api_client.dart';
import '../data/sembast_voting_outbox.dart';
import '../domain/voting.dart';
import 'voting_sync_service.dart';

final votingOutboxProvider = Provider<SembastVotingOutbox>((ref) {
  return SembastVotingOutbox(database: ref.watch(mindmapDatabaseProvider));
});

final votingApiClientProvider = Provider<HttpVotingApiClient?>((ref) {
  final endpoint = ref.watch(runtimeConfigProvider).votingApiEndpoint;
  if (endpoint == null) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpVotingApiClient(
    endpoint: endpoint,
    client: client,
    idTokenProvider: const FirebaseVotingIdTokenProvider(),
  );
});

final votingSyncServiceProvider = Provider<VotingSyncService?>((ref) {
  final api = ref.watch(votingApiClientProvider);
  return api == null
      ? null
      : VotingSyncService(outbox: ref.watch(votingOutboxProvider), api: api);
});

Future<VotingBallotMutation> enqueueVotingBallot(
  WidgetRef ref, {
  required String roomId,
  required String boardId,
  required String sessionId,
  required String uid,
  required Set<String> choices,
}) async {
  final mutation = VotingBallotMutation(
    mutationId: const Uuid().v4(),
    roomId: roomId,
    boardId: boardId,
    sessionId: sessionId,
    uid: uid,
    choices: choices,
    status: VotingDeliveryStatus.queued,
    attemptCount: 0,
    nextAttemptAt: DateTime.now().toUtc(),
  );
  await ref.read(votingOutboxProvider).enqueue(mutation);
  return mutation;
}
