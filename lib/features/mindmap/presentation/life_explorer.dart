import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_design_tokens.dart';
import '../../../core/theme/node_visuals.dart';
import '../domain/mindmap_node.dart';

class LifeExplorer extends StatefulWidget {
  const LifeExplorer({
    required this.day,
    required this.nodes,
    required this.selectedNodeId,
    required this.onNodeSelected,
    required this.onCreateNode,
    required this.onCollapse,
    this.onNodeUpdated,
    this.onNodeDeleted,
    super.key,
  });

  final DateTime day;
  final List<MindmapNode> nodes;
  final String? selectedNodeId;
  final ValueChanged<MindmapNode> onNodeSelected;
  final ValueChanged<NodeType> onCreateNode;
  final VoidCallback onCollapse;
  final ValueChanged<MindmapNode>? onNodeUpdated;
  final ValueChanged<MindmapNode>? onNodeDeleted;

  @override
  State<LifeExplorer> createState() => _LifeExplorerState();
}

class _LifeExplorerState extends State<LifeExplorer> {
  final _searchController = TextEditingController();
  final Set<String> _expandedNodeIds = <String>{};
  String _query = '';
  NodeStatus? _statusFilter;
  String? _renamingNodeId;
  TextEditingController? _renameController;
  bool _showCreatePicker = false;
  String? _createCategory;

  @override
  void dispose() {
    _searchController.dispose();
    _renameController?.dispose();
    super.dispose();
  }

  void _startRename(MindmapNode node) {
    _renameController?.dispose();
    setState(() {
      _renamingNodeId = node.id;
      _renameController = TextEditingController(text: node.title);
    });
  }

  void _finishRename(MindmapNode node) {
    final title = _renameController?.text.trim() ?? '';
    if (title.isNotEmpty && title != node.title) {
      widget.onNodeUpdated?.call(
        node.copyWith(title: title, updatedAt: DateTime.now()),
      );
    }
    setState(() => _renamingNodeId = null);
  }

