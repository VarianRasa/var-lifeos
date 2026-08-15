import 'package:firebase_auth/firebase_auth.dart';

import 'http_voting_api_client.dart';

final class FirebaseVotingIdTokenProvider implements VotingIdTokenProvider {
  const FirebaseVotingIdTokenProvider();

  @override
  Future<String?> token() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();
}
