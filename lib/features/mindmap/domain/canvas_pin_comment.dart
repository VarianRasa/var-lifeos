class CanvasPinComment {
  const CanvasPinComment({
    required this.id,
    required this.x,
    required this.y,
    required this.message,
    required this.author,
    required this.createdAt,
    this.isResolved = false,
    this.replies = const [],
  });

  factory CanvasPinComment.fromJson(Map<String, Object?> json) {
    final rawReplies = json['replies'] as List?;
    return CanvasPinComment(
      id: json['id']! as String,
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      message: json['message']! as String,
      author: json['author'] as String? ?? 'Anonymous',
      createdAt: DateTime.parse(json['createdAt']! as String),
      isResolved: json['isResolved'] as bool? ?? false,
      replies: rawReplies != null
          ? rawReplies
                .whereType<Map<String, Object?>>()
                .map(CanvasPinCommentReply.fromJson)
                .toList()
          : const [],
    );
  }

  final String id;
  final double x;
  final double y;
  final String message;
  final String author;
  final DateTime createdAt;
  final bool isResolved;
  final List<CanvasPinCommentReply> replies;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'x': x,
      'y': y,
      'message': message,
      'author': author,
      'createdAt': createdAt.toIso8601String(),
      'isResolved': isResolved,
      'replies': replies.map((r) => r.toJson()).toList(),
    };
  }

  CanvasPinComment resolve() => CanvasPinComment(
    id: id,
    x: x,
    y: y,
    message: message,
    author: author,
    createdAt: createdAt,
    isResolved: true,
    replies: replies,
  );
}

class CanvasPinCommentReply {
  const CanvasPinCommentReply({
    required this.id,
    required this.message,
    required this.author,
    required this.createdAt,
  });

  factory CanvasPinCommentReply.fromJson(Map<String, Object?> json) {
    return CanvasPinCommentReply(
      id: json['id']! as String,
      message: json['message']! as String,
      author: json['author'] as String? ?? 'Anonymous',
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }

  final String id;
  final String message;
  final String author;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'message': message,
      'author': author,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
