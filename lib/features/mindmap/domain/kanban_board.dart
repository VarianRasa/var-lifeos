/// Domain model for a compact kanban board stored inside a mindmap node.
library;

import 'package:collection/collection.dart';

enum KanbanColumn {
  todo,
  doing,
  done;

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

  static KanbanColumn fromName(String? name) {
    for (final column in KanbanColumn.values) {
      if (column.name == name) return column;
    }
    return KanbanColumn.todo;
  }
}

final class KanbanCard {
  const KanbanCard({
    required this.id,
    required this.title,
    this.column = KanbanColumn.todo,
  });

  factory KanbanCard.fromJson(Map<String, Object?> json) {
    return KanbanCard(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      column: KanbanColumn.fromName(json['column'] as String?),
    );
  }

  final String id;
  final String title;
  final KanbanColumn column;

  KanbanCard copyWith({String? id, String? title, KanbanColumn? column}) {
    return KanbanCard(
      id: id ?? this.id,
      title: title ?? this.title,
      column: column ?? this.column,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'column': column.name,
  };

  @override
  bool operator ==(Object other) {
    return other is KanbanCard &&
        other.id == id &&
        other.title == title &&
        other.column == column;
  }

  @override
  int get hashCode => Object.hash(id, title, column);
}

final class KanbanBoard {
  const KanbanBoard({this.cards = const []});

  factory KanbanBoard.fromJson(Map<String, Object?> json) {
    final rawCards = json['cards'];
    return KanbanBoard(
      cards: [
        if (rawCards is List)
          for (final rawCard in rawCards)
            if (rawCard is Map)
              KanbanCard.fromJson(rawCard.cast<String, Object?>()),
      ],
    );
  }

  factory KanbanBoard.fromNodeData(Map<String, Object?> data) {
    final rawBoard = data['kanban'];
    if (rawBoard is Map) {
      return KanbanBoard.fromJson(rawBoard.cast<String, Object?>());
    }
    return const KanbanBoard();
  }

  final List<KanbanCard> cards;

  List<KanbanCard> cardsFor(KanbanColumn column) {
    return List.unmodifiable(cards.where((card) => card.column == column));
  }

  KanbanCard? cardById(String id) {
    for (final card in cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  KanbanBoard moveCardToNextColumn(String cardId) {
    return KanbanBoard(
      cards: [
        for (final card in cards)
          if (card.id == cardId && card.column.next != null)
            card.copyWith(column: card.column.next)
          else
            card,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'cards': [for (final card in cards) card.toJson()],
  };

  @override
  bool operator ==(Object other) {
    return other is KanbanBoard &&
        const ListEquality<KanbanCard>().equals(other.cards, cards);
  }

  @override
  int get hashCode => const ListEquality<KanbanCard>().hash(cards);
}
