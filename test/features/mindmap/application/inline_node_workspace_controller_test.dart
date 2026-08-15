import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/inline_node_workspace_controller.dart';
import 'package:var_app/features/mindmap/application/mindmap_providers.dart';
import 'package:var_app/features/mindmap/data/in_memory_mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/mindmap_repository.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/inline_node_workspace.dart';

void main() {
  test('typing burst coalesces into one save with latest draft', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );

    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'A'));
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'AB'));
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'ABC'));
    await scheduler.runLatest();

    expect(repository.saveCount, 1);
    expect((await repository.getNode('one'))!.title, 'ABC');
    expect(controller.state.nodes['one']!.status, InlineNodeSaveStatus.saved);
  });

  test('resource draft autosaves before primary asset exists', () async {
    final scheduler = _ManualScheduler();
    final base = _node('resource', type: NodeType.resource);
    final repository = _CountingRepository(seedNodes: <MindmapNode>[base]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion(base.id);
    const payload = ResourcePayload(
      description: 'Draft description',
      folders: <ResourceFolder>[
        ResourceFolder(id: 'research', name: 'Research'),
      ],
      folderPath: <String>['Research'],
    );

    controller.updateDraft(
      base.id,
      InlineNodeDraftPatch.between(base, payload.toNode(base)),
    );
    await scheduler.runLatest();

    expect(repository.saveCount, 1);
    final saved = await repository.getNode(base.id);
    expect(ResourcePayload.fromNode(saved!).description, 'Draft description');
    expect(ResourcePayload.fromNode(saved).folders.single.name, 'Research');
    expect(controller.state.nodes[base.id]!.status, InlineNodeSaveStatus.saved);
  });

  test('itinerary without destination autosaves and collapses', () async {
    final scheduler = _ManualScheduler();
    final base = _node('itinerary', type: NodeType.itinerary);
    final repository = _CountingRepository(seedNodes: <MindmapNode>[base]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion(base.id);
    final payload = ItineraryPayload.fromNode(
      base,
    ).copyWith(transport: 'Train');
    final draft = base.copyWith(data: payload.toData(base.data));

    controller.updateDraft(base.id, InlineNodeDraftPatch.between(base, draft));

    expect(await controller.requestExpansion(null), isTrue);
    expect(repository.saveCount, 1);
    expect(controller.state.expandedNodeId, isNull);
    final saved = await repository.getNode(base.id);
    expect(ItineraryPayload.fromNode(saved!).destination, isEmpty);
    expect(ItineraryPayload.fromNode(saved).transport, 'Train');
  });

  test('one flush boundary waits for edit-during-save follow-up', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'First'));
    repository.holdNextSave();

    var completed = false;
    final boundary = controller.flush('one').then((value) {
      completed = true;
      return value;
    });
    await repository.saveStarted.future;
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'Second'));
    repository.holdNextSave();
    repository.completeSave();
    await repository.saveStarted.future;

    expect(completed, isFalse);
    repository.completeSave();
    expect(await boundary, isTrue);
    expect(repository.saveCount, 2);
    expect((await repository.getNode('one'))!.title, 'Second');
    expect(controller.state.nodes['one']!.status, InlineNodeSaveStatus.saved);
  });

  test('same-node reselect preserves dirty draft and generation', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'Draft'));
    final before = controller.state.nodes['one']!;

    expect(await controller.requestExpansion('one'), isTrue);

    final after = controller.state.nodes['one']!;
    expect(after.draft.title, 'Draft');
    expect(after.generation, before.generation);
    expect(after.status, InlineNodeSaveStatus.dirty);
  });

  test('missing node is discarded and collapsed during flush', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'Draft'));
    await repository.deleteNode('one');

    expect(await controller.flush('one'), isFalse);
    expect(controller.state.expandedNodeId, isNull);
    expect(controller.state.nodes, isNot(contains('one')));
    expect(scheduler.hasPending, isFalse);
  });

  test('save error keeps draft and retry succeeds', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'Retry'));
    repository.failNextSave();

    expect(await controller.flush('one'), isFalse);
    expect(controller.state.nodes['one']!.draft.title, 'Retry');
    expect(controller.state.nodes['one']!.status, InlineNodeSaveStatus.error);
    expect(await controller.flush('one'), isTrue);
    expect((await repository.getNode('one'))!.title, 'Retry');
  });

  for (final invalid in <({NodeType type, Map<String, Object?> data})>[
    (type: NodeType.link, data: const {'url': 'not-a-url'}),
    (type: NodeType.metric, data: const {'value': 'NaN'}),
    (
      type: NodeType.event,
      data: const {'startDate': '2026-02-30', 'endDate': '2026-03-01'},
    ),
  ]) {
    test(
      'invalid typed payload blocks flush for ${invalid.type.name}',
      () async {
        final scheduler = _ManualScheduler();
        final repository = _CountingRepository(
          seedNodes: [_node('one', type: invalid.type, data: invalid.data)],
        );
        final container = _container(repository, scheduler);
        addTearDown(container.dispose);
        final controller = container.read(
          inlineNodeWorkspaceControllerProvider.notifier,
        );
        await controller.requestExpansion('one');

        controller.updateDraft(
          'one',
          InlineNodeDraftPatch(title: 'Changed', dataFields: invalid.data),
        );

        expect(await controller.flush('one'), isFalse);
        expect(
          controller.state.nodes['one']!.status,
          InlineNodeSaveStatus.error,
        );
        expect(controller.state.nodes['one']!.error, isA<String>());
        expect(repository.saveCount, 0);
      },
    );
  }

  test('partial bookmark URL waits then autosaves when valid', () async {
    final scheduler = _ManualScheduler();
    final base = _node('bookmark', type: NodeType.bookmark);
    final repository = _CountingRepository(seedNodes: <MindmapNode>[base]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion(base.id);

    controller.updateDraft(
      base.id,
      InlineNodeDraftPatch(dataFields: <String, Object?>{'url': 'f'}),
    );

    expect(controller.state.nodes[base.id]!.status, InlineNodeSaveStatus.error);
    expect(controller.state.nodes[base.id]!.error, isA<String>());
    expect(scheduler.hasPending, isFalse);
    expect(repository.saveCount, 0);

    controller.updateDraft(
      base.id,
      InlineNodeDraftPatch(
        dataFields: <String, Object?>{'url': 'https://example.com'},
      ),
    );
    expect(scheduler.hasPending, isTrue);
    await scheduler.runLatest();

    expect(repository.saveCount, 1);
    expect(
      LinkResourcePayload.fromNode((await repository.getNode(base.id))!).url,
      'https://example.com',
    );
    expect(controller.state.nodes[base.id]!.status, InlineNodeSaveStatus.saved);
  });

  test('transaction mutates existing non-expanded node', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(
      seedNodes: [_node('one'), _node('two')],
    );
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');

    final changed = await controller.flushThenMutateLatest('two', (
      latest,
    ) async {
      await repository.saveNode(latest.copyWith(project: 'new'));
    });

    expect(changed, isTrue);
    expect((await repository.getNode('two'))!.project, 'new');
    expect(controller.state.nodes.containsKey('two'), isFalse);
  });

  test('failed flush blocks expansion transition', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(
      seedNodes: [_node('one'), _node('two')],
    );
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: ''));

    final changed = await controller.requestExpansion('two');

    expect(changed, isFalse);
    expect(controller.state.expandedNodeId, 'one');
    expect(controller.state.nodes['one']!.status, InlineNodeSaveStatus.error);
  });

  test('mutation rebases workspace before following edit', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(seedNodes: [_node('one')]);
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');

    expect(
      await controller.flushThenMutateLatest('one', (latest) async {
        await repository.saveNode(
          latest.copyWith(
            type: NodeType.task,
            data: const {'action': 'converted'},
          ),
        );
      }),
      isTrue,
    );
    expect(controller.state.nodes['one']!.draft.type, NodeType.task);
    expect(controller.state.nodes['one']!.draft.data['action'], 'converted');

    controller.updateDraft('one', InlineNodeDraftPatch(title: 'After action'));
    expect(await controller.flush('one'), isTrue);
    final saved = await repository.getNode('one');
    expect(saved!.title, 'After action');
    expect(saved.type, NodeType.task);
    expect(saved.data['action'], 'converted');
  });

  test(
    'stale save completion cannot replace newly expanded workspace',
    () async {
      final scheduler = _ManualScheduler();
      final repository = _CountingRepository(
        seedNodes: [_node('one'), _node('two')],
      );
      final container = _container(repository, scheduler);
      addTearDown(container.dispose);
      final controller = container.read(
        inlineNodeWorkspaceControllerProvider.notifier,
      );
      await controller.requestExpansion('one');
      controller.updateDraft('one', InlineNodeDraftPatch(title: 'Old save'));
      repository.holdNextSave();
      final transition = controller.requestExpansion('two');
      await repository.saveStarted.future;
      repository.completeSave();
      expect(await transition, isTrue);
      expect(controller.state.expandedNodeId, 'two');
      expect(controller.state.nodes['two']!.draft.title, 'two');
    },
  );

  test('latest expansion request wins while flush is pending', () async {
    final scheduler = _ManualScheduler();
    final repository = _CountingRepository(
      seedNodes: [_node('one'), _node('two'), _node('three')],
    );
    final container = _container(repository, scheduler);
    addTearDown(container.dispose);
    final controller = container.read(
      inlineNodeWorkspaceControllerProvider.notifier,
    );
    await controller.requestExpansion('one');
    controller.updateDraft('one', InlineNodeDraftPatch(title: 'Saved'));
    repository.holdNextSave();

    final toTwo = controller.requestExpansion('two');
    await repository.saveStarted.future;
    final toThree = controller.requestExpansion('three');
    repository.completeSave();

    expect(await toTwo, isFalse);
    expect(await toThree, isTrue);
    expect(controller.state.expandedNodeId, 'three');
  });
}

