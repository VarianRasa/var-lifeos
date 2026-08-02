import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/core/theme/app_colors.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';

import '../../../core/theme/app_design_tokens.dart';

enum NodeShellSaveStatus { idle, saving, saved, error }

enum NodeResizePhase { preview, commit, cancel }

@immutable
class NodeResizeChange {
  const NodeResizeChange({
    required this.size,
    required this.positionDelta,
    required this.preset,
    required this.phase,
  });

  final Size size;
  final Offset positionDelta;
  final NodeSizePreset preset;
  final NodeResizePhase phase;
}

enum NodeResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

class NodeShell extends StatefulWidget {
  const NodeShell({
    required this.type,
    required this.size,
    required this.color,
    required this.isSelected,
    required this.preset,
    required this.child,
    this.saveStatus = NodeShellSaveStatus.idle,
    this.isCompact = false,
    this.onSelected,
    this.onHoverChanged,
    this.onResizeChanged,
    this.showPresetControl = true,
    super.key,
  });

  static const presetButtonKey = ValueKey<String>('node-shell-preset');
  static const accessibleResizeKey = ValueKey<String>(
    'node-shell-accessible-resize',
  );

  static ValueKey<String> resizeHandleKey(NodeResizeHandle handle) =>
      ValueKey<String>('node-shell-resize-${handle.name}');

  final NodeType type;
  final Size size;
  final Color color;
  final bool isSelected;
  final NodeSizePreset preset;
  final Widget child;
  final NodeShellSaveStatus saveStatus;
  final bool isCompact;
  final VoidCallback? onSelected;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<NodeResizeChange>? onResizeChanged;
  final bool showPresetControl;

  @override
  State<NodeShell> createState() => _NodeShellState();
}

