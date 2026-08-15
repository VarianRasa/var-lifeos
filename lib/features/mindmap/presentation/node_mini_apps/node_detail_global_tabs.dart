import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/date_utils.dart';
import '../../../graph/domain/node_graph_explorer.dart';
import '../../../graph/presentation/graph_physics_canvas.dart';
import '../../application/mindmap_mutation_controller.dart';
import '../../application/mindmap_providers.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/mindmap_node_revision.dart';
import '../../domain/node_graph.dart';
import '../../domain/node_mini_app_data.dart';
import 'node_mini_app_common.dart';

class NodeRelationsTab extends ConsumerStatefulWidget {
  const NodeRelationsTab({
    required this.node,
    required this.onNodeSaved,
    this.prepareMutation,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onNodeSaved;
  final Future<MindmapNode> Function()? prepareMutation;

  @override
  ConsumerState<NodeRelationsTab> createState() => _NodeRelationsTabState();
}

class _NodeRelationsTabState extends ConsumerState<NodeRelationsTab> {
  String _query = '';
  String? _busyNodeId;
  Future<void> _mutationQueue = Future<void>.value();

  Future<MindmapNode> _sourceForMutation() async {
    return await widget.prepareMutation?.call() ?? widget.node;
  }

  Future<void> _link(MindmapNode target) => _enqueueMutation(
    target.id,
    errorLabel: 'link node',
    mutate: (source) => ref
        .read(mindmapMutationControllerProvider)
        .linkNodes(source: source, targetNodeId: target.id),
  );

  Future<void> _unlink(String targetNodeId) => _enqueueMutation(
    targetNodeId,
    errorLabel: 'unlink node',
    mutate: (source) => ref
        .read(mindmapMutationControllerProvider)
        .unlinkNodes(source: source, targetNodeId: targetNodeId),
  );

  Future<void> _toggleBlocker(MindmapNode target) => _enqueueMutation(
    target.id,
    errorLabel: 'update dependency',
    mutate: (source) {
      final isBlocker = source.blockedByNodeIds.contains(target.id);
      return ref
          .read(mindmapMutationControllerProvider)
          .saveNode(
            source.copyWith(
              blockedByNodeIds: isBlocker
                  ? <String>[
                      for (final id in source.blockedByNodeIds)
                        if (id != target.id) id,
                    ]
                  : <String>[...source.blockedByNodeIds, target.id],
              updatedAt: DateTime.now(),
            ),
          );
    },
  );

  Future<void> _enqueueMutation(
    String targetNodeId, {
    required String errorLabel,
    required Future<MindmapNode> Function(MindmapNode source) mutate,
  }) {
    setState(() => _busyNodeId = targetNodeId);
    final operation = _mutationQueue.then((_) async {
      try {
        final source = await _sourceForMutation();
        final saved = await mutate(source);
        widget.onNodeSaved(saved);
      } on Object catch (error) {
        if (mounted) _showError('Could not $errorLabel: $error');
      } finally {
        if (mounted && _busyNodeId == targetNodeId) {
          setState(() => _busyNodeId = null);
        }
      }
    });
    _mutationQueue = operation;
    return operation;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(MindmapNode target) {
    context.push('/calendar/${dayKey(target.day)}/node/${target.id}');
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(allMindmapNodesProvider);
    final relations = ref.watch(nodeRelationsProvider(widget.node.id));
    final graph = ref.watch(nodeGraphProvider);
    return nodes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load nodes: $error')),
      data: (allNodes) {
        final byId = <String, MindmapNode>{
          for (final node in allNodes) node.id: node,
        };
        final normalizedQuery = _query.trim().toLowerCase();
        final candidates = allNodes.where((candidate) {
          if (candidate.id == widget.node.id || candidate.isArchived) {
            return false;
          }
          if (normalizedQuery.isEmpty) return true;
          return candidate.title.toLowerCase().contains(normalizedQuery) ||
              candidate.type.label.toLowerCase().contains(normalizedQuery) ||
              candidate.tags.any((tag) => tag.contains(normalizedQuery));
        }).toList()..sort((left, right) => left.title.compareTo(right.title));

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MiniAppSection(
                      title: 'Neighborhood graph',
                      subtitle: 'Current node, outgoing links, and backlinks.',
                      icon: Icons.hub_outlined,
                      child: graph.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) =>
                            Text('Could not load graph: $error'),
                        data: (value) => _NodeNeighborhoodGraph(
                          graph: value,
                          nodeId: widget.node.id,
                          onOpen: (nodeId) {
                            final target = byId[nodeId];
                            if (target != null) _open(target);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    MiniAppSection(
                      title: 'Connected nodes',
                      subtitle: 'Open or remove direct graph relations.',
                      icon: Icons.hub_outlined,
                      child: widget.node.relatedNodeIds.isEmpty
                          ? const MiniAppEmptyState(
                              icon: Icons.link_off,
                              message: 'No direct relations yet.',
                            )
                          : Column(
                              children: [
                                for (final id in widget.node.relatedNodeIds)
                                  _RelationTile(
                                    node: byId[id],
                                    fallbackId: id,
                                    busy: _busyNodeId == id,
                                    onOpen: byId[id] == null
                                        ? null
                                        : () => _open(byId[id]!),
                                    onRemove: () => _unlink(id),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    MiniAppSection(
                      title: 'Backlinks',
                      subtitle: 'Nodes that link to or mention this node.',
                      icon: Icons.keyboard_return,
                      child: relations.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) =>
                            Text('Could not load backlinks: $error'),
                        data: (value) => value.backlinks.isEmpty
                            ? const MiniAppEmptyState(
                                icon: Icons.link_off,
                                message: 'No backlinks or mentions yet.',
                              )
                            : Column(
                                children: [
                                  for (final backlink in value.backlinks)
                                    ListTile(
                                      leading: const Icon(Icons.reply),
                                      title: Text(
                                        backlink.title.isEmpty
                                            ? 'Untitled ${backlink.type.label}'
                                            : backlink.title,
                                      ),
                                      subtitle: Text(
                                        '${backlink.type.label} · ${dayKey(backlink.day)}',
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _open(backlink),
                                    ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    MiniAppSection(
                      title: 'Blocked by',
                      subtitle: 'Incomplete blockers keep this node waiting.',
                      icon: Icons.account_tree_outlined,
                      child: widget.node.blockedByNodeIds.isEmpty
                          ? const MiniAppEmptyState(
                              icon: Icons.check_circle_outline,
                              message: 'No blocking dependencies.',
                            )
                          : Column(
                              children: [
                                for (final id in widget.node.blockedByNodeIds)
                                  _RelationTile(
                                    node: byId[id],
                                    fallbackId: id,
                                    busy: _busyNodeId == id,
                                    onOpen: byId[id] == null
                                        ? null
                                        : () => _open(byId[id]!),
                                    onRemove: byId[id] == null
                                        ? null
                                        : () => _toggleBlocker(byId[id]!),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    MiniAppSection(
                      title: 'Blocks',
                      subtitle: 'Nodes that wait for this node to finish.',
                      icon: Icons.call_split_outlined,
                      child: () {
                        final blocked =
                            allNodes
                                .where(
                                  (candidate) => candidate.blockedByNodeIds
                                      .contains(widget.node.id),
                                )
                                .toList()
                              ..sort(
                                (left, right) =>
                                    left.title.compareTo(right.title),
                              );
                        if (blocked.isEmpty) {
                          return const MiniAppEmptyState(
                            icon: Icons.check_circle_outline,
                            message: 'This node does not block another node.',
                          );
                        }
                        return Column(
                          children: [
                            for (final target in blocked)
                              ListTile(
                                leading: const Icon(Icons.call_split_outlined),
                                title: Text(
                                  target.title.isEmpty
                                      ? 'Untitled ${target.type.label}'
                                      : target.title,
                                ),
                                subtitle: Text(
                                  '${target.type.label} · ${dayKey(target.day)}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(target),
                              ),
                          ],
                        );
                      }(),
                    ),
                    const SizedBox(height: 16),
                    MiniAppSection(
                      title: 'Link another node',
                      subtitle: 'Search by title, type, or tag.',
                      icon: Icons.add_link,
                      child: Column(
                        children: [
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search nodes',
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                          const SizedBox(height: 12),
                          if (candidates.isEmpty)
                            const MiniAppEmptyState(
                              icon: Icons.search_off,
                              message: 'No matching nodes.',
                            )
                          else
                            for (final candidate in candidates.take(30))
                              ListTile(
                                leading: Icon(
                                  candidate.isDone
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                ),
                                title: Text(
                                  candidate.title.isEmpty
                                      ? 'Untitled ${candidate.type.label}'
                                      : candidate.title,
                                ),
                                subtitle: Text(candidate.type.label),
                                trailing: _busyNodeId == candidate.id
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Wrap(
                                        spacing: 4,
                                        children: [
                                          IconButton(
                                            tooltip:
                                                widget.node.relatedNodeIds
                                                    .contains(candidate.id)
                                                ? 'Already linked'
                                                : 'Link node',
                                            onPressed:
                                                widget.node.relatedNodeIds
                                                    .contains(candidate.id)
                                                ? null
                                                : () => _link(candidate),
                                            icon: const Icon(Icons.link),
                                          ),
                                          IconButton(
                                            tooltip:
                                                widget.node.blockedByNodeIds
                                                    .contains(candidate.id)
                                                ? 'Remove blocker'
                                                : 'Mark as blocker',
                                            onPressed: () =>
                                                _toggleBlocker(candidate),
                                            icon: Icon(
                                              widget.node.blockedByNodeIds
                                                      .contains(candidate.id)
                                                  ? Icons.remove_circle_outline
                                                  : Icons.account_tree_outlined,
                                            ),
                                          ),
                                        ],
                                      ),
                                onTap: () => _open(candidate),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NodeNeighborhoodGraph extends StatelessWidget {
  const _NodeNeighborhoodGraph({
    required this.graph,
    required this.nodeId,
    required this.onOpen,
  });

  final NodeGraph graph;
  final String nodeId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final view = NodeGraphExplorerView.fromGraph(
      graph,
      query: NodeGraphExplorerQuery(focusedNodeId: nodeId),
    );
    if (view.visibleEdges.isEmpty) {
      return const MiniAppEmptyState(
        icon: Icons.hub_outlined,
        message: 'Link another node to build this neighborhood.',
      );
    }
    final localGraph = NodeGraph(
      nodes: view.visibleNodes,
      edges: view.visibleEdges,
    );
    return Semantics(
      container: true,
      label:
          'Neighborhood graph, ${view.visibleNodes.length} nodes and ${view.visibleEdges.length} links',
      child: SizedBox(
        key: const ValueKey('node-relations-neighborhood-graph'),
        height: 340,
        child: GraphPhysicsCanvas(
          nodes: [for (final node in view.visibleNodes) node.node],
          graph: localGraph,
          onNodeTap: onOpen,
        ),
      ),
    );
  }
}

class NodeHistoryTab extends ConsumerStatefulWidget {
  const NodeHistoryTab({
    required this.node,
    required this.onRestored,
    this.prepareRestore,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onRestored;
  final Future<void> Function()? prepareRestore;

  @override
  ConsumerState<NodeHistoryTab> createState() => _NodeHistoryTabState();
}

class _NodeHistoryTabState extends ConsumerState<NodeHistoryTab> {
  String? _restoringId;

  Future<void> _restore(MindmapNodeRevision revision) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore revision ${revision.sequence}?'),
        content: const Text(
          'Current state remains available in version history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restoringId = revision.id);
    try {
      await widget.prepareRestore?.call();
      final restored = await ref
          .read(mindmapMutationControllerProvider)
          .restoreRevision(revision.id);
      widget.onRestored(restored);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _restoringId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final revisions = ref.watch(nodeRevisionsProvider(widget.node.id));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: MiniAppSection(
              title: 'Version history',
              subtitle: 'Every persisted edit creates a restorable revision.',
              icon: Icons.history,
              child: revisions.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Text('Could not load history: $error'),
                data: (items) {
                  if (items.isEmpty) {
                    return const MiniAppEmptyState(
                      icon: Icons.history_toggle_off,
                      message: 'No persisted revisions yet.',
                    );
                  }
                  return Column(
                    children: [
                      for (final revision in items)
                        _RevisionTile(
                          revision: revision,
                          current: widget.node,
                          restoring: _restoringId == revision.id,
                          onRestore: () => _restore(revision),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.node,
    required this.fallbackId,
    required this.busy,
    required this.onOpen,
    required this.onRemove,
  });

  final MindmapNode? node;
  final String fallbackId;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(node?.isDone ?? false ? Icons.check_circle : Icons.link),
    title: Text(node?.title.isNotEmpty == true ? node!.title : fallbackId),
    subtitle: node == null
        ? const Text('Linked node is unavailable')
        : Text('${node!.type.label} · ${dayKey(node!.day)}'),
    onTap: onOpen,
    trailing: busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
  );
}

class _RevisionTile extends StatelessWidget {
  const _RevisionTile({
    required this.revision,
    required this.current,
    required this.restoring,
    required this.onRestore,
  });

  final MindmapNodeRevision revision;
  final MindmapNode current;
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final changes = describeNodeChanges(current, revision.snapshot);
    return ExpansionTile(
      leading: CircleAvatar(child: Text('${revision.sequence}')),
      title: Text(
        revision.snapshot.title.isEmpty
            ? 'Untitled ${revision.snapshot.type.label}'
            : revision.snapshot.title,
      ),
      subtitle: Text(
        '${revision.kind.name} · ${revision.recordedAt.toLocal()}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: changes.isEmpty
                ? const <Widget>[Chip(label: Text('Matches current state'))]
                : <Widget>[
                    for (final change in changes) Chip(label: Text(change)),
                  ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: restoring ? null : onRestore,
            icon: restoring
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore),
            label: const Text('Restore this revision'),
          ),
        ),
      ],
    );
  }
}