ProviderContainer _container(
  _CountingRepository repository,
  _ManualScheduler scheduler,
) => ProviderContainer(
  overrides: [
    mindmapRepositoryProvider.overrideWithValue(repository),
    inlineNodeAutosaveSchedulerProvider.overrideWithValue(scheduler.schedule),
    inlineNodeAutosaveClockProvider.overrideWithValue(
      () => DateTime(2026, 7, 15),
    ),
  ],
);

MindmapNode _node(
  String id, {
  NodeType type = NodeType.note,
  Map<String, Object?> data = const {},
}) => MindmapNode.create(
  id: id,
  type: type,
  title: id,
  day: DateTime(2026, 7, 15),
  now: DateTime(2026, 7, 15),
).copyWith(data: data);

final class _ManualScheduler {
  void Function()? _callback;

  bool get hasPending => _callback != null;

  void Function() schedule(Duration _, void Function() callback) {
    _callback = callback;
    return () {
      if (identical(_callback, callback)) _callback = null;
    };
  }

  Future<void> runLatest() async {
    final callback = _callback;
    _callback = null;
    callback?.call();
    await Future<void>.delayed(Duration.zero);
  }
}

final class _CountingRepository implements MindmapRepository {
  _CountingRepository({required Iterable<MindmapNode> seedNodes})
    : _delegate = InMemoryMindmapRepository(seedNodes: seedNodes);

