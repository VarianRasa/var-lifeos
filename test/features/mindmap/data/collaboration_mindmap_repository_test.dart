import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/collaboration_session.dart';
import 'package:var_app/features/mindmap/data/collaboration_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/data/sembast_collaboration_sync_store.dart';
import 'package:var_app/features/mindmap/domain/collaboration_room.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node_revision_repository.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  test('bound expense keeps local receipts but sanitizes outbox', () async {
    final db = await databaseFactoryMemory.openDatabase(
      'collaboration-expense.db',
    );
    addTearDown(db.close);
    final store = SembastCollaborationSyncStore(database: db);
    final session = ActiveCollaborationSessionState()
      ..set(
        ActiveCollaborationSession(
          roomId: 'room',
          target: CollaborationTarget.day('2026-08-11'),
          uid: 'editor',
          role: CollaborationRole.editor,
        ),
      );
    final base = InMemoryMindmapRepository();
    final repository = CollaborationMindmapRepository(
      base: base,
      store: store,
      revisionRepository: const _UnusedRevisionRepository(),
      sessionReader: session,
    );
    final bare = MindmapNode.create(
      id: 'expense',
      type: NodeType.expense,
      title: 'Taxi',
      day: DateTime(2026, 8, 11),
    );
    const receipt = ResourceAsset(
      id: 'receipt',
      kind: 'file',
      attachmentId: 'attachment',
      fileName: 'taxi.pdf',
      mimeType: 'application/pdf',
    );
    final local = bare.copyWith(
      data: const ExpensePayload(
        amount: 20,
        currency: 'USD',
        receipts: [receipt],
      ).toData(bare.data),
    );

    await repository.bindAndPublish(
      local.copyWith(
        data: const ExpensePayload(
          amount: 20,
          currency: 'USD',
        ).toData(local.data),
      ),
      session.current!,
      persistLocally: false,
    );
    await repository.saveNode(local);

    final localReceipts = ExpensePayload.fromNode(
      (await base.getNode(local.id))!,
    ).receipts;
    expect(localReceipts, hasLength(1));
    expect(localReceipts.single.attachmentId, receipt.attachmentId);
    final payload = (await store.pendingForRoom('room')).single.payload!;
    expect(
      ExpensePayload.fromNode(MindmapNode.fromJson(payload)).receipts,
      isEmpty,
    );
  });
}

final class _UnusedRevisionRepository implements MindmapNodeRevisionRepository {
  const _UnusedRevisionRepository();

  @override
  Future<void> deleteRevisions(String nodeId) async {}

  @override
  Future<MindmapNodeRevision?> getRevision(String revisionId) async => null;

  @override
  Future<List<MindmapNodeRevision>> listRevisions(
    String nodeId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<MindmapNode> restoreRevision(
    String revisionId, {
    required DateTime now,
  }) => throw UnsupportedError('Revision restore is not used in this test.');
}
