import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/canvas_block_document.dart';
import '../../domain/node_type_payloads.dart';
import 'canvas_document_renderer.dart';

class CanvasNodeEditor extends StatefulWidget {
  const CanvasNodeEditor({
    required this.payload,
    required this.onChanged,
    this.onOpenCanvas,
    super.key,
  });

  final CanvasPayload payload;
  final ValueChanged<CanvasPayload> onChanged;
  final VoidCallback? onOpenCanvas;

  @override
  State<CanvasNodeEditor> createState() => _CanvasNodeEditorState();
}

class _CanvasNodeEditorState extends State<CanvasNodeEditor> {
  static const int _historyLimit = 50;
  static const int _historyByteLimit = maxDrawingSerializedPayloadBytes;

  late CanvasPayload _payload;
  final List<CanvasPayload> _undo = <CanvasPayload>[];
  final List<CanvasPayload> _redo = <CanvasPayload>[];
  CanvasElement? _draftElement;
  CanvasPayload? _gestureBase;
  Offset? _gestureStart;
  String? _movingElementId;
  String? _selectedElementId;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _blockScrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _blockScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _payload = widget.payload;
  }

  @override
  void didUpdateWidget(covariant CanvasNodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draftElement != null || _gestureBase != null) return;
    if (_samePayload(_payload, widget.payload)) return;
    setState(() {
      _payload = widget.payload;
      if (!_payload.elements.any((item) => item.id == _selectedElementId)) {
        _selectedElementId = null;
      }
    });
  }

  bool _samePayload(CanvasPayload left, CanvasPayload right) =>
      jsonEncode(left.toData(const <String, Object?>{})) ==
      jsonEncode(right.toData(const <String, Object?>{}));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _toolbar(context),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final split =
              _payload.viewMode == 'split' && constraints.maxWidth >= 800;
          final visual =
              _payload.viewMode == 'visual' ||
              (_payload.viewMode == 'split' && constraints.maxWidth < 800);
          if (split) {
            return SizedBox(
              height: 620,
              child: Row(
                children: [
                  Expanded(child: _visualWorkspace(context)),
                  const SizedBox(width: 8),
                  Expanded(child: _blockEditor(context)),
                ],
              ),
            );
          }
          return visual ? _visualWorkspace(context) : _blockEditor(context);
        },
      ),
      const SizedBox(height: 8),
      Text(
        '${_payload.elements.length} elements · ${_payload.drawingCount} drawings · ${_payload.textCount} text · ${_payload.shapeCount} shapes',
        key: const ValueKey<String>('knowledge-canvas-element-summary'),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );

  Widget _visualWorkspace(BuildContext context) => Container(
    key: const ValueKey<String>('knowledge-canvas-workspace'),
    height: 620,
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPanStart(details.localPosition, size),
          onPanUpdate: (details) =>
              _onPanUpdate(details.localPosition, details.delta, size),
          onPanEnd: (_) => _onPanEnd(size),
          onTapUp: (details) => _onTap(details.localPosition, size),
          child: CanvasDocumentView(
            payload: _payload,
            selectedElementId: _selectedElementId,
            draftElement: _draftElement,
          ),
        );
      },
    ),
  );

  Widget _blockEditor(BuildContext context) {
    final visible = _payload.blocks.blocks.indexed
        .where((entry) => entry.$2.text.toLowerCase().contains(_query))
        .toList(growable: false);
    final headings = _payload.blocks.blocks.indexed
        .where((entry) => entry.$2.type == CanvasBlockType.heading)
        .toList(growable: false);
    return Container(
      key: const ValueKey<String>('knowledge-canvas-blocks'),
      height: 440,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: TextField(
              key: const ValueKey<String>('knowledge-canvas-block-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search blocks',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
          ),
          if (headings.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final heading in headings)
                    TextButton(
                      onPressed: () => _scrollToBlock(heading.$1),
                      child: Text(heading.$2.text),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('knowledge-canvas-block-add'),
              onPressed: () => _addBlock(CanvasBlockType.paragraph),
              icon: const Icon(Icons.add),
              label: const Text('Add block'),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _blockScrollController,
              itemCount: visible.length,
              onReorderItem: _query.isEmpty
                  ? (oldIndex, newIndex) => _reorderBlock(
                      oldIndex,
                      newIndex > oldIndex ? newIndex + 1 : newIndex,
                    )
                  : (_, _) {},
              itemBuilder: (context, visibleIndex) {
                final entry = visible[visibleIndex];
                return _blockTile(entry.$2, entry.$1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockTile(CanvasBlock block, int index) => Semantics(
    key: ValueKey<String>('canvas-block-${block.id}'),
    label: '${_label(block.type.name)} block ${index + 1}',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              if (block.type == CanvasBlockType.checklist)
                Checkbox(
                  value: block.checked,
                  semanticLabel: 'Toggle checklist block ${index + 1}',
                  onChanged: (value) => _replaceBlock(
                    index,
                    block.copyWith(checked: value ?? false),
                  ),
                )
              else
                const Icon(Icons.drag_handle),
              Expanded(child: _blockContent(block, index)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DropdownButton<CanvasBlockType>(
                value: block.type,
                onChanged: (value) {
                  if (value != null) {
                    _replaceBlock(index, block.copyWith(type: value));
                  }
                },
                items: [
                  for (final type in CanvasBlockType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_label(type.name)),
                    ),
                ],
              ),
              IconButton(
                tooltip: 'Delete block',
                onPressed: () => _deleteBlock(index),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _blockContent(CanvasBlock block, int index) {
    if (block.type == CanvasBlockType.divider) {
      return const Divider();
    }
    if (block.type == CanvasBlockType.image ||
        block.type == CanvasBlockType.file) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                block.type == CanvasBlockType.image
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  block.fileName.isNotEmpty
                      ? block.fileName
                      : (block.attachmentId.isNotEmpty
                            ? 'Attachment ${block.attachmentId.substring(0, math.min(8, block.attachmentId.length))}'
                            : 'No media attached'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey<String>('canvas-block-attachment-${block.id}'),
            initialValue: block.attachmentId,
            decoration: const InputDecoration(
              labelText: 'Attachment ID',
              isDense: true,
            ),
            onChanged: (value) => _replaceBlock(
              index,
              block.copyWith(
                attachmentId: value.trim(),
                fileName: block.fileName.isEmpty && value.isNotEmpty
                    ? 'file-${value.substring(0, math.min(6, value.length))}'
                    : block.fileName,
              ),
            ),
          ),
        ],
      );
    }
    if (block.type == CanvasBlockType.urlPreview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: ValueKey<String>('canvas-block-url-${block.id}'),
            initialValue: block.url,
            decoration: const InputDecoration(
              labelText: 'URL',
              prefixIcon: Icon(Icons.link),
              isDense: true,
            ),
            onChanged: (value) =>
                _replaceBlock(index, block.copyWith(url: value.trim())),
          ),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey<String>('canvas-block-urltitle-${block.id}'),
            initialValue: block.urlTitle,
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              isDense: true,
            ),
            onChanged: (value) =>
                _replaceBlock(index, block.copyWith(urlTitle: value.trim())),
          ),
        ],
      );
    }
    if (block.type == CanvasBlockType.table) {
      final rows = block.tableRows.isEmpty
          ? const <List<String>>[
              <String>['', ''],
              <String>['', ''],
            ]
          : block.tableRows;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              children: [
                for (var r = 0; r < rows.length; r++)
                  TableRow(
                    children: [
                      for (var c = 0; c < rows[r].length; c++)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: SizedBox(
                            width: 90,
                            child: TextFormField(
                              key: ValueKey<String>(
                                'canvas-block-cell-${block.id}-$r-$c',
                              ),
                              initialValue: rows[r][c],
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onChanged: (value) {
                                final nextRows = rows
                                    .map((row) => List<String>.of(row))
                                    .toList();
                                nextRows[r][c] = value;
                                _replaceBlock(
                                  index,
                                  block.copyWith(tableRows: nextRows),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () {
                  final colCount = rows.firstOrNull?.length ?? 2;
                  final nextRows = [
                    ...rows.map((row) => List<String>.of(row)),
                    List<String>.filled(colCount, ''),
                  ];
                  _replaceBlock(index, block.copyWith(tableRows: nextRows));
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Row'),
              ),
              TextButton.icon(
                onPressed: () {
                  final nextRows = rows.map((row) => [...row, '']).toList();
                  _replaceBlock(index, block.copyWith(tableRows: nextRows));
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Column'),
              ),
            ],
          ),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _toggleChecklist(index),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
          shift: true,
        ): () =>
            _moveBlock(index, -1),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
          shift: true,
        ): () =>
            _moveBlock(index, 1),
      },
      child: TextFormField(
        key: ValueKey<String>('canvas-block-text-${block.id}'),
        initialValue: block.text,
        decoration: InputDecoration(
          hintText:
              _query.isNotEmpty && block.text.toLowerCase().contains(_query)
              ? 'Match: $_query'
              : null,
        ),
        maxLines: block.type == CanvasBlockType.code ? 5 : null,
        onChanged: (value) => _changeBlockText(index, value),
        onFieldSubmitted: (_) => _insertBlockAfter(index),
      ),
    );
  }

  Widget _toolbar(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        children: [
          for (final mode in const <String>['visual', 'blocks', 'split'])
            ChoiceChip(
              key: ValueKey<String>('knowledge-canvas-mode-$mode'),
              selected: _payload.viewMode == mode,
              label: Text(_label(mode)),
              onSelected: (_) =>
                  _setSettings(_payload.copyWith(viewMode: mode)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tool in canvasTools)
            ChoiceChip(
              key: ValueKey<String>('knowledge-canvas-tool-$tool'),
              selected: _payload.activeTool == tool,
              label: Text(_label(tool)),
              avatar: Icon(_toolIcon(tool), size: 17),
              onSelected: (_) =>
                  _setSettings(_payload.copyWith(activeTool: tool)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final color in canvasColorTokens)
            ChoiceChip(
              key: ValueKey<String>('knowledge-canvas-color-$color'),
              selected: _payload.penColor == color,
              label: Text(_label(color)),
              onSelected: (_) =>
                  _setSettings(_payload.copyWith(penColor: color)),
            ),
          SizedBox(
            width: 180,
            child: Column(
              children: [
                Text('Width ${_payload.penWidth.toStringAsFixed(1)}'),
                Slider(
                  key: const ValueKey<String>('knowledge-canvas-width-slider'),
                  value: _payload.penWidth.clamp(1, 12),
                  min: 1,
                  max: 12,
                  onChanged: (value) =>
                      _setSettings(_payload.copyWith(penWidth: value)),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final background in canvasBackgrounds)
            ChoiceChip(
              key: ValueKey<String>('knowledge-canvas-background-$background'),
              selected: _payload.background == background,
              label: Text(_label(background)),
              onSelected: (_) =>
                  _commit(_payload.copyWith(background: background)),
            ),
          IconButton(
            key: const ValueKey<String>('knowledge-canvas-undo'),
            tooltip: 'Undo',
            onPressed: _undo.isEmpty ? null : _undoChange,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            key: const ValueKey<String>('knowledge-canvas-redo'),
            tooltip: 'Redo',
            onPressed: _redo.isEmpty ? null : _redoChange,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            key: const ValueKey<String>('knowledge-canvas-delete-selected'),
            tooltip: 'Delete selected',
            onPressed: _selectedElementId == null ? null : _deleteSelected,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          IconButton(
            key: const ValueKey<String>('knowledge-canvas-clear'),
            tooltip: 'Clear canvas',
            onPressed: _payload.elements.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('knowledge-canvas-open-action'),
            onPressed: widget.onOpenCanvas,
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('Open canvas'),
          ),
        ],
      ),
    ],
  );

  void _setSettings(CanvasPayload next) {
    setState(() => _payload = next);
    widget.onChanged(next);
  }

  void _addBlock(CanvasBlockType type) {
    _insertBlockAfter(_payload.blocks.blocks.length - 1, type: type);
  }

  void _insertBlockAfter(
    int index, {
    CanvasBlockType type = CanvasBlockType.paragraph,
  }) {
    final blocks = List<CanvasBlock>.of(_payload.blocks.blocks);
    blocks.insert(index + 1, CanvasBlock(id: _nextBlockId(), type: type));
    _commit(
      _payload.copyWith(blocks: _payload.blocks.copyWith(blocks: blocks)),
    );
  }

  void _changeBlockText(int index, String value) {
    const commands = <String, CanvasBlockType>{
      '/text': CanvasBlockType.paragraph,
      '/heading': CanvasBlockType.heading,
      '/todo': CanvasBlockType.checklist,
      '/bullet': CanvasBlockType.bulletedList,
      '/number': CanvasBlockType.numberedList,
      '/quote': CanvasBlockType.quote,
      '/code': CanvasBlockType.code,
      '/divider': CanvasBlockType.divider,
      '/image': CanvasBlockType.image,
      '/file': CanvasBlockType.file,
      '/url': CanvasBlockType.urlPreview,
      '/table': CanvasBlockType.table,
    };
    final block = _payload.blocks.blocks[index];
    final command = commands[value];
    _replaceBlock(
      index,
      block.copyWith(
        type: command ?? block.type,
        text: command == null ? value : '',
      ),
    );
  }

  void _toggleChecklist(int index) {
    final block = _payload.blocks.blocks[index];
    if (block.type == CanvasBlockType.checklist) {
      _replaceBlock(index, block.copyWith(checked: !block.checked));
    }
  }

  void _moveBlock(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _payload.blocks.blocks.length) return;
    final blocks = List<CanvasBlock>.of(_payload.blocks.blocks);
    blocks.insert(target, blocks.removeAt(index));
    _commit(
      _payload.copyWith(blocks: _payload.blocks.copyWith(blocks: blocks)),
    );
  }

  void _scrollToBlock(int index) {
    if (!_blockScrollController.hasClients) return;
    _blockScrollController.animateTo(
      (index * 112).toDouble().clamp(
        0,
        _blockScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _replaceBlock(int index, CanvasBlock block) {
    _setSettings(
      _payload.copyWith(
        blocks: _payload.blocks.copyWith(
          blocks: <CanvasBlock>[
            for (final entry in _payload.blocks.blocks.indexed)
              entry.$1 == index ? block : entry.$2,
          ],
        ),
      ),
    );
  }

  void _deleteBlock(int index) {
    _commit(
      _payload.copyWith(
        blocks: _payload.blocks.copyWith(
          blocks: <CanvasBlock>[
            for (final entry in _payload.blocks.blocks.indexed)
              if (entry.$1 != index) entry.$2,
          ],
        ),
      ),
    );
  }

  void _reorderBlock(int oldIndex, int newIndex) {
    final blocks = List<CanvasBlock>.of(_payload.blocks.blocks);
    if (newIndex > oldIndex) newIndex--;
    blocks.insert(newIndex, blocks.removeAt(oldIndex));
    _commit(
      _payload.copyWith(blocks: _payload.blocks.copyWith(blocks: blocks)),
    );
  }

  String _nextBlockId() {
    final ids = _payload.blocks.blocks.map((block) => block.id).toSet();
    var index = ids.length + 1;
    while (ids.contains('block-$index')) {
      index++;
    }
    return 'block-$index';
  }

  void _onPanStart(Offset point, Size size) {
    final normalized = offsetToCanvasPoint(point, size);
    _gestureStart = point;
    _gestureBase = _payload;
    switch (_payload.activeTool) {
      case 'pen':
        setState(() {
          _draftElement = CanvasStroke(
            id: _nextId('stroke'),
            color: _payload.penColor,
            width: _payload.penWidth,
            points: <CanvasPoint>[normalized],
          );
        });
      case 'rectangle' || 'ellipse':
        setState(() {
          _draftElement = CanvasShapeElement(
            id: _nextId('shape'),
            color: _payload.penColor,
            shape: _payload.activeTool,
            start: normalized,
            end: normalized,
            width: _payload.penWidth,
          );
        });
      case 'arrow':
        setState(() {
          _draftElement = CanvasArrowElement(
            id: _nextId('arrow'),
            color: _payload.penColor,
            start: normalized,
            end: normalized,
            width: _payload.penWidth,
          );
        });
      case 'eraser':
        final hit = hitTestCanvasElement(_payload.elements, point, size);
        if (hit != null) {
          _commit(
            _payload.copyWith(
              elements: _payload.elements
                  .where((item) => item.id != hit.id)
                  .toList(growable: false),
            ),
          );
        }
        _gestureBase = null;
      case 'select':
        final hit = hitTestCanvasElement(_payload.elements, point, size);
        setState(() {
          _selectedElementId = hit?.id;
          _movingElementId = hit?.id;
        });
      default:
        _gestureBase = null;
    }
  }

  void _onPanUpdate(Offset point, Offset delta, Size size) {
    final normalized = offsetToCanvasPoint(point, size);
    switch (_draftElement) {
      case CanvasStroke(:final points) when _payload.activeTool == 'pen':
        final existingPoints = _payload.elements
            .whereType<CanvasStroke>()
            .fold<int>(0, (total, stroke) => total + stroke.points.length);
        if (points.length >= maxDrawingPointsPerItem ||
            existingPoints + points.length >= maxDrawingPointsTotal ||
            points.isNotEmpty &&
                (canvasPointToOffset(points.last, size) - point).distance <
                    1.5) {
          return;
        }
        setState(() {
          _draftElement = (_draftElement! as CanvasStroke).copyWith(
            points: <CanvasPoint>[...points, normalized],
          );
        });
      case CanvasShapeElement()
          when _payload.activeTool == 'rectangle' ||
              _payload.activeTool == 'ellipse':
        setState(() {
          _draftElement = (_draftElement! as CanvasShapeElement).copyWith(
            end: normalized,
          );
        });
      case CanvasArrowElement() when _payload.activeTool == 'arrow':
        setState(() {
          _draftElement = (_draftElement! as CanvasArrowElement).copyWith(
            end: normalized,
          );
        });
      default:
        if (_payload.activeTool != 'select' ||
            _movingElementId == null ||
            _gestureBase == null ||
            _gestureStart == null) {
          return;
        }
        final source = _gestureBase!.elements
            .where((item) => item.id == _movingElementId)
            .firstOrNull;
        if (source == null) return;
        final moved = moveCanvasElement(source, point - _gestureStart!, size);
        final next = _gestureBase!.copyWith(
          elements: <CanvasElement>[
            for (final element in _gestureBase!.elements)
              element.id == moved.id ? moved : element,
          ],
        );
        setState(() => _payload = next);
    }
  }

  void _onPanEnd(Size size) {
    final draft = _draftElement;
    if (draft != null) {
      final valid = switch (draft) {
        CanvasStroke() => draft.points.length >= 2,
        CanvasShapeElement() =>
          (canvasPointToOffset(draft.end, size) -
                      canvasPointToOffset(draft.start, size))
                  .distance >=
              6,
        CanvasArrowElement() =>
          (canvasPointToOffset(draft.end, size) -
                      canvasPointToOffset(draft.start, size))
                  .distance >=
              6,
        _ => false,
      };
      if (valid) {
        _commit(
          _payload.copyWith(
            elements: <CanvasElement>[..._payload.elements, draft],
          ),
          base: _gestureBase,
        );
      }
    } else if (_payload.activeTool == 'select' &&
        _gestureBase != null &&
        !_samePayload(_gestureBase!, _payload)) {
      _pushUndo(_gestureBase!);
      _redo.clear();
      _trimHistory();
      widget.onChanged(_payload);
    }
    setState(() {
      _draftElement = null;
      _gestureBase = null;
      _gestureStart = null;
      _movingElementId = null;
    });
  }

  Future<void> _onTap(Offset point, Size size) async {
    if (_payload.activeTool != 'text' && _payload.activeTool != 'sticky') {
      return;
    }
    final hit = hitTestCanvasElement(_payload.elements, point, size);
    if (hit is CanvasTextElement || hit is CanvasStickyElement) {
      await _showTextDialog(
        position: offsetToCanvasPoint(point, size),
        existing: hit,
      );
      return;
    }
    await _showTextDialog(position: offsetToCanvasPoint(point, size));
  }

  Future<void> _showTextDialog({
    required CanvasPoint position,
    CanvasElement? existing,
  }) async {
    final initial = switch (existing) {
      CanvasTextElement() => existing.text,
      CanvasStickyElement() => existing.text,
      _ => '',
    };
    var draftText = initial;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add text' : 'Edit text'),
        content: TextFormField(
          key: const ValueKey<String>('knowledge-canvas-text-dialog-field'),
          initialValue: initial,
          onChanged: (value) => draftText = value,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('knowledge-canvas-text-dialog-save'),
            onPressed: () => Navigator.of(context).pop(draftText.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) return;
    final element = switch (existing) {
      CanvasTextElement() => existing.copyWith(text: value),
      CanvasStickyElement() => existing.copyWith(text: value),
      _ when _payload.activeTool == 'sticky' => CanvasStickyElement(
        id: _nextId('sticky'),
        color: 'neutral',
        position: position,
        text: value,
        backgroundColor: _payload.penColor,
      ),
      _ => CanvasTextElement(
        id: _nextId('text'),
        color: _payload.penColor,
        position: position,
        text: value,
      ),
    };
    _commit(
      _payload.copyWith(
        elements: existing == null
            ? <CanvasElement>[..._payload.elements, element]
            : <CanvasElement>[
                for (final item in _payload.elements)
                  item.id == element.id ? element : item,
              ],
      ),
    );
  }

  void _deleteSelected() {
    final selected = _selectedElementId;
    if (selected == null) return;
    _commit(
      _payload.copyWith(
        elements: _payload.elements
            .where((item) => item.id != selected)
            .toList(growable: false),
      ),
    );
    setState(() => _selectedElementId = null);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear canvas?'),
        content: const Text('This removes every element from this canvas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('knowledge-canvas-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _commit(_payload.copyWith(elements: const <CanvasElement>[]));
    setState(() => _selectedElementId = null);
  }

  void _commit(CanvasPayload next, {CanvasPayload? base}) {
    final previous = base ?? _payload;
    if (_samePayload(previous, next)) return;
    _pushUndo(previous);
    _redo.clear();
    setState(() => _payload = next);
    widget.onChanged(next);
  }

  void _pushUndo(CanvasPayload payload) {
    _undo.add(payload);
    _trimHistory();
  }

  int _payloadBytes(CanvasPayload payload) =>
      utf8.encode(jsonEncode(payload.toData(const <String, Object?>{}))).length;

  void _trimHistory() {
    while (_undo.length + _redo.length > _historyLimit) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
    var bytes = <CanvasPayload>[
      ..._undo,
      ..._redo,
    ].fold<int>(0, (total, payload) => total + _payloadBytes(payload));
    while (bytes > _historyByteLimit && _undo.length + _redo.length > 1) {
      final removed = _undo.isNotEmpty ? _undo.removeAt(0) : _redo.removeAt(0);
      bytes -= _payloadBytes(removed);
    }
  }

  void _undoChange() {
    if (_undo.isEmpty) return;
    final previous = _undo.removeLast();
    _redo.add(_payload);
    _trimHistory();
    setState(() => _payload = previous);
    widget.onChanged(previous);
  }

  void _redoChange() {
    if (_redo.isEmpty) return;
    final next = _redo.removeLast();
    _pushUndo(_payload);
    setState(() => _payload = next);
    widget.onChanged(next);
  }

  String _nextId(String prefix) {
    final ids = _payload.elements.map((item) => item.id).toSet();
    var index = ids.length + 1;
    while (ids.contains('$prefix-$index')) {
      index++;
    }
    return '$prefix-$index';
  }
}

String _label(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

IconData _toolIcon(String tool) => switch (tool) {
  'pen' => Icons.edit_rounded,
  'eraser' => Icons.auto_fix_normal_rounded,
  'text' => Icons.text_fields_rounded,
  'sticky' => Icons.sticky_note_2_outlined,
  'rectangle' => Icons.rectangle_outlined,
  'ellipse' => Icons.circle_outlined,
  'arrow' => Icons.arrow_forward_rounded,
  _ => Icons.near_me_outlined,
};
