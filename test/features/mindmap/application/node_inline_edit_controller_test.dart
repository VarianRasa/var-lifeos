import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/application/node_inline_edit_controller.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';

void main() {
  group('NodeInlineEditController', () {
    test('begins one session and reports initial snapshot once', () {
      final scheduler = _ManualScheduler();
      final snapshots = <MindmapNode>[];
      final controller = NodeInlineEditController(
        save: (node) async => node,
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node, onInitialSnapshot: snapshots.add);
      controller.updateDraft(node.copyWith(title: 'First'));
      controller.updateDraft(node.copyWith(title: 'Second'));

      expect(snapshots, [node]);
      expect(controller.state.persisted, node);
      expect(controller.state.draft?.title, 'Second');
      expect(controller.state.status, NodeSaveStatus.dirty);
    });

    test('debounces autosave and saves latest draft', () async {
      final scheduler = _ManualScheduler();
      final saved = <MindmapNode>[];
      final controller = NodeInlineEditController(
        save: (node) async {
          saved.add(node);
          return node;
        },
        debounceDuration: const Duration(milliseconds: 400),
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(title: 'First'));
      controller.updateDraft(node.copyWith(title: 'Latest'));

      expect(scheduler.pendingCount, 1);
      expect(saved, isEmpty);

      await scheduler.fireLatest();

      expect(saved.single.title, 'Latest');
      expect(controller.state.status, NodeSaveStatus.saved);
      expect(controller.state.persisted?.title, 'Latest');
      expect(controller.state.draft?.title, 'Latest');
    });

    test('flush saves immediately and cancels debounce', () async {
      final scheduler = _ManualScheduler();
      final saved = <MindmapNode>[];
      final controller = NodeInlineEditController(
        save: (node) async {
          saved.add(node);
          return node;
        },
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(body: 'Draft'));
      await controller.flush();

      expect(saved.single.body, 'Draft');
      expect(scheduler.pendingCount, 0);
      expect(controller.state.status, NodeSaveStatus.saved);
    });

    test('cancel restores persisted node without saving', () async {
      final scheduler = _ManualScheduler();
      var saveCount = 0;
      final controller = NodeInlineEditController(
        save: (node) async {
          saveCount += 1;
          return node;
        },
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(title: 'Discard me'));
      await controller.cancel();

      expect(saveCount, 0);
      expect(scheduler.pendingCount, 0);
      expect(controller.state.draft, node);
      expect(controller.state.persisted, node);
      expect(controller.state.status, NodeSaveStatus.idle);
      expect(controller.state.error, isNull);
    });

    test(
      'cancel during active save compensates repository to snapshot',
      () async {
        final firstRelease = Completer<void>();
        final requests = <MindmapNode>[];
        MindmapNode? repositoryValue;
        final controller = NodeInlineEditController(
          save: (node) async {
            requests.add(node);
            if (requests.length == 1) await firstRelease.future;
            repositoryValue = node;
            return node;
          },
        );
        final original = _node();
        final draft = original.copyWith(title: 'Saved before cancel');

        repositoryValue = original;
        controller.begin(original);
        controller.updateDraft(draft);
        final flush = controller.flush();
        final cancel = controller.cancel();

        expect(requests, [draft]);
        firstRelease.complete();
        await Future.wait([flush, cancel]);

        expect(requests, [draft, original]);
        expect(repositoryValue, original);
        expect(controller.state.status, NodeSaveStatus.idle);
        expect(controller.state.persisted, original);
        expect(controller.state.draft, original);
        expect(controller.state.error, isNull);
      },
    );

    test('cancel compensation failure keeps truthful state', () async {
      final firstRelease = Completer<void>();
      var saveCount = 0;
      final controller = NodeInlineEditController(
        save: (node) async {
          saveCount += 1;
          if (saveCount == 1) {
            await firstRelease.future;
            return node;
          }
          throw StateError('compensation failed');
        },
      );
      final original = _node();
      final savedDraft = original.copyWith(title: 'Repository value');

      controller.begin(original);
      controller.updateDraft(savedDraft);
      final flush = controller.flush();
      final cancel = controller.cancel();
      firstRelease.complete();
      await Future.wait([flush, cancel]);

      expect(saveCount, 2);
      expect(controller.state.status, NodeSaveStatus.error);
      expect(controller.state.persisted, savedDraft);
      expect(controller.state.draft, original);
      expect(controller.state.error, isA<StateError>());
    });

    test('failed save retains draft and retry saves it', () async {
      final scheduler = _ManualScheduler();
      var shouldFail = true;
      final saved = <MindmapNode>[];
      final controller = NodeInlineEditController(
        save: (node) async {
          if (shouldFail) throw StateError('offline');
          saved.add(node);
          return node;
        },
        scheduler: scheduler.schedule,
      );
      final node = _node();
      final draft = node.copyWith(title: 'Keep me');

      controller.begin(node);
      controller.updateDraft(draft);
      await controller.flush();

      expect(controller.state.status, NodeSaveStatus.error);
      expect(controller.state.draft, draft);
      expect(controller.state.persisted, node);
      expect(controller.state.error, isA<StateError>());

      shouldFail = false;
      await controller.retry();

      expect(saved, [draft]);
      expect(controller.state.status, NodeSaveStatus.saved);
      expect(controller.state.persisted, draft);
      expect(controller.state.error, isNull);
    });

    test('focus loss flushes dirty draft', () async {
      final scheduler = _ManualScheduler();
      final saved = <MindmapNode>[];
      final controller = NodeInlineEditController(
        save: (node) async {
          saved.add(node);
          return node;
        },
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(title: 'Blur save'));
      await controller.onFocusLost();

      expect(saved.single.title, 'Blur save');
      expect(scheduler.pendingCount, 0);
    });

    test('schedules autosave with exact debounce duration', () {
      final scheduler = _ManualScheduler();
      final controller = NodeInlineEditController(
        save: (node) async => node,
        debounceDuration: const Duration(milliseconds: 375),
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(title: 'Debounced'));

      expect(scheduler.latestDuration, const Duration(milliseconds: 375));
    });

    test('queues latest draft while one save remains active', () async {
      final scheduler = _ManualScheduler();
      final releases = <Completer<void>>[];
      final requested = <MindmapNode>[];
      var activeSaves = 0;
      var maxActiveSaves = 0;
      final controller = NodeInlineEditController(
        save: (node) async {
          requested.add(node);
          activeSaves += 1;
          if (activeSaves > maxActiveSaves) maxActiveSaves = activeSaves;
          final release = Completer<void>();
          releases.add(release);
          await release.future;
          activeSaves -= 1;
          return node;
        },
        scheduler: scheduler.schedule,
      );
      final node = _node();
      final firstDraft = node.copyWith(title: 'First save');
      final secondDraft = node.copyWith(title: 'Typed while saving');

      controller.begin(node);
      controller.updateDraft(firstDraft);
      final firstFlush = controller.flush();
      expect(controller.state.status, NodeSaveStatus.saving);
      expect(requested, [firstDraft]);

      controller.updateDraft(secondDraft);
      final queuedFlush = controller.flush();
      final focusFlush = controller.onFocusLost();

      expect(requested, [firstDraft]);
      expect(activeSaves, 1);
      expect(maxActiveSaves, 1);

      releases.first.complete();
      await Future<void>.value();
      await Future<void>.value();

      expect(requested, [firstDraft, secondDraft]);
      expect(activeSaves, 1);
      expect(maxActiveSaves, 1);

      releases.last.complete();
      await Future.wait([firstFlush, queuedFlush, focusFlush]);

      expect(activeSaves, 0);
      expect(maxActiveSaves, 1);
      expect(controller.state.persisted, secondDraft);
      expect(controller.state.draft, secondDraft);
      expect(controller.state.status, NodeSaveStatus.saved);
    });

    test('dispose cancels pending autosave', () {
      final scheduler = _ManualScheduler();
      final controller = NodeInlineEditController(
        save: (node) async => node,
        scheduler: scheduler.schedule,
      );
      final node = _node();

      controller.begin(node);
      controller.updateDraft(node.copyWith(title: 'Pending'));
      controller.dispose();

      expect(scheduler.pendingCount, 0);
    });

    test(
      'dispose during active save ignores completion and queued draft',
      () async {
        final release = Completer<void>();
        var saveCount = 0;
        final controller = NodeInlineEditController(
          save: (node) async {
            saveCount += 1;
            await release.future;
            return node;
          },
        );
        final node = _node();

        controller.begin(node);
        controller.updateDraft(node.copyWith(title: 'Saving'));
        final flush = controller.flush();
        controller.updateDraft(node.copyWith(title: 'Queued'));

        controller.dispose();
        release.complete();

        await expectLater(flush, completes);
        await Future<void>.value();
        expect(saveCount, 1);
      },
    );

    test('new session is blocked until old save succeeds', () async {
      final release = Completer<void>();
      final controller = NodeInlineEditController(
        save: (node) async {
          await release.future;
          return node;
        },
      );
      final oldNode = _node();
      final newNode = _node(id: 'node-2');

      controller.begin(oldNode);
      controller.updateDraft(oldNode.copyWith(title: 'Old saving'));
      final flush = controller.flush();

      expect(() => controller.begin(newNode), throwsStateError);
      release.complete();
      await flush;

      controller.begin(newNode);
      expect(controller.state.persisted, newNode);
      expect(controller.state.draft, newNode);
    });

    test('new session is isolated after old save failure', () async {
      final release = Completer<void>();
      final controller = NodeInlineEditController(
        save: (node) async {
          await release.future;
          throw StateError('old save failed');
        },
      );
      final oldNode = _node();
      final newNode = _node(id: 'node-2');

      controller.begin(oldNode);
      controller.updateDraft(oldNode.copyWith(title: 'Old failing'));
      final flush = controller.flush();

      expect(() => controller.begin(newNode), throwsStateError);
      release.complete();
      await flush;
      expect(controller.state.status, NodeSaveStatus.error);

      controller.begin(newNode);
      expect(controller.state.status, NodeSaveStatus.idle);
      expect(controller.state.persisted, newNode);
      expect(controller.state.draft, newNode);
      expect(controller.state.error, isNull);
    });

    test('rejects draft belonging to another node', () {
      final controller = NodeInlineEditController(save: (node) async => node);
      controller.begin(_node());

      expect(
        () => controller.updateDraft(_node(id: 'other')),
        throwsArgumentError,
      );
    });
  });
}

MindmapNode _node({String id = 'node-1'}) {
  final timestamp = DateTime(2026, 7, 13, 10);
  return MindmapNode.create(
    id: id,
    type: NodeType.note,
    title: 'Original',
    day: DateTime(2026, 7, 13),
    now: timestamp,
  );
}

final class _ManualScheduler {
  final List<_ManualScheduledTask> _tasks = [];

  int get pendingCount => _tasks.where((task) => !task.isCancelled).length;

  Duration? get latestDuration {
    return _tasks.isEmpty ? null : _tasks.last.duration;
  }

  NodeInlineEditTimer schedule(
    Duration duration,
    FutureOr<void> Function() run,
  ) {
    final task = _ManualScheduledTask(duration, run);
    _tasks.add(task);
    return task;
  }

  Future<void> fireLatest() async {
    final task = _tasks.lastWhere((candidate) => !candidate.isCancelled);
    task.isCancelled = true;
    await task.run();
  }
}

final class _ManualScheduledTask implements NodeInlineEditTimer {
  _ManualScheduledTask(this.duration, this.run);

  final Duration duration;
  final FutureOr<void> Function() run;
  bool isCancelled = false;

  @override
  void cancel() {
    isCancelled = true;
  }
}
