import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';

enum ChecklistFilter { all, active, done }

final class ChecklistNodeEditor extends StatefulWidget {
  const ChecklistNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    super.key,
  });

  final MindmapNode node;
  final ChecklistPayload payload;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<ChecklistPayload> onPayloadChanged;

  @override
  State<ChecklistNodeEditor> createState() => _ChecklistNodeEditorState();
}

final class _ChecklistNodeEditorState extends State<ChecklistNodeEditor> {
  final TextEditingController _newItemController = TextEditingController();
  ChecklistFilter _filter = ChecklistFilter.all;

  ChecklistPayload get payload => widget.payload;

  @override
  void dispose() {
    _newItemController.dispose();
    super.dispose();
  }

  void _emit(List<ChecklistEntry> items) {
    widget.onPayloadChanged(payload.copyWith(items: items));
  }

  void _addItem() {
    final title = _newItemController.text.trim();
    if (title.isEmpty) return;
    _emit(<ChecklistEntry>[
      ...payload.items,
      ChecklistEntry(id: 'check-${const Uuid().v4()}', title: title),
    ]);
    _newItemController.clear();
  }

  void _replace(ChecklistEntry current, ChecklistEntry replacement) {
    _emit(<ChecklistEntry>[
      for (final item in payload.items)
        if (item.id == current.id) replacement else item,
    ]);
  }

