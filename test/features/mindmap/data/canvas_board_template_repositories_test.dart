import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:var_app/features/mindmap/data/canvas_board_template_repositories.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template.dart';
import 'package:var_app/features/mindmap/domain/canvas_board_template_repository.dart';

void main() {
  final earlier = DateTime.utc(2026, 8, 1);
  final later = DateTime.utc(2026, 8, 2);

  CanvasBoardTemplate template(
    String id, {
    required String name,
    required DateTime updatedAt,
  }) => CanvasBoardTemplate(
    id: id,
    name: name,
    sourceBoardId: 'board-$id',
    createdAt: earlier,
    updatedAt: updatedAt,
  );

  Future<void> verifyContract(CanvasBoardTemplateRepository repository) async {
    await repository.saveTemplate(
      template('b', name: 'Beta', updatedAt: earlier),
    );
    await repository.saveTemplate(
      template('c', name: 'Charlie', updatedAt: later),
    );
    await repository.saveTemplate(
      template('a', name: 'Alpha', updatedAt: later),
    );

    expect((await repository.listTemplates()).map((item) => item.id), <String>[
      'a',
      'c',
      'b',
    ]);

    final renamed = CanvasBoardTemplate(
      id: 'a',
      name: 'Renamed',
      sourceBoardId: 'board-a',
      createdAt: earlier,
      updatedAt: later,
    );
    await repository.saveTemplate(renamed);

    final afterRename = await repository.listTemplates();
    expect(afterRename.where((item) => item.id == 'a'), <CanvasBoardTemplate>[
      renamed,
    ]);

    await repository.deleteTemplate('c');
    expect((await repository.listTemplates()).map((item) => item.id), <String>[
      'a',
      'b',
    ]);
  }

  test('in-memory repository follows template contract', () async {
    await verifyContract(InMemoryCanvasBoardTemplateRepository());
  });

  test('Sembast repository follows template contract', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-board-template-contract.db',
    );
    await verifyContract(
      SembastCanvasBoardTemplateRepository(database: database),
    );
    await database.close();
  });

  Future<void> verifyAtomicRenameContract(
    CanvasBoardTemplateRepository repository,
  ) async {
    final original = template('rename', name: 'Original', updatedAt: earlier);
    await repository.saveTemplate(original);
    final concurrent = await repository.renameTemplate(
      templateId: original.id,
      expectedUpdatedAt: earlier,
      name: 'First rename',
      updatedAt: later,
    );

    await expectLater(
      repository.renameTemplate(
        templateId: original.id,
        expectedUpdatedAt: earlier,
        name: 'Stale rename',
        updatedAt: later.add(const Duration(minutes: 1)),
      ),
      throwsStateError,
    );
    expect(await repository.listTemplates(), <CanvasBoardTemplate>[concurrent]);

    await repository.deleteTemplate(original.id);
    await expectLater(
      repository.renameTemplate(
        templateId: original.id,
        expectedUpdatedAt: concurrent.updatedAt,
        name: 'Resurrected',
        updatedAt: later.add(const Duration(minutes: 2)),
      ),
      throwsStateError,
    );
    expect(await repository.listTemplates(), isEmpty);
  }

  test('in-memory rename is atomic against update and delete', () async {
    await verifyAtomicRenameContract(InMemoryCanvasBoardTemplateRepository());
  });

  test('Sembast rename is atomic against update and delete', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-board-template-rename.db',
    );
    addTearDown(database.close);
    await verifyAtomicRenameContract(
      SembastCanvasBoardTemplateRepository(database: database),
    );
  });

  test('repositories delete missing IDs idempotently', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-board-template-delete-missing.db',
    );
    final repositories = <CanvasBoardTemplateRepository>[
      InMemoryCanvasBoardTemplateRepository(),
      SembastCanvasBoardTemplateRepository(database: database),
    ];

    for (final repository in repositories) {
      await repository.deleteTemplate('missing');
      await repository.deleteTemplate('missing');
      expect(await repository.listTemplates(), isEmpty);
    }
    await database.close();
  });

  test(
    'repositories use identical deterministic equal-time ordering',
    () async {
      final database = await databaseFactoryMemory.openDatabase(
        'canvas-board-template-ordering.db',
      );
      final repositories = <CanvasBoardTemplateRepository>[
        InMemoryCanvasBoardTemplateRepository(),
        SembastCanvasBoardTemplateRepository(database: database),
      ];

      for (final repository in repositories) {
        await repository.saveTemplate(
          template('z', name: 'Zulu', updatedAt: later),
        );
        await repository.saveTemplate(
          template('a', name: 'Alpha', updatedAt: later),
        );
        expect(
          (await repository.listTemplates()).map((item) => item.id),
          <String>['a', 'z'],
        );
      }
      await database.close();
    },
  );

  test('Sembast repository accepts asynchronous database source', () async {
    final databaseFuture = databaseFactoryMemory.openDatabase(
      'canvas-board-template-async.db',
    );
    final repository = SembastCanvasBoardTemplateRepository(
      database: databaseFuture,
    );
    final valid = template('valid', name: 'Valid', updatedAt: later);

    await repository.saveTemplate(valid);

    expect(await repository.listTemplates(), <CanvasBoardTemplate>[valid]);
    await (await databaseFuture).close();
  });

  test('Sembast repository skips records whose key and ID differ', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-board-template-key-mismatch.db',
    );
    final store = stringMapStoreFactory.store('canvas_board_templates');
    final mismatched = template('payload-id', name: 'Bad', updatedAt: later);
    await store.record('record-key').put(database, mismatched.toJson());

    final repository = SembastCanvasBoardTemplateRepository(database: database);

    expect(await repository.listTemplates(), isEmpty);
    await database.close();
  });

  test('Sembast repository skips malformed fields and dates', () async {
    final database = await databaseFactoryMemory.openDatabase(
      'canvas-board-template-malformed.db',
    );
    final store = stringMapStoreFactory.store('canvas_board_templates');
    await store.record('missing-fields').put(database, <String, Object?>{
      'id': 'missing-fields',
      'name': 'Broken',
    });
    await store.record('wrong-field-type').put(database, <String, Object?>{
      'id': 'wrong-field-type',
      'name': 7,
      'sourceBoardId': 'board',
      'createdAt': earlier.toIso8601String(),
      'updatedAt': later.toIso8601String(),
    });
    await store.record('invalid-date').put(database, <String, Object?>{
      'id': 'invalid-date',
      'name': 'Broken date',
      'sourceBoardId': 'board',
      'createdAt': 'not-a-date',
      'updatedAt': later.toIso8601String(),
    });
    final valid = template('valid', name: 'Valid', updatedAt: later);
    await store.record(valid.id).put(database, valid.toJson());

    final repository = SembastCanvasBoardTemplateRepository(database: database);
    expect(await repository.listTemplates(), <CanvasBoardTemplate>[valid]);
    await database.close();
  });
}
