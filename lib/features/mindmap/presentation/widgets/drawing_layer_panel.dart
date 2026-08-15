import 'package:flutter/material.dart';
import '../../domain/canvas_drawing_layer.dart';

const List<String> _kLayerBlendModes = [
  'srcOver',
  'multiply',
  'screen',
  'overlay',
  'darken',
  'lighten',
  'colorDodge',
  'colorBurn',
];

/// Panel for managing drawing layers in the canvas drawing studio.
class DrawingLayerPanel extends StatelessWidget {
  const DrawingLayerPanel({
    super.key,
    required this.manager,
    required this.onAddLayer,
    required this.onRemoveLayer,
    required this.onSelectLayer,
    required this.onToggleVisibility,
    required this.onToggleLock,
    required this.onOpacityChanged,
    this.onBlendModeChanged,
  });

  final DrawingLayerManager manager;
  final VoidCallback onAddLayer;
  final ValueChanged<String> onRemoveLayer;
  final ValueChanged<String> onSelectLayer;
  final ValueChanged<String> onToggleVisibility;
  final ValueChanged<String> onToggleLock;
  final void Function(String layerId, double opacity) onOpacityChanged;
  final void Function(String layerId, String blendMode)? onBlendModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      constraints: const BoxConstraints(maxHeight: 380),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Layers',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                key: const Key('add-layer-button'),
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Add Layer',
                onPressed: onAddLayer,
              ),
            ],
          ),
          const Divider(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: manager.layers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                // Reverse display so topmost layer is on top of list
                final layer = manager.layers[manager.layers.length - 1 - index];
                final isActive = layer.id == manager.activeLayerId;

                return InkWell(
                  key: Key('layer-item-${layer.id}'),
                  onTap: () => onSelectLayer(layer.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isActive
                          ? Border.all(color: colorScheme.primary, width: 1.5)
                          : Border.all(color: Colors.transparent),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              key: Key('toggle-visibility-${layer.id}'),
                              icon: Icon(
                                layer.isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: layer.isVisible
                                  ? 'Hide Layer'
                                  : 'Show Layer',
                              onPressed: () => onToggleVisibility(layer.id),
                            ),
                            IconButton(
                              key: Key('toggle-lock-${layer.id}'),
                              icon: Icon(
                                layer.isLocked ? Icons.lock : Icons.lock_open,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: layer.isLocked
                                  ? 'Unlock Layer'
                                  : 'Lock Layer',
                              onPressed: () => onToggleLock(layer.id),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                layer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (manager.layers.length > 1)
                              IconButton(
                                key: Key('delete-layer-${layer.id}'),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                tooltip: 'Delete Layer',
                                onPressed: () => onRemoveLayer(layer.id),
                              ),
                          ],
                        ),
                        if (isActive) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Text(
                                  'Opacity',
                                  style: TextStyle(fontSize: 10),
                                ),
                                Expanded(
                                  child: Slider(
                                    key: Key(
                                      'layer-opacity-slider-${layer.id}',
                                    ),
                                    value: layer.opacity.clamp(0.0, 1.0),
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 20,
                                    onChanged: (val) =>
                                        onOpacityChanged(layer.id, val),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Text(
                                  'Blend',
                                  style: TextStyle(fontSize: 10),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<String>(
                                    value:
                                        _kLayerBlendModes.contains(
                                          layer.blendMode,
                                        )
                                        ? layer.blendMode
                                        : 'srcOver',
                                    isDense: true,
                                    isExpanded: true,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                    ),
                                    underline: const SizedBox.shrink(),
                                    items: _kLayerBlendModes.map((mode) {
                                      return DropdownMenuItem(
                                        value: mode,
                                        child: Text(mode),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        onBlendModeChanged?.call(layer.id, val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
