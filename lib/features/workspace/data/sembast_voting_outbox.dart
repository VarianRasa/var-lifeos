import 'dart:async';

import 'package:sembast/sembast.dart';

import '../domain/voting.dart';

final class SembastVotingOutbox {
  SembastVotingOutbox({required FutureOr<Database> database})
    : _databaseSource = database;

  final FutureOr<Database> _databaseSource;
  final _store = stringMapStoreFactory.store('voting_ballot_outbox');
  Database? _database;

  Future<Database> get _db async =>
      _database ??= await Future<Database>.value(_databaseSource);

  Future<void> enqueue(VotingBallotMutation mutation) async {
    await _store.record(mutation.key).put(await _db, mutation.toJson());
  }

  Future<VotingBallotMutation?> get(String key) async {
    final value = await _store.record(key).get(await _db);
    return value == null ? null : VotingBallotMutation.fromJson(value);
  }

  Future<List<VotingBallotMutation>> due(DateTime now) async =>
      (await _store.find(await _db))
          .map((record) => VotingBallotMutation.fromJson(record.value))
          .where(
            (mutation) =>
                mutation.status == VotingDeliveryStatus.queued &&
                !mutation.nextAttemptAt.isAfter(now.toUtc()),
          )
          .toList(growable: false);

  Future<bool> replaceIfCurrent(VotingBallotMutation mutation) async {
    final record = _store.record(mutation.key);
    final value = await record.get(await _db);
    if (value == null || value['mutationId'] != mutation.mutationId) {
      return false;
    }
    await record.put(await _db, mutation.toJson());
    return true;
  }
}
