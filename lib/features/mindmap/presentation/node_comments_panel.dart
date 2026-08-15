import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/collaboration_session.dart';
import '../application/node_comment_controller.dart';
import '../domain/collaboration_room.dart';

final class NodeCommentsPanel extends ConsumerStatefulWidget {
  const NodeCommentsPanel({
    required this.roomId,
    required this.localNodeId,
    super.key,
  });

  final String roomId;
  final String localNodeId;

  @override
  ConsumerState<NodeCommentsPanel> createState() => _NodeCommentsPanelState();
}

final class _NodeCommentsPanelState extends ConsumerState<NodeCommentsPanel> {
  final _composer = TextEditingController();

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _send(NodeCommentThreadKey key) async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    try {
      await ref.read(nodeCommentThreadProvider(key).notifier).submit(body);
      _composer.clear();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = NodeCommentThreadKey(widget.roomId, widget.localNodeId);
    final state = ref.watch(nodeCommentThreadProvider(key));
    final session = ref.watch(activeCollaborationSessionProvider);
    if (session == null || session.roomId != widget.roomId) {
      return const Center(
        child: Text('Sign in and join room to view comments.'),
      );
    }
    if (state.binding == null && !state.comments.isLoading) {
      return const Center(child: Text('Node is not bound to this room.'));
    }
    final canComment = session.role.canComment;
    return Column(
      children: [
        Expanded(
          child: state.comments.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (comments) => comments.isEmpty
                ? const Center(child: Text('No comments yet.'))
                : ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final comment = comments[index];
                      return ListTile(
                        title: Text(comment.authorDisplayName),
                        subtitle: Text(comment.body),
                        trailing: Text(
                          '${DateFormat.yMd().add_jm().format(comment.createdAt)}${comment.pending ? '\nPending' : ''}',
                          textAlign: TextAlign.end,
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (canComment)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: 'Comment',
                      hintText: 'Write comment',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Send comment',
                  child: FilledButton(
                    onPressed: state.submitting ? null : () => _send(key),
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Viewer access is read-only.'),
          ),
      ],
    );
  }
}
