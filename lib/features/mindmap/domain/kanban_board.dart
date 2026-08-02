/// Domain model for a kanban board stored inside a mindmap node.
library;

import 'package:collection/collection.dart';

const String kanbanBacklogColumnId = 'backlog';
const String kanbanInProgressColumnId = 'in-progress';
const String kanbanDoneColumnId = 'done';
const int maxKanbanColumns = 6;

enum KanbanColumn {
  todo,
  doing,
  done;

  String get id => switch (this) {
    KanbanColumn.todo => kanbanBacklogColumnId,
    KanbanColumn.doing => kanbanInProgressColumnId,
    KanbanColumn.done => kanbanDoneColumnId,
  };

  String get label => switch (this) {
    KanbanColumn.todo => 'Todo',
    KanbanColumn.doing => 'Doing',
    KanbanColumn.done => 'Done',
  };

  KanbanColumn? get next => switch (this) {
    KanbanColumn.todo => KanbanColumn.doing,
    KanbanColumn.doing => KanbanColumn.done,
    KanbanColumn.done => null,
  };

  static KanbanColumn fromName(String? name) => switch (name) {
    'doing' || kanbanInProgressColumnId => KanbanColumn.doing,
    'done' => KanbanColumn.done,
    _ => KanbanColumn.todo,
  };

  static KanbanColumn fromId(String? id) => fromName(id);
}

enum KanbanPriority {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High'),
  urgent('Urgent');

  const KanbanPriority(this.label);
  final String label;

  static KanbanPriority fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => KanbanPriority.none,
  );
}

final class KanbanColumnDefinition {
  const KanbanColumnDefinition({
    required this.id,
    required this.title,
    required this.order,
    this.isDoneColumn = false,
  });

  factory KanbanColumnDefinition.fromJson(
    Map<String, Object?> json, {
    required int fallbackOrder,
  }) {
    final id = (json['id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? '').trim();
    return KanbanColumnDefinition(
      id: id.isEmpty ? 'column-$fallbackOrder' : id,
      title: title.isEmpty ? 'Column ${fallbackOrder + 1}' : title,
      order: json['order'] is int ? json['order'] as int : fallbackOrder,
      isDoneColumn: json['isDoneColumn'] as bool? ?? false,
    );
  }

  final String id;
  final String title;
  final int order;
  final bool isDoneColumn;

  KanbanColumnDefinition copyWith({
    String? id,
    String? title,
    int? order,
    bool? isDoneColumn,
  }) => KanbanColumnDefinition(
    id: id ?? this.id,
    title: title ?? this.title,
    order: order ?? this.order,
    isDoneColumn: isDoneColumn ?? this.isDoneColumn,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'order': order,
    'isDoneColumn': isDoneColumn,
  };

  @override
  bool operator ==(Object other) =>
      other is KanbanColumnDefinition &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      other.isDoneColumn == isDoneColumn;

  @override
  int get hashCode => Object.hash(id, title, order, isDoneColumn);
}

const List<KanbanColumnDefinition> defaultKanbanColumns = [
  KanbanColumnDefinition(id: kanbanBacklogColumnId, title: 'Backlog', order: 0),
  KanbanColumnDefinition(
    id: kanbanInProgressColumnId,
    title: 'In Progress',
    order: 1,
  ),
  KanbanColumnDefinition(
    id: kanbanDoneColumnId,
    title: 'Done',
    order: 2,
    isDoneColumn: true,
  ),
];

final class KanbanChecklistItem {
  const KanbanChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  factory KanbanChecklistItem.fromJson(Map<String, Object?> json) =>
      KanbanChecklistItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        isDone: json['isDone'] as bool? ?? false,
      );

  final String id;
  final String title;
  final bool isDone;

  KanbanChecklistItem copyWith({String? title, bool? isDone}) =>
      KanbanChecklistItem(
        id: id,
        title: title ?? this.title,
        isDone: isDone ?? this.isDone,
      );

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'isDone': isDone};

  @override
  bool operator ==(Object other) =>
      other is KanbanChecklistItem &&
      other.id == id &&
      other.title == title &&
      other.isDone == isDone;

  @override
  int get hashCode => Object.hash(id, title, isDone);
}

final class KanbanAttachmentReference {
  const KanbanAttachmentReference({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });

  factory KanbanAttachmentReference.fromJson(Map<String, Object?> json) =>
      KanbanAttachmentReference(
        id: json['id'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        byteLength: json['byteLength'] as int? ?? 0,
      );

  final String id;
  final String fileName;
  final String mimeType;
  final int byteLength;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'mimeType': mimeType,
    'byteLength': byteLength,
  };

  @override
  bool operator ==(Object other) =>
      other is KanbanAttachmentReference &&
      other.id == id &&
      other.fileName == fileName &&
      other.mimeType == mimeType &&
      other.byteLength == byteLength;

  @override
  int get hashCode => Object.hash(id, fileName, mimeType, byteLength);
}

final class KanbanCard {
  const KanbanCard({
    required this.id,
    required this.title,
    this.column = KanbanColumn.todo,
    this.customColumnId,
    this.order = 0,
    this.description = '',
    this.priority = KanbanPriority.none,
    this.dueDate,
    this.labels = const [],
    this.checklist = const [],
    this.attachments = const [],
  });

  factory KanbanCard.fromJson(Map<String, Object?> json) {
    final legacyColumn = KanbanColumn.fromName(
      json['column'] is String ? json['column'] as String : null,
    );
    final rawLabels = json['labels'];
    final rawChecklist = json['checklist'];
    final rawAttachments = json['attachments'];
    return KanbanCard(
      id: json['id'] is String ? json['id'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      column: legacyColumn,
      customColumnId:
          json['columnId'] is String &&
              (json['columnId'] as String).trim().isNotEmpty
          ? (json['columnId'] as String).trim()
          : null,
      order: json['order'] is int ? json['order'] as int : 0,
      description: json['description'] is String
          ? json['description'] as String
          : '',
      priority: KanbanPriority.fromName(
        json['priority'] is String ? json['priority'] as String : null,
      ),
      dueDate: DateTime.tryParse(
        json['dueDate'] is String ? json['dueDate'] as String : '',
      ),
      labels: [
        if (rawLabels is List)
          for (final label in rawLabels)
            if (label is String && label.trim().isNotEmpty) label.trim(),
      ],
      checklist: [
        if (rawChecklist is List)
          for (final item in rawChecklist)
            if (item is Map)
              KanbanChecklistItem.fromJson(item.cast<String, Object?>()),
      ],
      attachments: [
        if (rawAttachments is List)
          for (final item in rawAttachments)
            if (item is Map)
              KanbanAttachmentReference.fromJson(item.cast<String, Object?>()),
      ],
    );
  }

  final String id;
  final String title;
  final KanbanColumn column;
  final String? customColumnId;
  final int order;
  final String description;
  final KanbanPriority priority;
  final DateTime? dueDate;
  final List<String> labels;
  final List<KanbanChecklistItem> checklist;
  final List<KanbanAttachmentReference> attachments;

  String get columnId => customColumnId ?? column.id;
  int get completedChecklistCount =>
      checklist.where((item) => item.isDone).length;

  KanbanCard copyWith({
    String? id,
    String? title,
    KanbanColumn? column,
    String? columnId,
    int? order,
    String? description,
    KanbanPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
    List<String>? labels,
    List<KanbanChecklistItem>? checklist,
    List<KanbanAttachmentReference>? attachments,
  }) => KanbanCard(
    id: id ?? this.id,
    title: title ?? this.title,
    column:
        column ??
        (columnId == null ? this.column : KanbanColumn.fromId(columnId)),
    customColumnId: columnId ?? customColumnId,
    order: order ?? this.order,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
    labels: labels ?? this.labels,
    checklist: checklist ?? this.checklist,
    attachments: attachments ?? this.attachments,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'columnId': columnId,
    'column': column.name,
    'order': order,
    'description': description,
    'priority': priority.name,
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
    'labels': labels,
    'checklist': [for (final item in checklist) item.toJson()],
    'attachments': [for (final item in attachments) item.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is KanbanCard &&
      other.id == id &&
      other.title == title &&
      other.columnId == columnId &&
      other.order == order &&
      other.description == description &&
      other.priority == priority &&
      other.dueDate == dueDate &&
      const ListEquality<String>().equals(other.labels, labels) &&
      const ListEquality<KanbanChecklistItem>().equals(
        other.checklist,
        checklist,
      ) &&
      const ListEquality<KanbanAttachmentReference>().equals(
        other.attachments,
        attachments,
      );

  @override
  int get hashCode => Object.hash(
    id,
    title,
    columnId,
    order,
    description,
    priority,
    dueDate,
    const ListEquality<String>().hash(labels),
    const ListEquality<KanbanChecklistItem>().hash(checklist),
    const ListEquality<KanbanAttachmentReference>().hash(attachments),
  );
}

final class KanbanBoard {
  const KanbanBoard({
    this.columns = defaultKanbanColumns,
    this.cards = const [],
  });

  factory KanbanBoard.fromJson(Map<String, Object?> json) {
    final rawColumns = json['columns'];
    final decodedColumns = <KanbanColumnDefinition>[];
    final seenIds = <String>{};
    if (rawColumns is List) {
      for (var index = 0; index < rawColumns.length; index++) {
        final rawColumn = rawColumns[index];
        if (rawColumn is! Map) continue;
        final column = KanbanColumnDefinition.fromJson(
          rawColumn.cast<String, Object?>(),
          fallbackOrder: index,
        );
        if (seenIds.add(column.id)) decodedColumns.add(column);
      }
    }
    final columns = decodedColumns.isEmpty
        ? defaultKanbanColumns
        : (decodedColumns
            ..sort((left, right) => left.order.compareTo(right.order)));
    final columnIds = columns.map((column) => column.id).toSet();
    final fallbackColumnId = columns.first.id;
    final rawCards = json['cards'];
    final cards = <KanbanCard>[];
    if (rawCards is List) {
      for (var index = 0; index < rawCards.length; index++) {
        final rawCard = rawCards[index];
        if (rawCard is! Map) continue;
        final card = KanbanCard.fromJson(rawCard.cast<String, Object?>());
        if (card.title.trim().isEmpty) continue;
        cards.add(
          card.copyWith(
            columnId: columnIds.contains(card.columnId)
                ? card.columnId
                : fallbackColumnId,
            order: rawCard['order'] is int ? card.order : index,
          ),
        );
      }
    }
    return KanbanBoard(columns: List.unmodifiable(columns), cards: cards);
  }

  factory KanbanBoard.fromNodeData(Map<String, Object?> data) {
    final rawBoard = data['kanban'];
    return rawBoard is Map
        ? KanbanBoard.fromJson(rawBoard.cast<String, Object?>())
        : const KanbanBoard();
  }

  final List<KanbanColumnDefinition> columns;
  final List<KanbanCard> cards;

  List<KanbanCard> cardsFor(Object column) {
    final columnId = column is KanbanColumn ? column.id : column.toString();
    final result = cards.where((card) => card.columnId == columnId).toList()
      ..sort((left, right) => left.order.compareTo(right.order));
    return List.unmodifiable(result);
  }

  KanbanCard? cardById(String id) =>
      cards.firstWhereOrNull((card) => card.id == id);

  KanbanBoard copyWith({
    List<KanbanColumnDefinition>? columns,
    List<KanbanCard>? cards,
  }) =>
      KanbanBoard(columns: columns ?? this.columns, cards: cards ?? this.cards);

  KanbanBoard moveCard(String cardId, String columnId, int order) {
    final targetCards =
        cards
            .where((card) => card.columnId == columnId && card.id != cardId)
            .toList()
          ..sort((left, right) => left.order.compareTo(right.order));
    final insertion = order.clamp(0, targetCards.length);
    final moved = cardById(cardId);
    if (moved == null) return this;
    targetCards.insert(insertion, moved.copyWith(columnId: columnId));
    final normalized = <KanbanCard>[
      for (final card in cards)
        if (card.id != cardId && card.columnId != columnId) card,
      for (var index = 0; index < targetCards.length; index++)
        targetCards[index].copyWith(order: index),
    ];
    return copyWith(cards: normalized);
  }

  KanbanBoard moveCardToNextColumn(String cardId) {
    final card = cardById(cardId);
    if (card == null) return this;
    final index = columns.indexWhere((column) => column.id == card.columnId);
    if (index < 0 || index >= columns.length - 1) return this;
    return moveCard(
      cardId,
      columns[index + 1].id,
      cardsFor(columns[index + 1].id).length,
    );
  }

  Map<String, Object?> toJson() => {
    'columns': [for (final column in columns) column.toJson()],
    'cards': [for (final card in cards) card.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is KanbanBoard &&
      const ListEquality<KanbanColumnDefinition>().equals(
        other.columns,
        columns,
      ) &&
      const ListEquality<KanbanCard>().equals(other.cards, cards);

  @override
  int get hashCode => Object.hash(
    const ListEquality<KanbanColumnDefinition>().hash(columns),
    const ListEquality<KanbanCard>().hash(cards),
  );
}