class _NodeShellState extends State<NodeShell> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);
  Size? _previewSize;
  Size? _dragStartSize;
  Offset _sceneDragDelta = Offset.zero;
  NodeResizeHandle? _activeHandle;

  Size get _effectiveSize => _previewSize ?? widget.size;

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NodeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeHandle == null && oldWidget.size != widget.size) {
      _previewSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<AppSemanticColors>();
    final size = _effectiveSize;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Semantics(
        container: true,
        selected: widget.isSelected,
        label: '${widget.type.label} node',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSelected,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _NodeShellPainter(
                      color: widget.color,
                      surface: semantic?.card ?? theme.colorScheme.surface,
                      borderColor:
                          semantic?.border ?? theme.colorScheme.outlineVariant,
                      selected: widget.isSelected,
                      isCompact: widget.isCompact,
                    ),
                    child: ClipPath(
                      clipper: _NodeShellClipper(
                        AppDesignTokens.of(context).radiusContainer,
                      ),
                      child: SizedBox.expand(child: widget.child),
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _isHovered,
                  builder: (context, isHovered, child) =>
                      widget.isSelected || isHovered
                      ? _buildChrome()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChrome() {
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (widget.showPresetControl)
            PositionedDirectional(top: 6, end: 6, child: _buildPresetButton()),
          if (widget.saveStatus != NodeShellSaveStatus.idle)
            PositionedDirectional(
              start: 12,
              bottom: 8,
              child: _buildSaveStatus(),
            ),
          if (widget.onResizeChanged != null) ...[
            for (final handle in NodeResizeHandle.values) _buildHandle(handle),
            PositionedDirectional(
              end: 38,
              top: 6,
              child: Semantics(
                key: NodeShell.accessibleResizeKey,
                label: 'Node custom size',
                value:
                    '${_effectiveSize.width.round()} by ${_effectiveSize.height.round()}',
                increasedValue: 'Larger node',
                decreasedValue: 'Smaller node',
                onIncrease: () => _accessibleResize(24),
                onDecrease: () => _accessibleResize(-24),
                child: const SizedBox(width: 1, height: 1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered.value == value) return;
    _isHovered.value = value;
    widget.onHoverChanged?.call(value);
  }

  Widget _buildPresetButton() {
    return PopupMenuButton<NodeSizePreset>(
      key: NodeShell.presetButtonKey,
      tooltip: 'Node size preset: ${_presetLabel(widget.preset)}',
      onSelected: _applyPreset,
      itemBuilder: (context) => NodeSizePreset.values
          .where((preset) => preset != NodeSizePreset.custom)
          .map(
            (preset) => PopupMenuItem<NodeSizePreset>(
              value: preset,
              child: Text(_presetLabel(preset)),
            ),
          )
          .toList(),
      child: Semantics(
        button: true,
        label: 'Node size preset: ${_presetLabel(widget.preset)}',
        child: const _ChromeBox(child: Icon(Icons.aspect_ratio, size: 16)),
      ),
    );
  }

  void _applyPreset(NodeSizePreset preset) {
    final resolved = NodePresentationSpec.forType(
      widget.type,
    ).resolve(preset: preset);
    widget.onResizeChanged?.call(
      NodeResizeChange(
        size: Size(resolved.width, resolved.height),
        positionDelta: Offset.zero,
        preset: preset,
        phase: NodeResizePhase.commit,
      ),
    );
  }

  void _accessibleResize(double delta) {
    final spec = NodePresentationSpec.forType(widget.type);
    final resolved = spec.resolve(
      preset: NodeSizePreset.custom,
      customWidth: _effectiveSize.width + delta,
      customHeight: _effectiveSize.height + delta,
    );
    widget.onResizeChanged?.call(
      NodeResizeChange(
        size: Size(resolved.width, resolved.height),
        positionDelta: Offset.zero,
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.commit,
      ),
    );
  }

  Widget _buildSaveStatus() {
    final (IconData icon, String label) = switch (widget.saveStatus) {
      NodeShellSaveStatus.idle => (Icons.circle, ''),
      NodeShellSaveStatus.saving => (Icons.sync, 'Saving…'),
      NodeShellSaveStatus.saved => (Icons.check, 'Saved'),
      NodeShellSaveStatus.error => (Icons.error_outline, 'Save failed'),
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: widget.color),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _buildHandle(NodeResizeHandle handle) {
    final alignment = _alignmentFor(handle);
    return Align(
      alignment: alignment,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: NodeShell.resizeHandleKey(handle),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: (_) {
            _activeHandle = handle;
            _dragStartSize = widget.size;
            _sceneDragDelta = Offset.zero;
          },
          onPanUpdate: (details) => _previewResize(handle, details.delta),
          onPanEnd: (_) => _commitResize(handle),
          onPanCancel: _cancelResize,
          child: SizedBox.square(
            dimension: AppDesignTokens.of(context).minimumTarget,
            child: Center(
              child: Transform.translate(
                offset: Offset(alignment.x * 4, alignment.y * 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.of(context).radiusInner,
                    ),
                  ),
                  child: const SizedBox(width: 9, height: 9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _previewResize(NodeResizeHandle handle, Offset screenDelta) {
    if (!mounted) return;
    _sceneDragDelta += screenDelta;
    final start = _dragStartSize ?? widget.size;
    final left =
        handle == NodeResizeHandle.topLeft ||
        handle == NodeResizeHandle.bottomLeft;
    final top =
        handle == NodeResizeHandle.topLeft ||
        handle == NodeResizeHandle.topRight;
    final rawWidth =
        start.width + (left ? -_sceneDragDelta.dx : _sceneDragDelta.dx);
    final rawHeight =
        start.height + (top ? -_sceneDragDelta.dy : _sceneDragDelta.dy);
    final resolved = NodePresentationSpec.forType(widget.type).resolve(
      preset: NodeSizePreset.custom,
      customWidth: rawWidth,
      customHeight: rawHeight,
    );
    final size = Size(resolved.width, resolved.height);
    final positionDelta = Offset(
      left ? start.width - size.width : 0,
      top ? start.height - size.height : 0,
    );
    setState(() => _previewSize = size);
    widget.onResizeChanged?.call(
      NodeResizeChange(
        size: size,
        positionDelta: positionDelta,
        preset: NodeSizePreset.custom,
        phase: NodeResizePhase.preview,
      ),
    );
  }

  void _commitResize(NodeResizeHandle handle) {
    if (!mounted) return;
    final start = _dragStartSize;
    final size = _previewSize;
    if (start != null && size != null) {
      final left =
          handle == NodeResizeHandle.topLeft ||
          handle == NodeResizeHandle.bottomLeft;
      final top =
          handle == NodeResizeHandle.topLeft ||
          handle == NodeResizeHandle.topRight;
      widget.onResizeChanged?.call(
        NodeResizeChange(
          size: size,
          positionDelta: Offset(
            left ? start.width - size.width : 0,
            top ? start.height - size.height : 0,
          ),
          preset: NodeSizePreset.custom,
          phase: NodeResizePhase.commit,
        ),
      );
    }
    _activeHandle = null;
    _dragStartSize = null;
    _sceneDragDelta = Offset.zero;
  }

  void _cancelResize() {
    if (!mounted) return;
    if (_activeHandle != null) {
      widget.onResizeChanged?.call(
        NodeResizeChange(
          size: widget.size,
          positionDelta: Offset.zero,
          preset: widget.preset,
          phase: NodeResizePhase.cancel,
        ),
      );
    }
    setState(() => _previewSize = null);
    _activeHandle = null;
    _dragStartSize = null;
    _sceneDragDelta = Offset.zero;
  }
}

class _ChromeBox extends StatelessWidget {
  const _ChromeBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(
        AppDesignTokens.of(context).radiusElement,
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(5), child: child),
  );
}

Alignment _alignmentFor(NodeResizeHandle handle) => switch (handle) {
  NodeResizeHandle.topLeft => Alignment.topLeft,
  NodeResizeHandle.topRight => Alignment.topRight,
  NodeResizeHandle.bottomLeft => Alignment.bottomLeft,
  NodeResizeHandle.bottomRight => Alignment.bottomRight,
};

String _presetLabel(NodeSizePreset preset) => switch (preset) {
  NodeSizePreset.auto => 'Auto',
  NodeSizePreset.compact => 'Compact',
  NodeSizePreset.standard => 'Standard',
  NodeSizePreset.large => 'Large',
  NodeSizePreset.wide => 'Wide',
  NodeSizePreset.custom => 'Custom',
};

class _NodeShellPainter extends CustomPainter {
  const _NodeShellPainter({
    required this.color,
    required this.surface,
    required this.borderColor,
    required this.selected,
    required this.isCompact,
  });

  final Color color;
  final Color surface;
  final Color borderColor;
  final bool selected;
  final bool isCompact;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _roundedNodePath(size, AppDesignTokens.astryx.radiusContainer);
    canvas.drawPath(path, Paint()..color = surface);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : (isCompact ? 1 : 1.2)
        ..color = selected ? color : borderColor,
    );
    canvas.drawLine(
      const Offset(1.5, 8),
      Offset(1.5, size.height - 8),
      Paint()
        ..color = color
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _NodeShellPainter oldDelegate) =>
      color != oldDelegate.color ||
      surface != oldDelegate.surface ||
      borderColor != oldDelegate.borderColor ||
      selected != oldDelegate.selected ||
      isCompact != oldDelegate.isCompact;
}

class _NodeShellClipper extends CustomClipper<Path> {
  const _NodeShellClipper(this.radius);
  final double radius;

  @override
  Path getClip(Size size) => _roundedNodePath(size, radius);

  @override
  bool shouldReclip(covariant _NodeShellClipper oldClipper) =>
      radius != oldClipper.radius;
}

Path _roundedNodePath(Size size, double radius) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
  );
