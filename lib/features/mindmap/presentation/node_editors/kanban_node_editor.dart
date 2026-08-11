import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../domain/kanban_board.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';

typedef KanbanAttachmentAddCallback =
    Future<KanbanAttachmentReference?> Function();
typedef KanbanAttachmentActionCallback =
    Future<void> Function(KanbanAttachmentReference attachment);

final class KanbanNodeEditor extends StatefulWidget {
  const KanbanNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    this.onAttachmentAdd,
    this.onAttachmentOpen,
    this.onAttachmentRemove,
    super.key,
  });
  final MindmapNode node;
  final KanbanPayload payload;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<KanbanPayload> onPayloadChanged;
  final KanbanAttachmentAddCallback? onAttachmentAdd;
  final KanbanAttachmentActionCallback? onAttachmentOpen;
  final KanbanAttachmentActionCallback? onAttachmentRemove;
  @override
  State<KanbanNodeEditor> createState() => _KanbanNodeEditorState();
}

final class _KanbanNodeEditorState extends State<KanbanNodeEditor> {
  KanbanBoard get board => widget.payload.board;
  void _emit(KanbanBoard value) => widget.onPayloadChanged(
    KanbanPayload(columns: value.columns, cards: value.cards),
  );

  Future<String?> _textDialog(String title, String initial) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          autofocus: true,
          initialValue: initial,
          inputFormatters: [LengthLimitingTextInputFormatter(80)],
          onChanged: (next) => value = next,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _addColumn() async {
    if (board.columns.length >= maxKanbanColumns) return;
    final title = await _textDialog('Add column', '');
    if (title == null || title.isEmpty) return;
    final id = 'column-${const Uuid().v4()}';
    _emit(
      board.copyWith(
        columns: [
          ...board.columns,
          KanbanColumnDefinition(
            id: id,
            title: title,
            order: board.columns.length,
          ),
        ],
      ),
    );
  }

  Future<void> _renameColumn(KanbanColumnDefinition column) async {
    final title = await _textDialog('Rename column', column.title);
    if (title == null || title.isEmpty) return;
    _emit(
      board.copyWith(
        columns: [
          for (final item in board.columns)
            item.id == column.id ? item.copyWith(title: title) : item,
        ],
      ),
    );
  }

  Future<void> _setColumnWipLimit(KanbanColumnDefinition column) async {
    final value = await _textDialog(
      'Set WIP limit',
      column.wipLimit?.toString() ?? '',
    );
    if (value == null) return;
    final limit = int.tryParse(value);
    if (value.isNotEmpty && (limit == null || limit <= 0)) {
      _showWipMessage('WIP limit must be a positive number.');
      return;
    }
    _emit(
      board.copyWith(
        columns: [
          for (final item in board.columns)
            item.id == column.id
                ? item.copyWith(wipLimit: limit, clearWipLimit: value.isEmpty)
                : item,
        ],
      ),
    );
  }

  void _showWipMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _moveCard(String cardId, KanbanColumnDefinition column, int order) {
    if (!board.canAddCardTo(column.id, movingCardId: cardId)) {
      _showWipMessage('${column.title} reached WIP limit ${column.wipLimit}.');
      return;
    }
    _emit(board.moveCard(cardId, column.id, order));
  }

  void _moveColumn(String columnId, int targetIndex) {
    final columns = [...board.columns]
      ..sort((a, b) => a.order.compareTo(b.order));
    final sourceIndex = columns.indexWhere((item) => item.id == columnId);
    if (sourceIndex < 0) return;
    final value = columns.removeAt(sourceIndex);
    final insertionIndex = targetIndex.clamp(0, columns.length);
    columns.insert(insertionIndex, value);
    _emit(
      board.copyWith(
        columns: [
          for (var i = 0; i < columns.length; i++)
            columns[i].copyWith(order: i),
        ],
      ),
    );
  }