  Future<void> _editItem(ChecklistEntry item) async {
    final controller = TextEditingController(text: item.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit checklist item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(160),
          ],
          decoration: const InputDecoration(labelText: 'Item'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    _replace(item, item.copyWith(title: title));
  }

  Future<void> _pickDeadline(ChecklistEntry item) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: item.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null) _replace(item, item.copyWith(dueDate: selected));
  }

  List<ChecklistEntry> get _visibleItems => switch (_filter) {
    ChecklistFilter.all => payload.items,
    ChecklistFilter.active =>
      payload.items.where((item) => !item.isDone).toList(growable: false),
    ChecklistFilter.done =>
      payload.items.where((item) => item.isDone).toList(growable: false),
  };

  void _reorder(int oldIndex, int newIndex) {
    if (_filter == ChecklistFilter.done) return;
    if (newIndex > oldIndex) newIndex--;
    if (_filter == ChecklistFilter.all) {
      final items = List<ChecklistEntry>.from(payload.items);
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);
      _emit(items);
      return;
    }

    final activeItems = payload.items
        .where((item) => !item.isDone)
        .toList(growable: true);
    final item = activeItems.removeAt(oldIndex);
    activeItems.insert(newIndex, item);
    var activeIndex = 0;
    _emit(<ChecklistEntry>[
      for (final entry in payload.items)
        if (entry.isDone) entry else activeItems[activeIndex++],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleItems = _visibleItems;
    return ColoredBox(
      key: const ValueKey<String>('checklist-node-editor'),
      color: colors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              key: ValueKey<String>(
                'productivity-${widget.node.id}-title-field',
              ),
              initialValue: widget.node.title,
              maxLength: 80,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.checklist_rounded),
                hintText: 'Checklist title',
                counterText: '',
                isDense: true,
              ),
              onChanged: widget.onTitleChanged,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey<String>(
                'productivity-${widget.node.id}-body-field',
              ),
              initialValue: widget.node.body,
              minLines: 2,
              maxLines: 4,
              maxLength: 240,
              decoration: const InputDecoration(
                hintText: 'Checklist details',
                counterText: '',
                isDense: true,
              ),
              onChanged: widget.onBodyChanged,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${payload.completedCount}/${payload.items.length} completed',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text('${(payload.progress * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: payload.progress),
            const SizedBox(height: 12),
            SegmentedButton<ChecklistFilter>(
              segments: const <ButtonSegment<ChecklistFilter>>[
                ButtonSegment(value: ChecklistFilter.all, label: Text('All')),
                ButtonSegment(
                  value: ChecklistFilter.active,
                  label: Text('Active'),
                ),
                ButtonSegment(value: ChecklistFilter.done, label: Text('Done')),
              ],
              selected: <ChecklistFilter>{_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.single),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('checklist-add-field'),
                    controller: _newItemController,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(160),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'Add checklist item',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey<String>('checklist-add-action'),
                  tooltip: 'Add item',
                  onPressed: _addItem,
                  icon: const Icon(Icons.add_rounded),
                ),
                const SizedBox(width: 4),
                IconButton.outlined(
                  key: const ValueKey<String>('checklist-clear-completed'),
                  tooltip: 'Clear completed',
                  onPressed: payload.completedCount == 0
                      ? null
                      : () => _emit(
                          payload.items
                              .where((item) => !item.isDone)
                              .toList(growable: false),
                        ),
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (visibleItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No checklist items')),
              )
            else
              ReorderableListView.builder(
                key: const ValueKey<String>('checklist-items'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: visibleItems.length,
                onReorderItem: (oldIndex, newIndex) => _reorder(
                  oldIndex,
                  newIndex > oldIndex ? newIndex + 1 : newIndex,
                ),
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  return _ChecklistItemRow(
                    key: ValueKey<String>('checklist-item-${item.id}'),
                    item: item,
                    index: index,
                    reorderEnabled: _filter != ChecklistFilter.done,
                    onToggle: (value) =>
                        _replace(item, item.copyWith(isDone: value)),
                    onEdit: () => _editItem(item),
                    onDelete: () => _emit(
                      payload.items
                          .where((entry) => entry.id != item.id)
                          .toList(growable: false),
                    ),
                    onPriorityChanged: (priority) =>
                        _replace(item, item.copyWith(priority: priority)),
                    onDeadline: () => _pickDeadline(item),
                    onClearDeadline: () =>
                        _replace(item, item.copyWith(clearDueDate: true)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

final class _ChecklistItemRow extends StatelessWidget {
  const _ChecklistItemRow({
    required this.item,
    required this.index,
    required this.reorderEnabled,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onPriorityChanged,
    required this.onDeadline,
    required this.onClearDeadline,
    super.key,
  });

  final ChecklistEntry item;
  final int index;
  final bool reorderEnabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<ChecklistPriority> onPriorityChanged;
  final VoidCallback onDeadline;
  final VoidCallback onClearDeadline;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: <Widget>[
          if (reorderEnabled)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_indicator_rounded),
              ),
            )
          else
            const SizedBox(width: 40),
          Checkbox(value: item.isDone, onChanged: (value) => onToggle(value!)),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: TextStyle(
                        decoration: item.isDone
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (item.dueDate != null)
                      Text(
                        DateFormat('EEE, d MMM yyyy').format(item.dueDate!),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<ChecklistPriority>(
            tooltip: 'Priority',
            initialValue: item.priority,
            onSelected: onPriorityChanged,
            icon: Icon(
              Icons.flag_outlined,
              color: _priorityColor(context, item.priority),
            ),
            itemBuilder: (context) => <PopupMenuEntry<ChecklistPriority>>[
              for (final priority in ChecklistPriority.values)
                PopupMenuItem<ChecklistPriority>(
                  value: priority,
                  child: Text(priority.name),
                ),
            ],
          ),
          IconButton(
            tooltip: item.dueDate == null ? 'Set deadline' : 'Clear deadline',
            onPressed: item.dueDate == null ? onDeadline : onClearDeadline,
            icon: Icon(
              item.dueDate == null
                  ? Icons.event_outlined
                  : Icons.event_busy_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Delete item',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    ),
  );
}

Color? _priorityColor(BuildContext context, ChecklistPriority priority) {
  final semantic = AppSemanticColors.of(context);
  return switch (priority) {
    ChecklistPriority.none => null,
    ChecklistPriority.low => semantic.info,
    ChecklistPriority.medium => semantic.warning,
    ChecklistPriority.high => semantic.danger,
  };
}
