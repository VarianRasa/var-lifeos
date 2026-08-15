import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/data/sembast_drawing_draft_store.dart';
import 'package:var_app/features/mindmap/domain/drawing_draft_checkpoint.dart';

void main() {
  test('survives reopen and rejects stale writes and deletes', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'drawing-drafts.db',
    );
    final first = SembastDrawingDraftStore(database: database);
    await first.putIfNewer(_checkpoint(2));

    final reopened = SembastDrawingDraftStore(database: database);
    expect((await reopened.get('canvas-1'))?.generation, 2);
    expect(await reopened.putIfNewer(_checkpoint(1)), isFalse);
    expect(await reopened.deleteIfGeneration('canvas-1', 1), isFalse);
    expect((await reopened.list()).single.generation, 2);
    expect(await reopened.deleteIfGeneration('canvas-1', 2), isTrue);
    expect(await reopened.get('canvas-1'), isNull);

    await database.close();
  });
}

DrawingDraftCheckpoint _checkpoint(int generation) => DrawingDraftCheckpoint(
  nodeId: 'canvas-1',
  baseUpdatedAt: DateTime.utc(2026, 7, 28, 9),
  generation: generation,
  data: <String, Object?>{
    'canvas': <String, Object?>{
      'schemaVersion': 1,
      'background': 'plain',
      'elements': <Object?>[],
      'activeTool': 'select',
      'penColor': 'violet',
      'penWidth': 3.0,
      'blocks': <String, Object?>{},
      'viewMode': 'visual',
    },
  },
  updatedAt: DateTime.utc(2026, 7, 28, 10, generation),
);