  Future<void> _deleteColumn(KanbanColumnDefinition column) async {
    if (board.columns.length <= 1) return;
    final targets = board.columns
        .where((item) => item.id != column.id)
        .toList();
    var destination = targets.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete column?'),
          content: DropdownButtonFormField<String>(
            initialValue: destination,
            decoration: const InputDecoration(labelText: 'Move cards to'),
            items: [
              for (final item in targets)
                DropdownMenuItem(value: item.id, child: Text(item.title)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => destination = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final columns = targets;
    _emit(
      board.copyWith(
        columns: [
          for (var i = 0; i < columns.length; i++)
            columns[i].copyWith(order: i),
        ],
        cards: [
          for (final card in board.cards)
            card.columnId == column.id
                ? card.copyWith(columnId: destination)
                : card,
        ],
      ),
    );
  }

  Future<void> _addCard(KanbanColumnDefinition column) async {
    if (!board.canAddCardTo(column.id)) {
      _showWipMessage('${column.title} reached WIP limit ${column.wipLimit}.');
      return;
    }
    final source = KanbanCard(
      id: const Uuid().v4(),
      title: '',
      customColumnId: column.id,
      order: board.cardsFor(column.id).length,
    );
    final card = await _cardDialog(source, isNew: true);
    if (card != null) _emit(board.copyWith(cards: [...board.cards, card]));
  }

  Future<void> _editCard(KanbanCard source) async {
    final card = await _cardDialog(source);
    if (card != null) {
      _emit(
        board.copyWith(
          cards: [
            for (final item in board.cards) item.id == source.id ? card : item,
          ],
        ),
      );
    }
  }

  Future<KanbanCard?> _cardDialog(
    KanbanCard source, {
    bool isNew = false,
  }) async {
    var draft = source;
    var labels = source.labels.join(', ');
    var checklist = source.checklist.map((item) => item.title).join('\n');
    return showDialog<KanbanCard>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isNew ? 'Add card' : 'Edit card'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: draft.title,
                    autofocus: true,
                    inputFormatters: [LengthLimitingTextInputFormatter(120)],
                    decoration: const InputDecoration(labelText: 'Title'),
                    onChanged: (value) => draft = draft.copyWith(title: value),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: draft.description,
                    minLines: 2,
                    maxLines: 4,
                    inputFormatters: [LengthLimitingTextInputFormatter(500)],
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) =>
                        draft = draft.copyWith(description: value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<KanbanPriority>(
                    initialValue: draft.priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      for (final value in KanbanPriority.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(
                          () => draft = draft.copyWith(priority: value),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          draft.dueDate == null
                              ? 'No deadline'
                              : DateFormat(
                                  'EEE, d MMM yyyy',
                                ).format(draft.dueDate!),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: draft.dueDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (value != null) {
                            setDialogState(
                              () => draft = draft.copyWith(dueDate: value),
                            );
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: const Text('Deadline'),
                      ),
                      if (draft.dueDate != null)
                        IconButton(
                          onPressed: () => setDialogState(
                            () => draft = draft.copyWith(clearDueDate: true),
                          ),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  TextFormField(
                    initialValue: labels,
                    decoration: const InputDecoration(
                      labelText: 'Labels',
                      hintText: 'design, urgent',
                    ),
                    onChanged: (value) => labels = value,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: checklist,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Checklist',
                      hintText: 'One item per line',
                    ),
                    onChanged: (value) => checklist = value,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Attachments',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  for (final attachment in draft.attachments)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file),
                      title: Text(attachment.fileName),
                      onTap: widget.onAttachmentOpen == null
                          ? null
                          : () => widget.onAttachmentOpen!(attachment),
                      trailing: widget.onAttachmentRemove == null
                          ? null
                          : IconButton(
                              onPressed: () async {
                                await widget.onAttachmentRemove!(attachment);
                                setDialogState(
                                  () => draft = draft.copyWith(
                                    attachments: draft.attachments
                                        .where(
                                          (item) => item.id != attachment.id,
                                        )
                                        .toList(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                    ),
                  if (widget.onAttachmentAdd != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final value = await widget.onAttachmentAdd!();
                          if (value != null) {
                            setDialogState(
                              () => draft = draft.copyWith(
                                attachments: [...draft.attachments, value],
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add attachment'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = draft.title.trim();
                if (title.isEmpty) return;
                final previous = {
                  for (final item in source.checklist) item.title: item,
                };
                final items = checklist
                    .split('\n')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .map(
                      (title) =>
                          previous[title] ??
                          KanbanChecklistItem(
                            id: const Uuid().v4(),
                            title: title,
                          ),
                    )
                    .toList();
                Navigator.pop(
                  dialogContext,
                  draft.copyWith(
                    title: title,
                    labels: labels
                        .split(',')
                        .map((value) => value.trim())
                        .where((value) => value.isNotEmpty)
                        .toSet()
                        .toList(),
                    checklist: items,
                  ),
                );
              },
              child: const Text('Save card'),
            ),
          ],
        ),
      ),
    );
  }

  void _duplicateCard(KanbanCard card) => _emit(
    board.copyWith(
      cards: [
        ...board.cards,
        card.copyWith(
          id: const Uuid().v4(),
          title: '${card.title} copy',
          order: board.cardsFor(card.columnId).length,
        ),
      ],
    ),
  );

  void _toggleChecklist(KanbanCard card, String itemId) {
    _emit(
      board.copyWith(
        cards: <KanbanCard>[
          for (final item in board.cards)
            if (item.id == card.id)
              item.copyWith(
                checklist: <KanbanChecklistItem>[
                  for (final checklistItem in item.checklist)
                    checklistItem.id == itemId
                        ? KanbanChecklistItem(
                            id: checklistItem.id,
                            title: checklistItem.title,
                            isDone: !checklistItem.isDone,
                          )
                        : checklistItem,
                ],
              )
            else
              item,
        ],
      ),
    );
  }

  Future<void> _deleteCard(KanbanCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Delete “${card.title}”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final attachment in card.attachments) {
      await widget.onAttachmentRemove?.call(attachment);
    }
    _emit(
      board.copyWith(
        cards: board.cards.where((item) => item.id != card.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = [...board.columns]
      ..sort((a, b) => a.order.compareTo(b.order));
    final doneIds = columns
        .where((item) => item.isDoneColumn)
        .map((item) => item.id)
        .toSet();
    final completed = board.cards
        .where((item) => doneIds.contains(item.columnId))
        .length;
    return ColoredBox(
      key: ValueKey('kanban-inline-editor-${widget.node.id}'),
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desiredWidth = columns.length * 270.0 + 24;
          final contentWidth = constraints.maxWidth > desiredWidth
              ? constraints.maxWidth
              : desiredWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        key: ValueKey(
                          'productivity-${widget.node.id}-title-field',
                        ),
                        initialValue: widget.node.title,
                        decoration: const InputDecoration(
                          hintText: 'Board title',
                          prefixIcon: Icon(Icons.view_kanban_outlined),
                          isDense: true,
                        ),
                        onChanged: widget.onTitleChanged,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        key: ValueKey(
                          'productivity-${widget.node.id}-body-field',
                        ),
                        initialValue: widget.node.body,
                        minLines: 1,
                        maxLines: 3,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(500),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Board goal or context…',
                          isDense: true,
                        ),
                        onChanged: widget.onBodyChanged,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              children: [
                                _InfoChip(
                                  Icons.dashboard_outlined,
                                  '${board.cards.length} cards',
                                ),
                                _InfoChip(
                                  Icons.task_alt,
                                  '$completed complete',
                                ),
                                _InfoChip(
                                  Icons.view_column_outlined,
                                  '${columns.length} columns',
                                ),
                              ],
                            ),
                          ),
                          if (board.cards.any(
                            (card) =>
                                board.columns.indexWhere(
                                  (column) => column.id == card.columnId,
                                ) <
                                board.columns.length - 1,
                          ))
                            IconButton(
                              key: const ValueKey('kanban-advance-card'),
                              tooltip: 'Advance next card',
                              onPressed: () {
                                final card = board.cards.firstWhere(
                                  (item) =>
                                      board.columns.indexWhere(
                                        (column) => column.id == item.columnId,
                                      ) <
                                      board.columns.length - 1,
                                );
                                _emit(board.moveCardToNextColumn(card.id));
                              },
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          FilledButton.tonalIcon(
                            key: const ValueKey('kanban-add-column'),
                            onPressed: columns.length >= maxKanbanColumns
                                ? null
                                : _addColumn,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Column'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < columns.length;
                            index++
                          ) ...[
                            DragTarget<_ColumnDragData>(
                              onWillAcceptWithDetails: (details) =>
                                  details.data.columnId != columns[index].id,
                              onAcceptWithDetails: (details) =>
                                  _moveColumn(details.data.columnId, index),
                              builder: (context, candidates, rejects) =>
                                  AnimatedContainer(
                                    key: ValueKey(
                                      'kanban-column-drop-${columns[index].id}',
                                    ),
                                    duration: const Duration(milliseconds: 120),
                                    width: 260,
                                    decoration: BoxDecoration(
                                      border: candidates.isEmpty
                                          ? null
                                          : Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 2,
                                            ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: _Column(
                                      column: columns[index],
                                      cards: board.cardsFor(columns[index].id),
                                      onAdd: () => _addCard(columns[index]),
                                      onRename: () =>
                                          _renameColumn(columns[index]),
                                      onSetWipLimit: () =>
                                          _setColumnWipLimit(columns[index]),
                                      onDelete: () =>
                                          _deleteColumn(columns[index]),
                                      onEdit: _editCard,
                                      onDuplicate: _duplicateCard,
                                      onCardDelete: _deleteCard,
                                      onChecklistToggle: _toggleChecklist,
                                      onAttachmentOpen:
                                          widget.onAttachmentOpen == null
                                          ? null
                                          : (attachment) =>
                                                widget.onAttachmentOpen!(
                                                  attachment,
                                                ),
                                      onDrop: (id, order) =>
                                          _moveCard(id, columns[index], order),
                                    ),
                                  ),
                            ),
                            if (index < columns.length - 1)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _ColumnDragData {
  const _ColumnDragData(this.columnId);
  final String columnId;
}

final class _ColumnDragHandle extends StatelessWidget {
  const _ColumnDragHandle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.drag_indicator_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    ],
  );
}

final class _Column extends StatelessWidget {
  const _Column({
    required this.column,
    required this.cards,
    required this.onAdd,
    required this.onRename,
    required this.onSetWipLimit,
    required this.onDelete,
    required this.onEdit,
    required this.onDuplicate,
    required this.onCardDelete,
    required this.onChecklistToggle,
    required this.onAttachmentOpen,
    required this.onDrop,
  });
  final KanbanColumnDefinition column;
  final List<KanbanCard> cards;
  final VoidCallback onAdd;
  final VoidCallback onRename;
  final VoidCallback onSetWipLimit;
  final VoidCallback onDelete;
  final ValueChanged<KanbanCard> onEdit;
  final ValueChanged<KanbanCard> onDuplicate;
  final ValueChanged<KanbanCard> onCardDelete;
  final void Function(KanbanCard, String) onChecklistToggle;
  final KanbanAttachmentActionCallback? onAttachmentOpen;
  final void Function(String, int) onDrop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDrop(details.data, cards.length),
      builder: (context, candidates, rejects) => Container(
        key: ValueKey('kanban-column-${column.id}'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? colors.surfaceContainerLow
              : colors.primaryContainer,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Draggable<_ColumnDragData>(
                    key: ValueKey('kanban-column-drag-${column.id}'),
                    data: _ColumnDragData(column.id),
                    axis: Axis.horizontal,
                    feedback: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 240,
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          column.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: _ColumnDragHandle(title: column.title),
                    ),
                    child: _ColumnDragHandle(title: column.title),
                  ),
                ),
                Text(
                  column.wipLimit == null
                      ? '${cards.length}'
                      : '${cards.length}/${column.wipLimit}',
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'wip') onSetWipLimit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                      value: 'wip',
                      child: Text(
                        column.wipLimit == null
                            ? 'Set WIP limit'
                            : 'Change WIP limit',
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (cards.isEmpty)
              InkWell(
                onTap: onAdd,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.add_card_outlined),
                      SizedBox(height: 6),
                      Text('Add first card'),
                    ],
                  ),
                ),
              ),
            for (var index = 0; index < cards.length; index++) ...[
              DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    details.data != cards[index].id,
                onAcceptWithDetails: (details) => onDrop(details.data, index),
                builder: (context, candidates, rejects) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: candidates.isEmpty ? 4 : 22,
                  decoration: BoxDecoration(
                    color: candidates.isEmpty ? null : colors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Draggable<String>(
                key: ValueKey('kanban-card-drag-${cards[index].id}'),
                data: cards[index].id,
                feedback: Material(
                  elevation: 8,
                  child: SizedBox(width: 240, child: _Card(card: cards[index])),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.3,
                  child: _Card(card: cards[index]),
                ),
                child: _Card(
                  card: cards[index],
                  onEdit: () => onEdit(cards[index]),
                  onDuplicate: () => onDuplicate(cards[index]),
                  onDelete: () => onCardDelete(cards[index]),
                  onChecklistToggle: (itemId) =>
                      onChecklistToggle(cards[index], itemId),
                  onAttachmentOpen: onAttachmentOpen,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (cards.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add card'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _Card extends StatelessWidget {
  const _Card({
    required this.card,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.onChecklistToggle,
    this.onAttachmentOpen,
  });
  final KanbanCard card;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onChecklistToggle;
  final KanbanAttachmentActionCallback? onAttachmentOpen;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('kanban-card-${card.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (onEdit != null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'duplicate') onDuplicate?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          if (card.description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              card.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (card.labels.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final label in card.labels.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 7),
          Wrap(
            spacing: 8,
            runSpacing: 5,
            children: [
              if (card.priority != KanbanPriority.none)
                _Meta(Icons.flag_outlined, card.priority.label),
              if (card.dueDate != null)
                _Meta(
                  Icons.event_outlined,
                  DateFormat('d MMM').format(card.dueDate!),
                ),
            ],
          ),
          if (card.checklist.isNotEmpty) ...[
            const SizedBox(height: 9),
            _CardSectionHeader(
              icon: Icons.checklist_rounded,
              label:
                  'Checklist ${card.completedChecklistCount}/${card.checklist.length}',
            ),
            const SizedBox(height: 4),
            for (final item in card.checklist)
              InkWell(
                key: ValueKey('kanban-checklist-${card.id}-${item.id}'),
                onTap: onChecklistToggle == null
                    ? null
                    : () => onChecklistToggle!(item.id),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.isDone
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 17,
                        color: item.isDone
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                decoration: item.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: item.isDone
                                    ? colors.onSurfaceVariant
                                    : null,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (card.attachments.isNotEmpty) ...[
            const SizedBox(height: 9),
            _CardSectionHeader(
              icon: Icons.attach_file_rounded,
              label: 'Attachments ${card.attachments.length}',
            ),
            const SizedBox(height: 4),
            for (final attachment in card.attachments)
              InkWell(
                key: ValueKey('kanban-attachment-${card.id}-${attachment.id}'),
                onTap: onAttachmentOpen == null
                    ? null
                    : () => onAttachmentOpen!(attachment),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          attachment.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (onAttachmentOpen != null)
                        const Icon(Icons.open_in_new_rounded, size: 14),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

final class _CardSectionHeader extends StatelessWidget {
  const _CardSectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

final class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

final class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13),
      const SizedBox(width: 3),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
