import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';

final class NoteNodeEditor extends StatefulWidget {
  const NoteNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    required this.onNodeChanged,
    this.onAttachmentAdd,
    this.onAttachmentOpen,
    this.onAttachmentRemove,
    this.validationErrors = const <String>[],
    super.key,
  });

  final MindmapNode node;
  final NotePayload payload;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<NotePayload> onPayloadChanged;
  final ValueChanged<MindmapNode> onNodeChanged;
  final Future<TaskAttachmentReference?> Function()? onAttachmentAdd;
  final Future<void> Function(TaskAttachmentReference attachment)?
  onAttachmentOpen;
  final Future<void> Function(TaskAttachmentReference attachment)?
  onAttachmentRemove;
  final List<String> validationErrors;

  @override
  State<NoteNodeEditor> createState() => _NoteNodeEditorState();
}

final class _NoteNodeEditorState extends State<NoteNodeEditor> {
  late final TextEditingController _bodyController;
  late final TextEditingController _searchController;
  late final TextEditingController _tagController;
  final ScrollController _editorScrollController = ScrollController();
  bool _showPreview = false;
  int _searchIndex = -1;

  NotePayload get payload => widget.payload;

  @override
  void initState() {
    super.initState();
    _bodyController = TextEditingController(text: widget.node.body);
    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _tagController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant NoteNodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _bodyController.text = widget.node.body;
      _searchController.clear();
      _searchIndex = -1;
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _searchController.dispose();
    _tagController.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchIndex = -1);
  }

  List<RegExpMatch> get _matches {
    final query = _searchController.text.trim();
    if (query.isEmpty) return const <RegExpMatch>[];
    return RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(_bodyController.text).toList(growable: false);
  }

  void _nextMatch() {
    final matches = _matches;
    if (matches.isEmpty) return;
    _searchIndex = (_searchIndex + 1) % matches.length;
    final match = matches[_searchIndex];
    _bodyController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    setState(() => _showPreview = false);
  }

  void _replaceSelection(String prefix, String suffix, {String fallback = ''}) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = start == end ? fallback : text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    _bodyController.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    widget.onBodyChanged(_bodyController.text);
    setState(() {});
  }

  List<_NoteHeading> get _headings {
    final headings = <_NoteHeading>[];
    var offset = 0;
    for (final line in _bodyController.text.split('\n')) {
      final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (match != null) {
        headings.add(
          _NoteHeading(
            level: match.group(1)!.length,
            title: match.group(2)!.trim(),
            offset: offset,
          ),
        );
      }
      offset += line.length + 1;
    }
    return headings;
  }

  int get _wordCount => RegExp(r'\S+').allMatches(_bodyController.text).length;

  Future<void> _addSource() async {
    final labelController = TextEditingController();
    final urlController = TextEditingController();
    final source = await showDialog<NoteSourceLink>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: labelController,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'https://...'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final url = urlController.text.trim();
              final uri = Uri.tryParse(url);
              if (uri == null ||
                  !uri.hasAuthority ||
                  (uri.scheme != 'http' && uri.scheme != 'https')) {
                return;
              }
              Navigator.pop(
                context,
                NoteSourceLink(
                  id: 'source-${const Uuid().v4()}',
                  label: labelController.text.trim().isEmpty
                      ? uri.host
                      : labelController.text.trim(),
                  url: url,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    labelController.dispose();
    urlController.dispose();
    if (source == null) return;
    widget.onPayloadChanged(
      payload.copyWith(
        sourceLinks: <NoteSourceLink>[...payload.sourceLinks, source],
      ),
    );
  }

  Color _colorForToken(String token, AppSemanticColors semantic) =>
      switch (token) {
        'violet' => semantic.nodeColors[NodeType.goal]!,
        'blue' => semantic.info,
        'green' => semantic.success,
        'amber' => semantic.warning,
        'rose' => semantic.nodeColors[NodeType.journal]!,
        _ => semantic.border,
      };

  List<String> _normalizedTags(Iterable<String> tags) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in tags) {
      final tag = value.trim().replaceFirst(RegExp(r'^#+'), '');
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      normalized.add(tag);
    }
    return normalized;
  }

  void _saveTags(Iterable<String> tags) {
    widget.onNodeChanged(
      widget.node.copyWith(
        tags: _normalizedTags(tags),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _addTag([String? submitted]) {
    final value = (submitted ?? _tagController.text).trim();
    if (value.isEmpty) return;
    _saveTags(<String>[...widget.node.tags, value]);
    _tagController.clear();
  }

  void _removeTag(String tag) {
    _saveTags(widget.node.tags.where((item) => item != tag));
  }

  Future<void> _editTag(String tag) async {
    var value = tag;
    final changed = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit tag'),
        content: TextFormField(
          key: const ValueKey<String>('note-tag-edit-field'),
          initialValue: tag,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag'),
          onChanged: (next) => value = next,
          onFieldSubmitted: (next) => Navigator.of(context).pop(next),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('note-tag-edit-save'),
            onPressed: () => Navigator.of(context).pop(value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (changed == null || changed.trim().isEmpty) return;
    _saveTags(<String>[
      for (final item in widget.node.tags) item == tag ? changed : item,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final accent = _colorForToken(payload.color, semantic);
    return AnimatedContainer(
      key: const ValueKey<String>('note-node-editor'),
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: payload.color == 'neutral'
            ? colors.surface
            : Color.alphaBlend(accent.withValues(alpha: 0.12), colors.surface),
        border: Border.all(
          color: payload.color == 'neutral'
              ? colors.outlineVariant
              : accent.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          key: ValueKey<String>(
                            'productivity-${widget.node.id}-title-field',
                          ),
                          initialValue: widget.node.title,
                          maxLength: 80,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.note_alt_outlined),
                            hintText: 'Note title',
                            counterText: '',
                            isDense: true,
                          ),
                          onChanged: widget.onTitleChanged,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const ValueKey<String>('note-pin-action'),
                        tooltip: widget.node.isPinned
                            ? 'Unpin note'
                            : 'Pin note',
                        onPressed: () => widget.onNodeChanged(
                          widget.node.copyWith(
                            isPinned: !widget.node.isPinned,
                            updatedAt: DateTime.now(),
                          ),
                        ),
                        icon: Icon(
                          widget.node.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Note color',
                        onSelected: (color) => widget.onPayloadChanged(
                          payload.copyWith(color: color),
                        ),
                        icon: Icon(
                          Icons.palette_outlined,
                          color: _colorForToken(payload.color, semantic),
                        ),
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          for (final token in noteColorTokens)
                            PopupMenuItem<String>(
                              value: token,
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    payload.color == token
                                        ? Icons.radio_button_checked
                                        : Icons.circle,
                                    color: _colorForToken(token, semantic),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(token),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  for (final error in widget.validationErrors)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      _tool(
                        Icons.title,
                        'Heading',
                        () => _replaceSelection('## ', '', fallback: 'Heading'),
                      ),
                      _tool(
                        Icons.format_bold,
                        'Bold',
                        () => _replaceSelection('**', '**', fallback: 'bold'),
                      ),
                      _tool(
                        Icons.format_italic,
                        'Italic',
                        () => _replaceSelection('_', '_', fallback: 'italic'),
                      ),
                      _tool(
                        Icons.format_quote,
                        'Quote',
                        () => _replaceSelection('> ', '', fallback: 'quote'),
                      ),
                      _tool(
                        Icons.format_list_bulleted,
                        'Bullet list',
                        () => _replaceSelection('- ', '', fallback: 'item'),
                      ),
                      _tool(
                        Icons.format_list_numbered,
                        'Numbered list',
                        () => _replaceSelection('1. ', '', fallback: 'item'),
                      ),
                      _tool(
                        Icons.check_box_outlined,
                        'Checklist',
                        () => _replaceSelection('- [ ] ', '', fallback: 'item'),
                      ),
                      _tool(
                        Icons.link,
                        'Link',
                        () => _replaceSelection(
                          '[',
                          '](https://)',
                          fallback: 'label',
                        ),
                      ),
                      _tool(
                        Icons.code,
                        'Inline code',
                        () => _replaceSelection('`', '`', fallback: 'code'),
                      ),
                      _tool(
                        Icons.data_object,
                        'Code block',
                        () => _replaceSelection(
                          '```\n',
                          '\n```',
                          fallback: 'code',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 140,
                          maxWidth: 360,
                        ),
                        child: TextField(
                          key: const ValueKey<String>('note-search-field'),
                          controller: _searchController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search in note',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _nextMatch(),
                        ),
                      ),
                      Text('${_matches.length} matches'),
                      IconButton(
                        tooltip: 'Next match',
                        onPressed: _matches.isEmpty ? null : _nextMatch,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      if (!wide)
                        SegmentedButton<bool>(
                          segments: const <ButtonSegment<bool>>[
                            ButtonSegment(value: false, label: Text('Edit')),
                            ButtonSegment(value: true, label: Text('Preview')),
                          ],
                          selected: <bool>{_showPreview},
                          onSelectionChanged: (value) =>
                              setState(() => _showPreview = value.single),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 280,
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Expanded(child: _editorPane()),
                              const VerticalDivider(width: 20),
                              Expanded(child: _previewPane()),
                            ],
                          )
                        : (_showPreview ? _previewPane() : _editorPane()),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$_wordCount words • ${_bodyController.text.length} characters',
                  ),
                  const SizedBox(height: 8),
                  _metadata(colors),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton.outlined(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      );

  Widget _editorPane() => TextField(
    key: const ValueKey<String>('note-markdown-editor'),
    controller: _bodyController,
    scrollController: _editorScrollController,
    expands: true,
    minLines: null,
    maxLines: null,
    textAlignVertical: TextAlignVertical.top,
    inputFormatters: <TextInputFormatter>[
      LengthLimitingTextInputFormatter(50000),
    ],
    decoration: const InputDecoration(
      hintText: 'Write Markdown...',
      alignLabelWithHint: true,
    ),
    onChanged: (value) {
      widget.onBodyChanged(value);
      setState(() {});
    },
  );

  Widget _previewPane() => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        key: const ValueKey<String>('note-markdown-preview'),
        data: _bodyController.text,
        selectable: true,
        onTapLink: (text, href, title) async {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        },
      ),
    ),
  );

  Widget _metadata(ColorScheme colors) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      SizedBox(
        width: 260,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('note-tag-input'),
                controller: _tagController,
                decoration: const InputDecoration(
                  labelText: 'Add tag',
                  hintText: 'research',
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _addTag,
              ),
            ),
            IconButton.filledTonal(
              key: const ValueKey<String>('note-tag-add'),
              tooltip: 'Add tag',
              onPressed: _addTag,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      for (final tag in widget.node.tags)
        InputChip(
          key: ValueKey<String>('note-tag-$tag'),
          avatar: const Icon(Icons.tag, size: 16),
          label: Text(tag),
          tooltip: 'Edit tag',
          onPressed: () => _editTag(tag),
          onDeleted: () => _removeTag(tag),
        ),
      OutlinedButton.icon(
        key: const ValueKey<String>('note-add-source'),
        onPressed: _addSource,
        icon: const Icon(Icons.add_link),
        label: Text('Sources ${payload.sourceLinks.length}'),
      ),
      OutlinedButton.icon(
        onPressed: widget.onAttachmentAdd == null
            ? null
            : () async {
                final attachment = await widget.onAttachmentAdd!();
                if (attachment == null) return;
                widget.onPayloadChanged(
                  payload.copyWith(
                    attachments: <TaskAttachmentReference>[
                      ...payload.attachments,
                      attachment,
                    ],
                  ),
                );
              },
        icon: const Icon(Icons.attach_file),
        label: Text('Attachments ${payload.attachments.length}'),
      ),
      Chip(
        avatar: const Icon(Icons.hub_outlined, size: 16),
        label: Text('Related ${widget.node.relatedNodeIds.length}'),
      ),
      if (_headings.isNotEmpty)
        PopupMenuButton<_NoteHeading>(
          tooltip: 'Table of contents',
          onSelected: (heading) {
            _bodyController.selection = TextSelection.collapsed(
              offset: heading.offset,
            );
            setState(() => _showPreview = false);
          },
          itemBuilder: (context) => <PopupMenuEntry<_NoteHeading>>[
            for (final heading in _headings)
              PopupMenuItem<_NoteHeading>(
                value: heading,
                child: Padding(
                  padding: EdgeInsets.only(left: (heading.level - 1) * 10.0),
                  child: Text(heading.title),
                ),
              ),
          ],
          child: const Chip(
            avatar: Icon(Icons.toc, size: 16),
            label: Text('Contents'),
          ),
        ),
      for (final source in payload.sourceLinks)
        InputChip(
          avatar: const Icon(Icons.link, size: 16),
          label: Text(source.label),
          onPressed: () async {
            final uri = Uri.tryParse(source.url);
            if (uri != null) await launchUrl(uri);
          },
          onDeleted: () => widget.onPayloadChanged(
            payload.copyWith(
              sourceLinks: payload.sourceLinks
                  .where((item) => item.id != source.id)
                  .toList(growable: false),
            ),
          ),
        ),
      for (final attachment in payload.attachments)
        InputChip(
          avatar: const Icon(Icons.description_outlined, size: 16),
          label: Text(attachment.fileName),
          onPressed: widget.onAttachmentOpen == null
              ? null
              : () => widget.onAttachmentOpen!(attachment),
          onDeleted: widget.onAttachmentRemove == null
              ? null
              : () async {
                  await widget.onAttachmentRemove!(attachment);
                  widget.onPayloadChanged(
                    payload.copyWith(
                      attachments: payload.attachments
                          .where((item) => item.id != attachment.id)
                          .toList(growable: false),
                    ),
                  );
                },
        ),
    ],
  );
}

final class _NoteHeading {
  const _NoteHeading({
    required this.level,
    required this.title,
    required this.offset,
  });

  final int level;
  final String title;
  final int offset;
}