  Future<void> _showNodeMenu(MindmapNode node, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, 0),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Open / edit')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(
          value: 'pin',
          child: Text(node.isPinned ? 'Unpin' : 'Pin'),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(node.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'open') widget.onNodeSelected(node);
    if (action == 'rename') _startRename(node);
    if (action == 'pin') {
      final shouldPin = !node.isPinned;
      final now = DateTime.now();
      final nodesToUpdate = <MindmapNode>[node];
      if (shouldPin) {
        final ancestorIds = <String>{node.id};
        final pendingIds = <String>[node.id];
        while (pendingIds.isNotEmpty) {
          final childId = pendingIds.removeLast();
          for (final candidate in widget.nodes) {
            if (candidate.relatedNodeIds.contains(childId) &&
                ancestorIds.add(candidate.id)) {
              nodesToUpdate.add(candidate);
              pendingIds.add(candidate.id);
            }
          }
        }
      }
      for (final candidate in nodesToUpdate) {
        widget.onNodeUpdated?.call(
          candidate.copyWith(isPinned: shouldPin, updatedAt: now),
        );
      }
    }
    if (action == 'archive') {
      widget.onNodeUpdated?.call(
        node.copyWith(isArchived: !node.isArchived, updatedAt: DateTime.now()),
      );
    }
    if (action == 'delete') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete node?'),
              content: Text('Delete “${node.title}”? This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;
      if (confirmed) widget.onNodeDeleted?.call(node);
    }
  }

  Widget _buildTreeNode(
    BuildContext context,
    MindmapNode node,
    List<MindmapNode> activeNodes, {
    required int depth,
    required Set<String> ancestorIds,
  }) {
    final theme = Theme.of(context);
    final children = activeNodes
        .where(
          (candidate) =>
              node.relatedNodeIds.contains(candidate.id) &&
              !ancestorIds.contains(candidate.id),
        )
        .toList();
    final expanded = _expandedNodeIds.contains(node.id);
    final isRoot = depth == 0;
    final parentId = ancestorIds.isEmpty ? null : ancestorIds.last;

    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 22.0, bottom: 4),
      child: Column(
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu): () {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  _showNodeMenu(
                    node,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  );
                }
              },
              const SingleActivator(LogicalKeyboardKey.f10, shift: true): () {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  _showNodeMenu(
                    node,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  );
                }
              },
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) =>
                  _showNodeMenu(node, details.globalPosition),
              onLongPressStart: (details) =>
                  _showNodeMenu(node, details.globalPosition),
              child: ListTile(
                key: ValueKey(
                  isRoot
                      ? 'life-explorer-node-${node.id}'
                      : 'life-explorer-connection-$parentId-${node.id}',
                ),
                selected: node.id == widget.selectedNodeId,
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.of(context).radiusElement,
                  ),
                  side: BorderSide(
                    color: node.id == widget.selectedNodeId
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    width: node.id == widget.selectedNodeId ? 1.4 : 1,
                  ),
                ),
                leading: children.isEmpty
                    ? Icon(
                        NodeVisuals.icon(node.type),
                        color: NodeVisuals.color(context, node.type),
                        size: depth == 0 ? 20 : 17,
                      )
                    : IconButton(
                        key: ValueKey('life-explorer-expand-${node.id}'),
                        tooltip: expanded
                            ? 'Hide connected files'
                            : 'Show connected files',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          expanded
                              ? _expandedNodeIds.remove(node.id)
                              : _expandedNodeIds.add(node.id);
                        }),
                        icon: Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: NodeVisuals.color(context, node.type),
                          size: 20,
                        ),
                      ),
                title: _renamingNodeId == node.id
                    ? TextField(
                        key: ValueKey('life-explorer-rename-${node.id}'),
                        controller: _renameController,
                        autofocus: true,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        onSubmitted: (_) => _finishRename(node),
                        onTapOutside: (_) => _finishRename(node),
                      )
                    : Text(
                        node.title.trim().isEmpty
                            ? 'Untitled ${node.type.label}'
                            : node.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                subtitle: Text(
                  '${node.type.label} · ${DateFormat.Hm().format(node.createdAt)}'
                  '${children.isEmpty ? '' : ' · ${children.length} links'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isRoot ? null : const Icon(Icons.link, size: 15),
                onTap: () => widget.onNodeSelected(node),
              ),
            ),
          ),
          if (expanded)
            for (final child in children)
              Stack(
                key: ValueKey('life-explorer-guide-${node.id}-${child.id}'),
                children: [
                  Positioned(
                    left: (depth * 22) + 10,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1.5,
                      color: NodeVisuals.color(
                        context,
                        node.type,
                      ).withValues(alpha: 0.35),
                    ),
                  ),
                  Positioned(
                    left: (depth * 22) + 10,
                    top: 25,
                    child: Container(
                      width: 13,
                      height: 1.5,
                      color: NodeVisuals.color(
                        context,
                        node.type,
                      ).withValues(alpha: 0.35),
                    ),
                  ),
                  _buildTreeNode(
                    context,
                    child,
                    activeNodes,
                    depth: depth + 1,
                    ancestorIds: {...ancestorIds, node.id},
                  ),
                ],
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeNodes = widget.nodes.where((node) => !node.isArchived).toList();
    final connectedTargetIds = <String>{
      for (final node in activeNodes) ...node.relatedNodeIds,
    };
    final visibleNodes = activeNodes.where((node) {
      if (connectedTargetIds.contains(node.id)) return false;
      if (node.isArchived) return false;
      if (_statusFilter != null && node.status != _statusFilter) return false;
      if (_query.isEmpty) return true;
      final connectedNodes = activeNodes.where(
        (candidate) => node.relatedNodeIds.contains(candidate.id),
      );
      bool matches(MindmapNode candidate) =>
          candidate.title.toLowerCase().contains(_query) ||
          candidate.body.toLowerCase().contains(_query) ||
          candidate.type.label.toLowerCase().contains(_query) ||
          candidate.tags.any((tag) => tag.toLowerCase().contains(_query));
      return matches(node) || connectedNodes.any(matches);
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final pinnedNodes = visibleNodes.where((node) => node.isPinned).toList();
    final regularNodes = visibleNodes.where((node) => !node.isPinned).toList();

    return Material(
      key: const ValueKey('life-explorer'),
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'LIFE EXPLORER',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Minimize Life Explorer',
                    onPressed: widget.onCollapse,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                key: const ValueKey('life-explorer-search'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search this day...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  isDense: true,
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  for (final status in [
                    NodeStatus.inbox,
                    NodeStatus.next,
                    NodeStatus.someday,
                    NodeStatus.done,
                  ]) ...[
                    FilterChip(
                      key: ValueKey('explorer-status-${status.name}'),
                      label: Text(status.label),
                      selected: _statusFilter == status,
                      onSelected: (selected) {
                        setState(() {
                          _statusFilter = selected ? status : null;
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: InkWell(
                key: const ValueKey('life-explorer-new-file'),
                onTap: () => setState(() {
                  _showCreatePicker = !_showCreatePicker;
                  if (!_showCreatePicker) _createCategory = null;
                }),
                borderRadius: BorderRadius.circular(
                  AppDesignTokens.of(context).radiusElement,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.of(context).radiusElement,
                      ),
                      side: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.note_add_outlined, size: 19),
                      SizedBox(width: 8),
                      Text(
                        'New node file',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.grid_view_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ),
            if (_showCreatePicker)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _LifeExplorerNodeTypePicker(
                  selectedCategory: _createCategory,
                  onCategorySelected: (category) =>
                      setState(() => _createCategory = category),
                  onSelected: (type) {
                    setState(() {
                      _showCreatePicker = false;
                      _createCategory = null;
                    });
                    widget.onCreateNode(type);
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('EEE, MMM d').format(widget.day).toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Text(
                    '${visibleNodes.length} files',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visibleNodes.isEmpty
                  ? _ExplorerEmptyState(hasQuery: _query.isNotEmpty)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                      children: [
                        if (pinnedNodes.isNotEmpty) ...[
                          const _ExplorerSectionLabel(
                            icon: Icons.push_pin_outlined,
                            label: 'PINNED',
                          ),
                          for (final node in pinnedNodes)
                            _buildTreeNode(
                              context,
                              node,
                              activeNodes,
                              depth: 0,
                              ancestorIds: const <String>{},
                            ),
                          if (regularNodes.isNotEmpty)
                            const Divider(height: 20),
                        ],
                        if (regularNodes.isNotEmpty && pinnedNodes.isNotEmpty)
                          const _ExplorerSectionLabel(
                            icon: Icons.description_outlined,
                            label: 'FILES',
                          ),
                        for (final node in regularNodes)
                          _buildTreeNode(
                            context,
                            node,
                            activeNodes,
                            depth: 0,
                            ancestorIds: const <String>{},
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerSectionLabel extends StatelessWidget {
  const _ExplorerSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LifeExplorerNodeTypePicker extends StatefulWidget {
  const _LifeExplorerNodeTypePicker({
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.onSelected,
  });

  final String? selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<NodeType> onSelected;

  static const categories = <String, List<NodeType>>{
    'Action': [
      NodeType.task,
      NodeType.kanban,
      NodeType.plan,
      NodeType.checklist,
      NodeType.routine,
    ],
    'Thinking': [
      NodeType.note,
      NodeType.idea,
      NodeType.question,
      NodeType.decision,
      NodeType.quote,
    ],
    'Knowledge': [
      NodeType.resource,
      NodeType.bookmark,
      NodeType.link,
      NodeType.journal,
      NodeType.audio,
    ],
    'Life': [
      NodeType.habit,
      NodeType.goal,
      NodeType.event,
      NodeType.mood,
      NodeType.fit,
      NodeType.weather,
      NodeType.canvas,
    ],
    'People & Data': [
      NodeType.contact,
      NodeType.metric,
      NodeType.expense,
      NodeType.timer,
      NodeType.empty,
    ],
    'Media & Travel': [NodeType.itinerary, NodeType.image, NodeType.video],
  };

  @override
  State<_LifeExplorerNodeTypePicker> createState() =>
      _LifeExplorerNodeTypePickerState();
}

class _LifeExplorerNodeTypePickerState
    extends State<_LifeExplorerNodeTypePicker> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final query = _searchQuery.trim().toLowerCase();

    final List<NodeType> matchingTypes;
    if (hasSearch) {
      matchingTypes = NodeType.values.where((type) {
        return type.label.toLowerCase().contains(query) ||
            type.name.toLowerCase().contains(query);
      }).toList();
    } else {
      matchingTypes =
          _LifeExplorerNodeTypePicker.categories[widget.selectedCategory] ??
          const <NodeType>[];
    }

    return Container(
      key: const ValueKey('life-explorer-node-type-picker'),
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AppDesignTokens.of(context).radiusContainer,
          ),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const ValueKey('life-explorer-type-search-field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search type...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: hasSearch
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                if (!hasSearch) ...[
                  SizedBox(
                    width: 124,
                    child: ListView(
                      padding: const EdgeInsets.all(6),
                      children: [
                        for (final entry
                            in _LifeExplorerNodeTypePicker.categories.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              key: ValueKey(
                                'life-explorer-category-${entry.key}',
                              ),
                              onTap: () => widget.onCategorySelected(entry.key),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: widget.selectedCategory == entry.key
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.14,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${entry.value.length}',
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: theme.dividerColor),
                ],
                Expanded(
                  child: (!hasSearch && widget.selectedCategory == null)
                      ? Center(
                          child: Text(
                            'Choose category or search above',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : matchingTypes.isEmpty
                      ? Center(
                          child: Text(
                            'No types match "$_searchQuery"',
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          key: const ValueKey('life-explorer-node-type-grid'),
                          padding: const EdgeInsets.all(7),
                          itemCount: matchingTypes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 5),
                          itemBuilder: (context, index) {
                            final type = matchingTypes[index];
                            final color = NodeVisuals.color(context, type);
                            return InkWell(
                              key: ValueKey(
                                'life-explorer-create-${type.name}',
                              ),
                              onTap: () => widget.onSelected(type),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      NodeVisuals.icon(type),
                                      color: color,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        type.label,
                                        style: theme.textTheme.labelLarge,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerEmptyState extends StatelessWidget {
  const _ExplorerEmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          hasQuery
              ? 'No node files match this search.'
              : 'This canvas is quiet.\nCreate a node file to start.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
