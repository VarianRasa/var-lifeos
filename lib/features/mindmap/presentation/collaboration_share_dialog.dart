import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/collaboration_controller.dart';
import '../domain/collaboration_room.dart';

Future<void> showCollaborationShareDialog(
  BuildContext context, {
  required String targetLabel,
}) => showDialog<void>(
  context: context,
  builder: (_) => CollaborationShareDialog(targetLabel: targetLabel),
);

class CollaborationShareDialog extends ConsumerStatefulWidget {
  const CollaborationShareDialog({super.key, required this.targetLabel});

  final String targetLabel;

  @override
  ConsumerState<CollaborationShareDialog> createState() =>
      _CollaborationShareDialogState();
}

class _CollaborationShareDialogState
    extends ConsumerState<CollaborationShareDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on CollaborationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collaboration action failed.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value, String message) => _run(() async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  });

  Future<void> _createInvite() async {
    final email = TextEditingController();
    var role = CollaborationRole.editor;
    var validity = const Duration(days: 7);
    final invite = await showDialog<CollaborationInvite>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create email-bound invite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('collaboration-invite-email'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Recipient email'),
              ),
              DropdownButtonFormField<CollaborationRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: CollaborationRole.values
                    .where((value) => value != CollaborationRole.owner)
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => role = value ?? role),
              ),
              DropdownButtonFormField<Duration>(
                initialValue: validity,
                decoration: const InputDecoration(labelText: 'Validity'),
                items: const [
                  DropdownMenuItem(
                    value: Duration(days: 1),
                    child: Text('1 day'),
                  ),
                  DropdownMenuItem(
                    value: Duration(days: 3),
                    child: Text('3 days'),
                  ),
                  DropdownMenuItem(
                    value: Duration(days: 7),
                    child: Text('7 days'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => validity = value ?? validity),
              ),
              const SizedBox(height: 12),
              const Text('No email is sent. Share copied link manually.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('collaboration-create-invite'),
              onPressed: () async {
                try {
                  final created = await ref
                      .read(collaborationActionsProvider)
                      .createInvite(email.text, role, validity);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, created);
                  }
                } on CollaborationException catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    if (invite != null && mounted) {
      await _copy(invite.link, 'Invite link copied.');
    }
  }

  Future<void> _removeMember(CollaborationMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('${member.displayName} will lose access to this room.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(
        () => ref.read(collaborationActionsProvider).removeMember(member.uid),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collaborationProvider);
    final roomId = state.roomId;
    final isOwner = state.currentRole == CollaborationRole.owner;
    final roomLink = roomId == null
        ? null
        : 'var-collab://var.app/room/$roomId';
    return AlertDialog(
      key: const ValueKey('collaboration-share-dialog'),
      title: Text('Share ${widget.targetLabel}'),
      content: SizedBox(
        width: 520,
        child: roomId == null
            ? const Text('No active collaboration room.')
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Role: ${state.currentRole?.name ?? 'unknown'}'),
                    const SizedBox(height: 8),
                    SelectableText('Room ID: $roomId'),
                    const SizedBox(height: 8),
                    SelectableText(roomLink!),
                    const SizedBox(height: 8),
                    const Text(
                      'Room link works for existing members. New members need an email-bound invite.',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: const ValueKey('collaboration-copy-room-link'),
                          onPressed: _busy
                              ? null
                              : () => _copy(roomLink, 'Room link copied.'),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy link'),
                        ),
                        if (isOwner)
                          FilledButton.tonalIcon(
                            key: const ValueKey(
                              'collaboration-open-invite-dialog',
                            ),
                            onPressed: _busy ? null : _createInvite,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Create invite'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Members (${state.members.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final member in state.members)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(member.displayName),
                        subtitle: Text(member.email),
                        trailing:
                            !isOwner || member.role == CollaborationRole.owner
                            ? Text(member.role.name)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DropdownButton<CollaborationRole>(
                                    value: member.role,
                                    items: CollaborationRole.values
                                        .where(
                                          (role) =>
                                              role != CollaborationRole.owner,
                                        )
                                        .map(
                                          (role) => DropdownMenuItem(
                                            value: role,
                                            child: Text(role.name),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (role) {
                                            if (role != null) {
                                              _run(
                                                () => ref
                                                    .read(
                                                      collaborationActionsProvider,
                                                    )
                                                    .updateMemberRole(
                                                      member.uid,
                                                      role,
                                                    ),
                                              );
                                            }
                                          },
                                  ),
                                  IconButton(
                                    tooltip: 'Remove ${member.displayName}',
                                    onPressed: _busy
                                        ? null
                                        : () => _removeMember(member),
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        if (roomId != null)
          TextButton(
            key: const ValueKey('collaboration-leave-room'),
            onPressed: _busy
                ? null
                : () async {
                    await _run(
                      () => ref.read(collaborationActionsProvider).leaveRoom(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Leave room'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
