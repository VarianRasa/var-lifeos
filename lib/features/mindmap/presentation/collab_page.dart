import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../application/collaboration_controller.dart';
import '../application/node_comment_controller.dart';
import '../domain/collaboration_board_sync.dart';
import '../domain/collaboration_node_sync.dart';
import '../domain/collaboration_room.dart';
import 'collaboration_share_dialog.dart';
import 'node_comments_panel.dart';
import 'node_revision_history_dialog.dart';

class CollabPage extends ConsumerStatefulWidget {
  const CollabPage({super.key, this.initialRoomId, this.initialDayKey});
  final String? initialRoomId;
  final String? initialDayKey;

  @override
  ConsumerState<CollabPage> createState() => _CollabPageState();
}

class _CollabPageState extends ConsumerState<CollabPage> {
  final _inputController = TextEditingController();
  bool _isLoading = false;
  final Set<String> _resolvingConflicts = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomId != null) {
      _inputController.text = widget.initialRoomId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleJoin(widget.initialRoomId!);
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin(String roomText) async {
    final invite = CollaborationInviteLink.tryParse(roomText);
    final cleanId =
        invite?.roomId ?? CollaborationNotifier.cleanRoomId(roomText);
    if (cleanId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a valid room or invite link.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final actions = ref.read(collaborationActionsProvider);
      if (invite != null) {
        await actions.acceptInvite(roomText);
      } else {
        await actions.openRoomChecked(
          cleanId,
          expectedTarget: widget.initialDayKey == null
              ? null
              : CollaborationTarget.day(widget.initialDayKey!),
        );
      }
      if (!mounted) return;
      final theme = Theme.of(context);
      final successColor =
          theme.extension<AppSemanticColors>()?.success ??
          theme.colorScheme.primary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully joined room: $cleanId!'),
          backgroundColor: successColor,
        ),
      );
    } on CollaborationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCreateNew() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(collaborationProvider.notifier).createRoom(DateTime.now());
    } on CollaborationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resolveConflict(
    CollaborationNodeConflict conflict, {
    required bool keepRemote,
  }) async {
    if (keepRemote) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep remote version?'),
          content: const Text(
            'Local pending changes for this node will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep remote'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _resolvingConflicts.add(conflict.localNodeId));
    try {
      await ref
          .read(collaborationProvider.notifier)
          .resolveConflict(conflict, keepRemote: keepRemote);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _resolvingConflicts.remove(conflict.localNodeId));
      }
    }
  }

  Future<void> _resolveBoardConflict(
    CollaborationBoardConflict conflict, {
    required bool keepRemote,
  }) async {
    if (keepRemote) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Keep remote board?'),
          content: const Text('Local pending board changes will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep remote'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _resolvingConflicts.add(conflict.boardId));
    try {
      await ref
          .read(collaborationProvider.notifier)
          .resolveBoardConflict(conflict, keepRemote: keepRemote);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _resolvingConflicts.remove(conflict.boardId));
    }
  }

  Future<void> _showInviteDialog() async {
    final email = TextEditingController();
    var role = CollaborationRole.editor;
    var validity = const Duration(days: 7);
    final invite = await showDialog<CollaborationInvite>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create invite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Recipient email'),
              ),
              DropdownButtonFormField<CollaborationRole>(
                initialValue: role,
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
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              DropdownButtonFormField<Duration>(
                initialValue: validity,
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
                decoration: const InputDecoration(labelText: 'Validity'),
              ),
              const SizedBox(height: 12),
              const Text('No email is sent. Share copied link manually.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final value = await ref
                      .read(collaborationProvider.notifier)
                      .createInvite(email.text, role, validity);
                  if (context.mounted) Navigator.pop(context, value);
                } on CollaborationException catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
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
    if (invite == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: invite.link));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite copied: ${invite.link}')));
    }
  }

  Future<void> _showComments(String roomId) async {
    final bindings = await ref.read(boundRoomNodesProvider(roomId).future);
    if (!mounted) return;
    if (bindings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No room nodes are bound on this device.'),
        ),
      );
      return;
    }
    final binding = await showDialog<CollaborationNodeBinding>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose node comments'),
        children: [
          for (final item in bindings)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Text(item.localNodeId),
            ),
        ],
      ),
    );
    if (binding == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 600,
          height: 600,
          child: Column(
            children: [
              AppBar(
                title: const Text('Node comments'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    tooltip: 'Close comments',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: NodeCommentsPanel(
                  roomId: roomId,
                  localNodeId: binding.localNodeId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory(String roomId) async {
    final bindings = await ref.read(boundRoomNodesProvider(roomId).future);
    if (!mounted) return;
    if (bindings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No room nodes are bound on this device.'),
        ),
      );
      return;
    }
    final binding = await showDialog<CollaborationNodeBinding>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose node history'),
        children: [
          for (final item in bindings)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Text(item.localNodeId),
            ),
        ],
      ),
    );
    if (binding == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          NodeRevisionHistoryDialog(nodeId: binding.localNodeId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();
    final tokens = AppDesignTokens.of(context);
    final success = semantic?.success ?? theme.colorScheme.primary;
    final collabState = ref.watch(collaborationProvider);
    final conflicts = collabState.roomId == null
        ? null
        : ref.watch(collaborationConflictsProvider(collabState.roomId!));
    final boardConflicts = collabState.roomId == null
        ? null
        : ref.watch(collaborationBoardConflictsProvider(collabState.roomId!));
    final outbox = collabState.roomId == null
        ? null
        : ref.watch(collaborationOutboxProvider(collabState.roomId!));

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        tokens.radiusContainer,
                      ),
                      side: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Real-time Collaboration',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Work synchronously with your team on day and project canvases.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Active room state card
                if (collabState.roomId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: ShapeDecoration(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          tokens.radiusContainer,
                        ),
                        side: BorderSide(
                          color: success.withValues(alpha: 0.8),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Connected to Room',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          'Room ID: ${collabState.roomId}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Share Link:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  'var-collab://var.app/room/${collabState.roomId}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy link',
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        'var-collab://var.app/room/${collabState.roomId}',
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Room link copied to clipboard!',
                                    ),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        if (collabState.currentRole == CollaborationRole.owner)
                          FilledButton.icon(
                            onPressed: _showInviteDialog,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Create invite'),
                          ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          key: const ValueKey('collaboration-manage-sharing'),
                          onPressed: () => showCollaborationShareDialog(
                            context,
                            targetLabel:
                                collabState.roomTarget?.label ?? 'room',
                          ),
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Manage sharing'),
                        ),
                        if (collabState.roomTarget?.kind ==
                            CollaborationTargetKind.day) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    _showComments(collabState.roomId!),
                                icon: const Icon(Icons.comment_outlined),
                                label: const Text('Open comments'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    _showHistory(collabState.roomId!),
                                icon: const Icon(Icons.history),
                                label: const Text('Open history'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (outbox != null)
                          outbox.when(
                            data: (summary) => Align(
                              alignment: Alignment.centerLeft,
                              child: ActionChip(
                                avatar: Icon(
                                  summary.total == 0
                                      ? Icons.cloud_done_outlined
                                      : Icons.cloud_upload_outlined,
                                ),
                                label: Text(
                                  summary.total == 0
                                      ? 'Synced'
                                      : '${summary.total} in outbox'
                                            '${summary.retrying > 0 ? ' · ${summary.retrying} retrying' : ''}'
                                            '${summary.blocked > 0 ? ' · ${summary.blocked} blocked' : ''}'
                                            '${summary.failed > 0 ? ' · ${summary.failed} failed' : ''}',
                                ),
                                onPressed:
                                    summary.blocked > 0 || summary.retrying > 0
                                    ? () => ref
                                          .read(collaborationProvider.notifier)
                                          .retryOutboxNow()
                                    : null,
                              ),
                            ),
                            error: (error, _) => Text(
                              error.toString(),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            loading: () => const SizedBox.shrink(),
                          ),
                        if (conflicts != null)
                          conflicts.when(
                            data: (items) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (items.isNotEmpty)
                                  Text(
                                    'Conflicts (${items.length})',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                for (final conflict in items)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            conflict
                                                        .remoteEnvelope
                                                        ?.payload?['title']
                                                    as String? ??
                                                conflict.localNodeId,
                                            style: theme.textTheme.titleSmall,
                                          ),
                                          Text(
                                            'Local base r${conflict.localBaseRevision} · Remote r${conflict.remoteRevision}',
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            children: [
                                              FilledButton.tonal(
                                                onPressed:
                                                    _resolvingConflicts
                                                        .contains(
                                                          conflict.localNodeId,
                                                        )
                                                    ? null
                                                    : () => _resolveConflict(
                                                        conflict,
                                                        keepRemote: false,
                                                      ),
                                                child: const Text('Keep mine'),
                                              ),
                                              OutlinedButton(
                                                onPressed:
                                                    _resolvingConflicts
                                                        .contains(
                                                          conflict.localNodeId,
                                                        )
                                                    ? null
                                                    : () => _resolveConflict(
                                                        conflict,
                                                        keepRemote: true,
                                                      ),
                                                child: const Text(
                                                  'Keep remote',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            error: (error, _) => Text(
                              error.toString(),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        if (boardConflicts != null)
                          boardConflicts.when(
                            data: (items) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (items.isNotEmpty)
                                  Text(
                                    'Board conflicts (${items.length})',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                for (final conflict in items)
                                  Card(
                                    child: ListTile(
                                      title: Text(conflict.boardId),
                                      subtitle: Text(
                                        'Local base r${conflict.localBaseRevision} · Remote r${conflict.remoteRevision}',
                                      ),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          FilledButton.tonal(
                                            key: ValueKey(
                                              'board-conflict-keep-mine-${conflict.boardId}',
                                            ),
                                            onPressed:
                                                _resolvingConflicts.contains(
                                                  conflict.boardId,
                                                )
                                                ? null
                                                : () => _resolveBoardConflict(
                                                    conflict,
                                                    keepRemote: false,
                                                  ),
                                            child: const Text('Keep mine'),
                                          ),
                                          OutlinedButton(
                                            key: ValueKey(
                                              'board-conflict-keep-remote-${conflict.boardId}',
                                            ),
                                            onPressed:
                                                _resolvingConflicts.contains(
                                                  conflict.boardId,
                                                )
                                                ? null
                                                : () => _resolveBoardConflict(
                                                    conflict,
                                                    keepRemote: true,
                                                  ),
                                            child: const Text('Keep remote'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            error: (error, _) => Text(
                              error.toString(),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            loading: () => const SizedBox.shrink(),
                          ),
                        if (collabState.members.isNotEmpty) ...[
                          Text(
                            'Members (${collabState.members.length})',
                            style: theme.textTheme.titleSmall,
                          ),
                          for (final member in collabState.members)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(member.displayName),
                              subtitle: Text(member.email),
                              trailing:
                                  member.role == CollaborationRole.owner ||
                                      collabState.currentRole !=
                                          CollaborationRole.owner
                                  ? Text(member.role.name)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        DropdownButton<CollaborationRole>(
                                          value: member.role,
                                          items: CollaborationRole.values
                                              .where(
                                                (role) =>
                                                    role !=
                                                    CollaborationRole.owner,
                                              )
                                              .map(
                                                (role) => DropdownMenuItem(
                                                  value: role,
                                                  child: Text(role.name),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (role) {
                                            if (role != null) {
                                              ref
                                                  .read(
                                                    collaborationProvider
                                                        .notifier,
                                                  )
                                                  .updateMemberRole(
                                                    member.uid,
                                                    role,
                                                  );
                                            }
                                          },
                                        ),
                                        IconButton(
                                          onPressed: () => ref
                                              .read(
                                                collaborationProvider.notifier,
                                              )
                                              .removeMember(member.uid),
                                          icon: const Icon(
                                            Icons.person_remove_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (collabState.collaborators.isNotEmpty) ...[
                          Text(
                            'Active Peers (${collabState.collaborators.length}):',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: collabState.collaborators.values.map((
                              peer,
                            ) {
                              return Chip(
                                avatar: CircleAvatar(
                                  backgroundColor: peer.color,
                                  child: Text(
                                    peer.name.isNotEmpty
                                        ? peer.name[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                label: Text(peer.name),
                                backgroundColor: theme.colorScheme.surface,
                                side: BorderSide(color: peer.color, width: 1.5),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      tokens.radiusContainer,
                                    ),
                                    side: BorderSide(
                                      color: theme.colorScheme.error,
                                      width: 1.5,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await ref
                                      .read(collaborationProvider.notifier)
                                      .leaveRoom();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Disconnected from room'),
                                    ),
                                  );
                                },
                                child: const Text('Leave Collab Session'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Action form card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        tokens.radiusContainer,
                      ),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Join or Create Session',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: 'Enter Room ID or Collab Link...',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusElement,
                            ),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outline,
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusElement,
                            ),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outline,
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusElement,
                            ),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        onSubmitted: _isLoading ? null : _handleJoin,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusContainer,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () => _handleJoin(_inputController.text),
                              child: _isLoading
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    )
                                  : const Text(
                                      'Join Room',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              tokens.radiusContainer,
                            ),
                            side: const BorderSide(width: 1.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isLoading ? null : _handleCreateNew,
                        child: const Text(
                          'Create New Collab Room',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // History section
                if (collabState.roomHistory.isNotEmpty) ...[
                  Text(
                    'Recent Rooms',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: ShapeDecoration(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          tokens.radiusContainer,
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: collabState.roomHistory.length,
                      separatorBuilder: (context, index) => Divider(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.1,
                        ),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final room = collabState.roomHistory[index];
                        return ListTile(
                          title: Text(
                            room,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                          ),
                          onTap: _isLoading ? null : () => _handleJoin(room),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
