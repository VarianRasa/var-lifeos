import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/mindmap_providers.dart';
import '../../domain/mindmap_node.dart';

class WikiLinkAutocompleteTextField extends ConsumerStatefulWidget {
  const WikiLinkAutocompleteTextField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.maxLines = 5,
    this.minLines,
    this.expands = false,
    this.scrollController,
    this.inputFormatters,
    this.textAlignVertical,
    this.decoration,
    this.fieldKey,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final ScrollController? scrollController;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlignVertical? textAlignVertical;
  final InputDecoration? decoration;
  final Key? fieldKey;

  @override
  ConsumerState<WikiLinkAutocompleteTextField> createState() =>
      _WikiLinkAutocompleteTextFieldState();
}

class _WikiLinkAutocompleteTextFieldState
    extends ConsumerState<WikiLinkAutocompleteTextField> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  String _filterQuery = '';
  int _triggerIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (!selection.isValid || selection.isCollapsed == false) {
      _removeOverlay();
      return;
    }

    final cursor = selection.baseOffset;
    final textBeforeCursor = text.substring(0, cursor);
    final lastOpenBrackets = textBeforeCursor.lastIndexOf('[[');

    if (lastOpenBrackets != -1) {
      final textAfterBrackets = textBeforeCursor.substring(
        lastOpenBrackets + 2,
      );
      if (!textAfterBrackets.contains(']]') &&
          !textAfterBrackets.contains('\n')) {
        _triggerIndex = lastOpenBrackets;
        _filterQuery = textAfterBrackets.toLowerCase();
        _showOrUpdateOverlay();
        return;
      }
    }

    _removeOverlay();
  }

  void _showOrUpdateOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _insertLink(MindmapNode targetNode) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final cursor = selection.baseOffset;

    final beforeTrigger = text.substring(0, _triggerIndex);
    final afterCursor = text.substring(cursor);

    final inserted = '[[${targetNode.title}]]';
    final newText = '$beforeTrigger$inserted$afterCursor';
    final newCursor = _triggerIndex + inserted.length;

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    widget.onChanged(newText);
    _removeOverlay();
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final nodesAsync = ref.watch(allMindmapNodesProvider);
          final theme = Theme.of(context);

          return Positioned(
            width: 280,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 48),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHigh,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: nodesAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (nodes) {
                      final matches = nodes
                          .where((n) {
                            if (n.isArchived) return false;
                            if (_filterQuery.isEmpty) return true;
                            return n.title.toLowerCase().contains(_filterQuery);
                          })
                          .take(6)
                          .toList();

                      if (matches.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('No matching nodes'),
                        );
                      }

                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final node = matches[index];
                          return ListTile(
                            dense: true,
                            title: Text(node.title, maxLines: 1),
                            subtitle: Text(node.type.name),
                            onTap: () => _insertLink(node),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        expands: widget.expands,
        scrollController: widget.scrollController,
        inputFormatters: widget.inputFormatters,
        textAlignVertical: widget.textAlignVertical,
        decoration: widget.decoration,
        onChanged: widget.onChanged,
      ),
    );
  }
}
