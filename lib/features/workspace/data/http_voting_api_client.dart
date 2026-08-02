import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/voting.dart';

abstract interface class VotingIdTokenProvider {
  Future<String?> token();
}

final class VotingApiException implements Exception {
  const VotingApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

final class HttpVotingApiClient {
  const HttpVotingApiClient({
    required Uri endpoint,
    required http.Client client,
    required VotingIdTokenProvider idTokenProvider,
  }) : _endpoint = endpoint,
       _client = client,
       _idTokenProvider = idTokenProvider;

  final Uri _endpoint;
  final http.Client _client;
  final VotingIdTokenProvider _idTokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _idTokenProvider.token();
    if (token == null || token.isEmpty) {
      throw const VotingApiException(401, 'Firebase sign-in required.');
    }
    return <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Uri _resource(
    String roomId,
    String boardId,
    String sessionId,
    String resource,
  ) => _endpoint.replace(
    pathSegments: <String>[
      ..._endpoint.pathSegments.where((segment) => segment.isNotEmpty),
      'v1',
      'rooms',
      roomId,
      'boards',
      boardId,
      'sessions',
      sessionId,
      resource,
    ],
  );

  Future<void> putBallot(VotingBallotMutation mutation) async {
    final response = await _client.put(
      _resource(
        mutation.roomId,
        mutation.boardId,
        mutation.sessionId,
        'ballot',
      ),
      headers: await _headers(),
      body: jsonEncode(<String, Object?>{
        'roomId': mutation.roomId,
        'boardId': mutation.boardId,
        'sessionId': mutation.sessionId,
        'mutationId': mutation.mutationId,
        'choices': mutation.choices.toList()..sort(),
      }),
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<VotingAggregate> aggregate({
    required String roomId,
    required String boardId,
    required String sessionId,
  }) async {
    final response = await _client.get(
      _resource(roomId, boardId, sessionId, 'aggregate'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) _throwResponse(response);
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return VotingAggregate(
      sessionId: json['sessionId']! as String,
      totals: <String, int>{
        for (final value in json['totals']! as List)
          (value as Map<String, Object?>)['optionId']! as String:
              value['total']! as int,
      },
    );
  }

  Never _throwResponse(http.Response response) {
    String message = 'Voting request failed.';
    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      message = json['error'] as String? ?? message;
    } on FormatException {
      message = 'Voting request failed.';
    }
    throw VotingApiException(response.statusCode, message);
  }
}
