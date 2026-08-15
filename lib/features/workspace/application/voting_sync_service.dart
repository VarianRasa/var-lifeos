import 'dart:async';

import '../data/http_voting_api_client.dart';
import '../data/sembast_voting_outbox.dart';
import '../domain/voting.dart';

final class VotingSyncService {
  const VotingSyncService({
    required SembastVotingOutbox outbox,
    required HttpVotingApiClient api,
  }) : _outbox = outbox,
       _api = api;

  final SembastVotingOutbox _outbox;
  final HttpVotingApiClient _api;

  Future<void> flush(DateTime now) async {
    for (final mutation in await _outbox.due(now)) {
      final syncing = mutation.copyWith(status: VotingDeliveryStatus.syncing);
      if (!await _outbox.replaceIfCurrent(syncing)) continue;
      try {
        await _api.putBallot(syncing);
        await _outbox.replaceIfCurrent(
          syncing.copyWith(status: VotingDeliveryStatus.accepted),
        );
      } on VotingApiException catch (error) {
        final retry =
            error.statusCode == 408 ||
            error.statusCode == 429 ||
            error.statusCode >= 500;
        final attempts = syncing.attemptCount + 1;
        await _outbox.replaceIfCurrent(
          syncing.copyWith(
            status: retry
                ? VotingDeliveryStatus.queued
                : VotingDeliveryStatus.rejected,
            attemptCount: attempts,
            nextAttemptAt: now.toUtc().add(
              Duration(seconds: 1 << attempts.clamp(0, 6)),
            ),
            error: error.message,
          ),
        );
      } on Object catch (error) {
        final attempts = syncing.attemptCount + 1;
        await _outbox.replaceIfCurrent(
          syncing.copyWith(
            status: VotingDeliveryStatus.queued,
            attemptCount: attempts,
            nextAttemptAt: now.toUtc().add(
              Duration(seconds: 1 << attempts.clamp(0, 6)),
            ),
            error: error.runtimeType.toString(),
          ),
        );
      }
    }
  }

  Stream<VotingAggregate> pollAggregate({
    required String roomId,
    required String boardId,
    required String sessionId,
    Duration interval = const Duration(seconds: 3),
  }) async* {
    while (true) {
      yield await _api.aggregate(
        roomId: roomId,
        boardId: boardId,
        sessionId: sessionId,
      );
      await Future<void>.delayed(interval);
    }
  }
}
