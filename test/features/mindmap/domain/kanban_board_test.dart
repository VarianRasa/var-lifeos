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

  test('migrates legacy cards into flexible default columns', () {
    final board = KanbanBoard.fromJson({
      'cards': [
        {'id': 'legacy', 'title': 'Legacy card', 'column': 'doing'},
      ],
    });

    expect(board.columns, defaultKanbanColumns);
    expect(board.cardById('legacy')?.columnId, kanbanInProgressColumnId);
  });

  test('round trips rich cards and reorders across custom columns', () {
    final dueDate = DateTime(2026, 7, 20);
    final board = KanbanBoard(
      columns: const [
        KanbanColumnDefinition(id: 'ideas', title: 'Ideas', order: 0),
        KanbanColumnDefinition(id: 'shipping', title: 'Shipping', order: 1),
      ],
      cards: [
        KanbanCard(
          id: 'rich',
          title: 'Rich card',
          customColumnId: 'ideas',
          description: 'Context',
          priority: KanbanPriority.high,
          dueDate: dueDate,
          labels: const ['design'],
          checklist: const [KanbanChecklistItem(id: 'check', title: 'Review')],
          attachments: const [
            KanbanAttachmentReference(
              id: 'file',
              fileName: 'brief.pdf',
              mimeType: 'application/pdf',
              byteLength: 42,
            ),
          ],
        ),
      ],
    );

    final moved = board.moveCard('rich', 'shipping', 0);
    final restored = KanbanBoard.fromJson(moved.toJson());

    expect(restored.cardById('rich')?.columnId, 'shipping');
    expect(restored.cardById('rich')?.priority, KanbanPriority.high);
    expect(restored.cardById('rich')?.attachments.single.fileName, 'brief.pdf');
  });
}
