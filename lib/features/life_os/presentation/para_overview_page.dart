/// PARA System (Projects, Areas, Resources, Archives) dashboard view.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../shared/widgets/error_message.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/mindmap_node.dart';

class ParaOverviewPage extends ConsumerStatefulWidget {
  const ParaOverviewPage({super.key});

  @override
  ConsumerState<ParaOverviewPage> createState() => _ParaOverviewPageState();
}

class _ParaOverviewPageState extends ConsumerState<ParaOverviewPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      body: nodesAsync.when(
        data: (nodes) {
          final activeNodes = nodes.where((n) => !n.isArchived).toList();
          final archivedNodes = nodes.where((n) => n.isArchived).toList();

          // Projects: Nodes with type plan/kanban or project non-empty
          final projects = activeNodes
              .where(
                (n) =>
                    n.type == NodeType.plan ||
                    n.type == NodeType.kanban ||
                    n.project.trim().isNotEmpty,
              )
              .toList();

          // Areas: Group by node.area
          final areasMap = <String, List<MindmapNode>>{};
          for (final n in activeNodes) {
            final areaKey = n.area.trim().isEmpty ? 'General' : n.area.trim();
            areasMap.putIfAbsent(areaKey, () => []).add(n);
          }

          // Resources: Nodes with type resource/link/bookmark/idea
          final resources = activeNodes
              .where(
                (n) =>
                    n.type == NodeType.resource ||
                    n.type == NodeType.link ||
                    n.type == NodeType.bookmark ||
                    n.type == NodeType.idea,
              )
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_special_rounded,
                      size: 28,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PARA System',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Projects, Areas, Resources, and Archives organizational hub.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    text: 'Projects (${projects.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.grid_view_outlined, size: 18),
                    text: 'Areas (${areasMap.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.bookmark_outline, size: 18),
                    text: 'Resources (${resources.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    text: 'Archives (${archivedNodes.length})',
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _NodeListGroup(
                      nodes: projects,
                      emptyMessage: 'No active projects found.',
                    ),
                    _AreasGroup(areasMap: areasMap),
                    _NodeListGroup(
                      nodes: resources,
                      emptyMessage: 'No saved resources or bookmarks.',
                    ),
                    _NodeListGroup(
                      nodes: archivedNodes,
                      emptyMessage: 'No archived items.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => ErrorMessage(
          message: 'Failed to load PARA system',
          onRetry: () => ref.invalidate(allMindmapNodesProvider),
        ),
      ),
    );
  }
}

class _AreasGroup extends StatelessWidget {
  const _AreasGroup({required this.areasMap});
  final Map<String, List<MindmapNode>> areasMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = areasMap.keys.toList()..sort();

    if (keys.isEmpty) {
      return const Center(child: Text('No areas defined.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final areaName = keys[index];
        final areaNodes = areasMap[areaName] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: Icon(
              Icons.domain_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              areaName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '${areaNodes.length} item(s)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            children: [
              for (final node in areaNodes.take(10))
                ListTile(
                  dense: true,
                  leading: Icon(
                    NodeVisuals.icon(node.type),
                    color: NodeVisuals.color(context, node.type),
                    size: 18,
                  ),
                  title: Text(node.title),
                  subtitle: Text(node.type.label),
                  trailing: const Icon(Icons.arrow_forward, size: 14),
                  onTap: () =>
                      goToDay(context, node.day, highlightNodeId: node.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _NodeListGroup extends StatelessWidget {
  const _NodeListGroup({required this.nodes, required this.emptyMessage});

  final List<MindmapNode> nodes;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (nodes.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              NodeVisuals.icon(node.type),
              color: NodeVisuals.color(context, node.type),
            ),
            title: Text(
              node.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${node.type.label} ${node.project.isNotEmpty ? '• ${node.project}' : ''}',
            ),
            trailing: const Icon(Icons.arrow_forward, size: 16),
            onTap: () => goToDay(context, node.day, highlightNodeId: node.id),
          ),
        );
      },
    );
  }
}
