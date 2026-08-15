import 'package:flutter/material.dart';
import '../../domain/canvas_drawing_layer.dart';

/// Floating/dockable brush palette bar for selecting brush type, size, opacity, and quick color.
class BrushPaletteBar extends StatelessWidget {
  const BrushPaletteBar({
    super.key,
    required this.selectedBrush,
    required this.brushSize,
    required this.brushOpacity,
    required this.selectedColor,
    required this.onBrushChanged,
    required this.onSizeChanged,
    required this.onOpacityChanged,
    required this.onColorChanged,
    this.onClose,
    this.colorSwatches = defaultSwatches,
  });

  final CanvasBrushType selectedBrush;
  final double brushSize;
  final double brushOpacity;
  final Color selectedColor;
  final ValueChanged<CanvasBrushType> onBrushChanged;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onClose;
  final List<Color> colorSwatches;

  static const List<Color> defaultSwatches = <Color>[
    Colors.black,
    Colors.white,
    Colors.redAccent,
    Colors.orangeAccent,
    Colors.amber,
    Colors.greenAccent,
    Colors.lightBlueAccent,
    Colors.purpleAccent,
  ];

  IconData _getBrushIcon(CanvasBrushType type) {
    return switch (type) {
      CanvasBrushType.pencil => Icons.edit_outlined,
      CanvasBrushType.pen => Icons.brush,
      CanvasBrushType.marker => Icons.border_color,
      CanvasBrushType.highlighter => Icons.highlight,
      CanvasBrushType.airbrush => Icons.blur_on,
      CanvasBrushType.ink => Icons.gesture,
      CanvasBrushType.charcoal => Icons.grain,
      CanvasBrushType.eraser => Icons.auto_fix_normal,
    };
  }

  String _getBrushLabel(CanvasBrushType type) {
    return switch (type) {
      CanvasBrushType.pencil => 'Pencil',
      CanvasBrushType.pen => 'Pen',
      CanvasBrushType.marker => 'Marker',
      CanvasBrushType.highlighter => 'Highlighter',
      CanvasBrushType.airbrush => 'Airbrush',
      CanvasBrushType.ink => 'Ink',
      CanvasBrushType.charcoal => 'Charcoal',
      CanvasBrushType.eraser => 'Eraser',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brush type selectors
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: CanvasBrushType.values
                        .map((brush) {
                          final isSelected = brush == selectedBrush;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Tooltip(
                              message: _getBrushLabel(brush),
                              child: ChoiceChip(
                                showCheckmark: false,
                                avatar: Icon(
                                  _getBrushIcon(brush),
                                  size: 16,
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                label: Text(
                                  _getBrushLabel(brush),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: colorScheme.primary,
                                onSelected: (_) => onBrushChanged(brush),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('brush-palette-done-button'),
                  icon: const Icon(Icons.check, size: 18),
                  tooltip: 'Done Drawing / Exit',
                  onPressed: onClose,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Size and Opacity controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.line_weight, size: 16),
              const SizedBox(width: 4),
              SizedBox(
                width: 100,
                child: Slider(
                  value: brushSize.clamp(1.0, 50.0),
                  min: 1.0,
                  max: 50.0,
                  divisions: 49,
                  label: '${brushSize.round()}px',
                  onChanged: onSizeChanged,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.opacity, size: 16),
              const SizedBox(width: 4),
              SizedBox(
                width: 100,
                child: Slider(
                  value: brushOpacity.clamp(0.05, 1.0),
                  min: 0.05,
                  max: 1.0,
                  divisions: 19,
                  label: '${(brushOpacity * 100).round()}%',
                  onChanged: onOpacityChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Quick color swatches
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: colorSwatches
                  .map((color) {
                    final isSelected =
                        selectedColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => onColorChanged(color),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                size: 14,
                                color: color.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}