  final InMemoryMindmapRepository _delegate;

  int saveCount = 0;
  final List<Completer<void>> _gates = [];
  final List<Completer<void>> _activeGates = [];
  final List<Completer<void>> _saveStarts = [];
  Completer<void> saveStarted = Completer<void>();
  bool _failNextSave = false;

  void holdNextSave() {
    final gate = Completer<void>();
    final started = Completer<void>();
    _gates.add(gate);
    _saveStarts.add(started);
    saveStarted = started;
  }

  void completeSave() => _activeGates.removeAt(0).complete();

  void failNextSave() => _failNextSave = true;

  @override
  Future<MindmapNode> saveNode(MindmapNode node) async {
    saveCount++;
    if (_failNextSave) {
      _failNextSave = false;
      throw StateError('save failed');
    }
    final gate = _gates.isEmpty ? null : _gates.removeAt(0);
    final started = _saveStarts.isEmpty ? null : _saveStarts.removeAt(0);
    if (gate != null) {
      _activeGates.add(gate);
      if (started != null && !started.isCompleted) started.complete();
      await gate.future;
    }
    return _delegate.saveNode(node);
  }

  @override
  Future<void> deleteNode(String id) => _delegate.deleteNode(id);

  @override
  Future<MindmapNode?> getNode(String id) => _delegate.getNode(id);

  @override
  Future<List<MindmapNode>> listNodes({DateTime? day}) =>
      _delegate.listNodes(day: day);

  @override
  Future<List<MindmapNode>> searchNodes(String query) =>
      _delegate.searchNodes(query);
}
