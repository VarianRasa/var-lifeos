import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';

void main() {
  test('groups cards by kanban column and advances a card', () {
    const board = KanbanBoard(
      cards: [
        KanbanCard(id: 'card-1', title: 'Draft copy'),
        KanbanCard(
          id: 'card-2',
          title: 'Review scope',
          column: KanbanColumn.doing,
        ),
      ],
    );

    expect(board.cardsFor(KanbanColumn.todo).single.title, 'Draft copy');
    expect(board.cardsFor(KanbanColumn.doing).single.title, 'Review scope');

    final moved = board.moveCardToNextColumn('card-1');

    expect(moved.cardById('card-1')?.column, KanbanColumn.doing);
  });

  test('serializes to JSON and restores cards', () {
    const board = KanbanBoard(
      cards: [
        KanbanCard(id: 'card-1', title: 'Draft copy'),
        KanbanCard(
          id: 'card-2',
          title: 'Ship update',
          column: KanbanColumn.done,
        ),
      ],
    );

    final restored = KanbanBoard.fromJson(board.toJson());

    expect(restored.cards, board.cards);
    expect(restored.cardsFor(KanbanColumn.done).single.title, 'Ship update');
  });
}
