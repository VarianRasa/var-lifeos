final class NodeComment {
  NodeComment({
    required this.id,
    required this.roomId,
    required this.nodeId,
    required String body,
    required this.authorUid,
    required String authorDisplayName,
    required this.createdAt,
    required this.pending,
  }) : body = body.trim(),
       authorDisplayName = authorDisplayName.trim() {
    if (id.isEmpty ||
        roomId.isEmpty ||
        nodeId.isEmpty ||
        this.body.isEmpty ||
        this.body.length > 4000 ||
        authorUid.isEmpty ||
        this.authorDisplayName.length > 100) {
      throw const FormatException('Invalid node comment.');
    }
  }

  factory NodeComment.fromJson(
    Map<String, Object?> json, {
    required bool pending,
  }) {
    if (json.keys.toSet().difference(_keys).isNotEmpty ||
        !_keys.every(json.containsKey) ||
        json['id'] is! String ||
        json['roomId'] is! String ||
        json['nodeId'] is! String ||
        json['body'] is! String ||
        json['authorUid'] is! String ||
        json['authorDisplayName'] is! String ||
        json['createdAt'] is! DateTime) {
      throw const FormatException('Invalid node comment JSON.');
    }
    return NodeComment(
      id: json['id']! as String,
      roomId: json['roomId']! as String,
      nodeId: json['nodeId']! as String,
      body: json['body']! as String,
      authorUid: json['authorUid']! as String,
      authorDisplayName: json['authorDisplayName']! as String,
      createdAt: json['createdAt']! as DateTime,
      pending: pending,
    );
  }

  static const _keys = {
    'id',
    'roomId',
    'nodeId',
    'body',
    'authorUid',
    'authorDisplayName',
    'createdAt',
  };

  final String id;
  final String roomId;
  final String nodeId;
  final String body;
  final String authorUid;
  final String authorDisplayName;
  final DateTime createdAt;
  final bool pending;

  Map<String, Object?> toJson() => {
    'id': id,
    'roomId': roomId,
    'nodeId': nodeId,
    'body': body,
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'createdAt': createdAt,
  };
}
