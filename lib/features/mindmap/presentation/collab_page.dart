import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/date_utils.dart';
import '../../../shared/layout/adaptive_scaffold.dart';
import '../../../shared/widgets/doodle_border.dart';
import '../application/collaboration_controller.dart';

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
    final cleanId = CollaborationNotifier.cleanRoomId(roomText);
    if (cleanId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Room ID or Link cannot be empty'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecting to room: $cleanId...'),
        duration: const Duration(seconds: 1),
      ),
    );

    // Use initialDayKey from deep link if available, fallback to today
    final targetDayKey = widget.initialDayKey ?? dayKey(DateTime.now());
    final success = await ref
        .read(collaborationProvider.notifier)
        .joinRoom(cleanId, dayKey: targetDayKey);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully joined room: $cleanId!'),
          backgroundColor: Colors.green,
        ),
      );
      // Navigate straight to the canvas page for the targeted day
      context.go('/calendar/$targetDayKey');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to join room. Check internet or platform support.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleCreateNew() async {
    // Generate a fresh random room ID
    final newId = const Uuid().v4().substring(0, 8);
    await _handleJoin(newId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collabState = ref.watch(collaborationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppRouteChromeTabs(currentRoute: AppRoute.collab),
      ),
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
                    shape: DoodleShapeBorder(
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
                        'Work synchronously with your team on the day mindmap canvas.',
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
                      shape: DoodleShapeBorder(
                        side: BorderSide(
                          color: Colors.green.withValues(alpha: 0.8),
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
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Connected to Room',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
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
                        const SizedBox(height: 16),
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
                                  foregroundColor: Colors.redAccent,
                                  shape: const DoodleShapeBorder(
                                    side: BorderSide(
                                      color: Colors.redAccent,
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
                    shape: DoodleShapeBorder(
                      side: BorderSide(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
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
                          border: DoodleInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              width: 1.5,
                            ),
                          ),
                          enabledBorder: DoodleInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: DoodleInputBorder(
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
                                shape: const DoodleShapeBorder(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _isLoading
                                  ? null
                                  : () => _handleJoin(_inputController.text),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
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
                          shape: const DoodleShapeBorder(
                            side: BorderSide(width: 1.5),
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
                      shape: DoodleShapeBorder(
                        side: BorderSide(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.2,
                          ),
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
