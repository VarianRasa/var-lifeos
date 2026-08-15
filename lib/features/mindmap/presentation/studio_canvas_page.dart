import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../application/mindmap_providers.dart';
import '../domain/canvas_position.dart';
import '../domain/mindmap_node.dart';
import 'mindmap_canvas.dart';

/// Figma-style Creative Studio Workspace Page.
/// Replaces calendar/day-page with Document / Files & Canvas Pages hierarchy.
class StudioCanvasPage extends ConsumerStatefulWidget {
  const StudioCanvasPage({super.key, this.initialFileId, this.initialPageId});

  final String? initialFileId;
  final String? initialPageId;

  @override
  ConsumerState<StudioCanvasPage> createState() => _StudioCanvasPageState();
}

class _StudioCanvasPageState extends ConsumerState<StudioCanvasPage> {
  String _currentFileName = 'Untitled Creative Project';
  final List<String> _canvasPages = ['Page 1', 'Sketches & Ideas', 'Renders'];
  int _selectedPageIndex = 0;
  bool _showLeftPanel = true;
  bool _showRightPanel = true;
  int _leftTab = 0; // 0 = Layers, 1 = Assets

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final today = DateTime.now().dateOnly;
    final nodesAsync = ref.watch(allMindmapNodesProvider);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Column(
        children: [
          // Top Bar: Figma Style File Title, Pages Switcher, Collaboration & Actions
          _buildTopBar(context),

          // Main Workspace Area: Left Panel (Layers/Assets) + Central Infinite Canvas + Right Inspector Panel
          Expanded(
            child: Row(
              children: [
                // Left Panel: Layers & Components Tree
                if (_showLeftPanel)
                  _buildLeftSidebar(
                    context,
                    nodesAsync.value ?? const <MindmapNode>[],
                  ),

                // Central Infinite Canvas Viewport
                Expanded(
                  child: nodesAsync.when(
                    data: (List<MindmapNode> nodes) => MindmapCanvas(
                      nodes: nodes,
                      onNodeDropped: (NodeType type, Offset position) {
                        final newNode = MindmapNode.create(
                          id: 'node_${DateTime.now().microsecondsSinceEpoch}',
                          title: 'New ${type.label}',
                          type: type,
                          day: today,
                          position: CanvasPosition(position.dx, position.dy),
                        );
                        ref.read(mindmapRepositoryProvider).saveNode(newNode);
                        invalidateMindmapState(ref, day: today);
                      },
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object e, StackTrace st) =>
                        Center(child: Text('Failed to load canvas: $e')),
                  ),
                ),

                // Right Panel: Design & Properties Inspector
                if (_showRightPanel) _buildRightInspector(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Project / File Menu & Title
          Icon(Icons.dashboard_outlined, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentFileName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Rename File',
                    onPressed: () => _showRenameDialog(context),
                  ),
                  const SizedBox(width: 16),
                  // Pages dropdown / tabs
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButton<int>(
                      value: _selectedPageIndex,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      style: theme.textTheme.labelMedium,
                      items: [
                        for (var i = 0; i < _canvasPages.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(_canvasPages[i]),
                          ),
                      ],
                      onChanged: (idx) {
                        if (idx != null) {
                          setState(() => _selectedPageIndex = idx);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'New Page',
                    onPressed: () {
                      setState(() {
                        _canvasPages.add('Page ${_canvasPages.length + 1}');
                        _selectedPageIndex = _canvasPages.length - 1;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // Actions
          IconButton(
            icon: Icon(
              _showLeftPanel ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              size: 18,
            ),
            tooltip: 'Toggle Layers Panel',
            onPressed: () => setState(() => _showLeftPanel = !_showLeftPanel),
          ),
          IconButton(
            icon: Icon(
              _showRightPanel
                  ? Icons.space_dashboard
                  : Icons.space_dashboard_outlined,
              size: 18,
            ),
            tooltip: 'Toggle Properties Panel',
            onPressed: () => setState(() => _showRightPanel = !_showRightPanel),
          ),
          const VerticalDivider(indent: 10, endIndent: 10),
          FilledButton.icon(
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Share'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar(BuildContext context, List<MindmapNode> nodes) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _leftTab = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _leftTab == 0
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Layers',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: _leftTab == 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _leftTab = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _leftTab == 1
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      'Assets',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: _leftTab == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _leftTab == 0
                ? ListView.builder(
                    itemCount: nodes.length,
                    itemBuilder: (context, idx) {
                      final n = nodes[idx];
                      return ListTile(
                        dense: true,
                        leading: Icon(_getNodeIcon(n.type), size: 16),
                        title: Text(
                          n.title.isEmpty
                              ? 'Untitled ${n.type.label}'
                              : n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(
                        'Components & Presets',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 8),
                      const _AssetChip(
                        icon: Icons.crop_free,
                        label: 'Frame (Artboard)',
                      ),
                      const _AssetChip(
                        icon: Icons.sticky_note_2,
                        label: 'Milanote Card',
                      ),
                      const _AssetChip(
                        icon: Icons.brush,
                        label: 'Digital Sketch',
                      ),
                      const _AssetChip(
                        icon: Icons.auto_awesome_mosaic,
                        label: 'Gendo AI Studio',
                      ),
                      const _AssetChip(
                        icon: Icons.polyline,
                        label: 'Smart Connector',
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightInspector(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          left: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: ListView(
        children: [
          Text(
            'Design & Properties',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Transform',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: _PropertyField(label: 'X', value: '120'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PropertyField(label: 'Y', value: '340'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(
                child: _PropertyField(label: 'W', value: '280'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _PropertyField(label: 'H', value: '200'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          Text(
            'Style & Appearance',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Fill Color', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          Text(
            'Gendo AI Controls',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Render to Photoreal'),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  IconData _getNodeIcon(NodeType type) {
    return switch (type) {
      NodeType.note => Icons.sticky_note_2_outlined,
      NodeType.canvas => Icons.brush_outlined,
      NodeType.image => Icons.image_outlined,
      NodeType.task => Icons.check_circle_outline,
      NodeType.kanban => Icons.view_column_outlined,
      NodeType.link => Icons.link_outlined,
      NodeType.frame => Icons.crop_free_rounded,
      _ => Icons.widgets_outlined,
    };
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: _currentFileName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Project File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() => _currentFileName = controller.text.trim());
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

class _AssetChip extends StatelessWidget {
  const _AssetChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyField extends StatelessWidget {
  const _PropertyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
