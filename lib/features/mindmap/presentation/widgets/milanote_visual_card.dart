import 'package:flutter/material.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

Color _resolveCardColor(MindmapNode node, ThemeData theme) {
  final colorVal = node.data['color'] ?? node.data['card_color'];
  if (colorVal is int) return Color(colorVal);
  if (colorVal is String) {
    final hex = colorVal.replaceFirst('#', '');
    if (hex.length == 6) {
      final parsed = int.tryParse('FF$hex', radix: 16);
      if (parsed != null) return Color(parsed);
    } else if (hex.length == 8) {
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(parsed);
    }
  }
  return theme.colorScheme.surfaceContainerHighest;
}

const List<Color> _kMilanotePaletteColors = [
  Color(0xFFFFF9C4), // Light Yellow
  Color(0xFFFFECB3), // Amber
  Color(0xFFFFCCBC), // Light Peach
  Color(0xFFF8BBD0), // Soft Pink
  Color(0xFFE1BEE7), // Soft Purple
  Color(0xFFC5CAE9), // Indigo Tint
  Color(0xFFBBDEFB), // Soft Blue
  Color(0xFFB2DFDB), // Mint
  Color(0xFFDCEDC8), // Light Green
  Color(0xFFEEEEEE), // Neutral Grey
];

/// Milanote-style flexible visual card for Mindmap Canvas.
/// Supports image preview, inline editing, color header, sticky note style, and card actions.
class MilanoteVisualCard extends StatefulWidget {
  const MilanoteVisualCard({
    required this.node,
    this.onTap,
    this.onColorChange,
    this.onDelete,
    this.onUpdate,
    super.key,
  });

  final MindmapNode node;
  final VoidCallback? onTap;
  final ValueChanged<Color>? onColorChange;
  final VoidCallback? onDelete;
  final void Function(String title, String body)? onUpdate;

  @override
  State<MilanoteVisualCard> createState() => _MilanoteVisualCardState();
}

class _MilanoteVisualCardState extends State<MilanoteVisualCard> {
  bool _isEditingTitle = false;
  bool _isEditingBody = false;
  bool _showColorPicker = false;
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _bodyFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.node.title);
    _bodyController = TextEditingController(
      text: widget.node.data['caption'] as String? ?? widget.node.body,
    );
    _titleFocusNode.addListener(() {
      if (!_titleFocusNode.hasFocus && _isEditingTitle) {
        _saveChanges();
      }
    });
    _bodyFocusNode.addListener(() {
      if (!_bodyFocusNode.hasFocus && _isEditingBody) {
        _saveChanges();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MilanoteVisualCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.title != widget.node.title && !_isEditingTitle) {
      _titleController.text = widget.node.title;
    }
    final currentCaption =
        widget.node.data['caption'] as String? ?? widget.node.body;
    if ((oldWidget.node.data['caption'] as String? ?? oldWidget.node.body) !=
            currentCaption &&
        !_isEditingBody) {
      _bodyController.text = currentCaption;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _titleFocusNode.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _saveChanges() {
    setState(() {
      _isEditingTitle = false;
      _isEditingBody = false;
    });
    widget.onUpdate?.call(
      _titleController.text.trim(),
      _bodyController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = _resolveCardColor(widget.node, theme);
    final imageUrl =
        (widget.node.data['imageUrl'] ?? widget.node.data['image_url'])
            as String?;
    final isSticky =
        (widget.node.data['isSticky'] ?? widget.node.data['is_sticky'])
            as bool? ??
        false;
    final width = (widget.node.data['width'] as num?)?.toDouble() ?? 220.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top action bar (Milanote quick tools: color & options)
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 4, top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showColorPicker = !_showColorPicker;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
            ),
            if (_showColorPicker && widget.onColorChange != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final color in _kMilanotePaletteColors)
                      InkWell(
                        onTap: () {
                          widget.onColorChange?.call(color);
                          setState(() {
                            _showColorPicker = false;
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: theme.colorScheme.surfaceContainer,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(isSticky ? 12 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title: Click / Double-tap inline editor
                  if (_isEditingTitle)
                    TextField(
                      controller: _titleController,
                      focusNode: _titleFocusNode,
                      autofocus: true,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Card title...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _saveChanges(),
                    )
                  else
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _isEditingTitle = true);
                        _titleFocusNode.requestFocus();
                      },
                      child: Text(
                        _titleController.text.isEmpty
                            ? 'Untitled card'
                            : _titleController.text,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _titleController.text.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 6),
                  // Caption / Body: Click / Double-tap inline editor
                  if (_isEditingBody)
                    TextField(
                      controller: _bodyController,
                      focusNode: _bodyFocusNode,
                      autofocus: true,
                      maxLines: null,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Add note or description...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _saveChanges(),
                    )
                  else
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _isEditingBody = true);
                        _bodyFocusNode.requestFocus();
                      },
                      child: Text(
                        _bodyController.text.isEmpty
                            ? 'Add a note...'
                            : _bodyController.text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _bodyController.text.isEmpty
                              ? theme.colorScheme.outline
                              : theme.colorScheme.onSurfaceVariant,
                          fontStyle: _bodyController.text.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
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
