import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/node_comment.dart';

void main() {
  test('trims and parses immutable comment data', () {
    final createdAt = DateTime.utc(2026, 7, 28);
    final comment = NodeComment.fromJson({
      'id': 'comment',
      'roomId': 'room',
      'nodeId': 'node',
      'body': ' body ',
      'authorUid': 'author',
      'authorDisplayName': ' Name ',
      'createdAt': createdAt,
    }, pending: true);

    expect(comment.body, 'body');
    expect(comment.authorDisplayName, 'Name');
    expect(comment.createdAt, createdAt);
    expect(comment.pending, isTrue);
  });

  test('rejects empty and oversized bodies', () {
    expect(
      () => NodeComment(
        id: 'id',
        roomId: 'room',
        nodeId: 'node',
        body: ' ',
        authorUid: 'author',
        authorDisplayName: 'Name',
        createdAt: DateTime.now(),
        pending: false,
      ),
      throwsFormatException,
    );
    expect(
      () => NodeComment(
        id: 'id',
        roomId: 'room',
        nodeId: 'node',
        body: 'x' * 4001,
        authorUid: 'author',
        authorDisplayName: 'Name',
        createdAt: DateTime.now(),
        pending: false,
      ),
      throwsFormatException,
    );
  });
}
