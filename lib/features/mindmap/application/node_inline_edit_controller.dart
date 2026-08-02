/// Inline edit session state and autosave orchestration for mindmap nodes.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/mindmap_node.dart';

enum NodeSaveStatus { idle, dirty, saving, saved, error }

final class NodeInlineEditState {
  const NodeInlineEditState({
    this.status = NodeSaveStatus.idle,
    this.persisted,
    this.draft,
    this.error,
  });

  final NodeSaveStatus status;
  final MindmapNode? persisted;
  final MindmapNode? draft;
  final Object? error;

  bool get hasSession => persisted != null && draft != null;
}

abstract interface class NodeInlineEditTimer {
  void cancel();
}

typedef NodeInlineEditSave = Future<MindmapNode> Function(MindmapNode node);
typedef NodeInlineEditSchedule =
    NodeInlineEditTimer Function(
      Duration duration,
      FutureOr<void> Function() callback,
    );

final class NodeInlineEditController
    extends StateNotifier<NodeInlineEditState> {
  NodeInlineEditController({
    required NodeInlineEditSave save,
    Duration debounceDuration = const Duration(milliseconds: 500),
    NodeInlineEditSchedule? scheduler,
  }) : _save = save,
       _debounceDuration = debounceDuration,
       _scheduler = scheduler ?? _scheduleTimer,
       super(const NodeInlineEditState());

  final NodeInlineEditSave _save;
  final Duration _debounceDuration;
  final NodeInlineEditSchedule _scheduler;

  NodeInlineEditTimer? _timer;
  Future<void>? _saveLoop;
  Future<void>? _cancelOperation;
  MindmapNode? _initialSnapshot;
  var _cancelRequested = false;
  var _disposed = false;
  var _sessionRevision = 0;

  void begin(
    MindmapNode node, {
    void Function(MindmapNode snapshot)? onInitialSnapshot,
  }) {
    if (_disposed) return;
    if (_saveLoop != null || _cancelOperation != null) {
      throw StateError(
        'Cannot begin a new inline edit session while saving or cancelling.',
      );
    }
    _cancelTimer();
    _sessionRevision += 1;
    _initialSnapshot = node;
    onInitialSnapshot?.call(node);
    state = NodeInlineEditState(persisted: node, draft: node);
  }

  void updateDraft(MindmapNode draft) {
    if (_disposed) return;
    final persisted = state.persisted;
    if (persisted == null) {
      throw StateError('Begin an inline edit session before updating draft.');
    }
    if (draft.id != persisted.id) {
      throw ArgumentError.value(
        draft.id,
        'draft.id',
        'Draft must belong to the active node ${persisted.id}.',
      );
    }

    final wasSaving = state.status == NodeSaveStatus.saving;
    final isDirty = draft != persisted;
    state = NodeInlineEditState(
      status: isDirty ? NodeSaveStatus.dirty : NodeSaveStatus.idle,
      persisted: persisted,
      draft: draft,
    );
    _cancelTimer();
    if (isDirty && !wasSaving) _scheduleAutosave();
  }

  Future<void> flush() {
    if (_disposed) return Future.value();
    final cancelOperation = _cancelOperation;
    if (cancelOperation != null) return cancelOperation;
    _cancelTimer();
    final activeLoop = _saveLoop;
    if (activeLoop != null) return activeLoop;

    final persisted = state.persisted;
    final draft = state.draft;
    if (persisted == null || draft == null || draft == persisted) {
      return Future.value();
    }

    late final Future<void> loop;
    loop = _runSaveLoop().whenComplete(() {
      if (identical(_saveLoop, loop)) _saveLoop = null;
    });
    _saveLoop = loop;
    return loop;
  }

  Future<void> _runSaveLoop() async {
    while (true) {
      if (_disposed) return;
      final persisted = state.persisted;
      final draft = state.draft;
      if (persisted == null || draft == null || draft == persisted) return;

      final sessionRevision = _sessionRevision;
      final savingDraft = draft;
      if (_disposed) return;
      state = NodeInlineEditState(
        status: NodeSaveStatus.saving,
        persisted: persisted,
        draft: draft,
      );

      try {
        if (_disposed) return;
        final saved = await _save(savingDraft);
        if (_disposed) return;
        if (sessionRevision != _sessionRevision) continue;

        final latestDraft = state.draft;
        if (_cancelRequested) {
          state = NodeInlineEditState(
            status: latestDraft == saved
                ? NodeSaveStatus.saved
                : NodeSaveStatus.dirty,
            persisted: saved,
            draft: latestDraft ?? savingDraft,
          );
          return;
        }
        if (latestDraft == null || latestDraft == savingDraft) {
          if (_disposed) return;
          state = NodeInlineEditState(
            status: NodeSaveStatus.saved,
            persisted: saved,
            draft: saved,
          );
          return;
        }

        if (_disposed) return;
        state = NodeInlineEditState(
          status: NodeSaveStatus.dirty,
          persisted: saved,
          draft: latestDraft,
        );
      } catch (error) {
        if (_disposed) return;
        if (sessionRevision != _sessionRevision) continue;
        state = NodeInlineEditState(
          status: NodeSaveStatus.error,
          persisted: persisted,
          draft: state.draft ?? savingDraft,
          error: error,
        );
        return;
      }
    }
  }

  Future<void> retry() => flush();

  Future<void> onFocusLost() => flush();

  Future<void> cancel() {
    if (_disposed) return Future.value();
    final existing = _cancelOperation;
    if (existing != null) return existing;

    _cancelTimer();
    _cancelRequested = true;
    late final Future<void> operation;
    operation = _cancelSession().whenComplete(() {
      _cancelRequested = false;
      if (identical(_cancelOperation, operation)) _cancelOperation = null;
    });
    _cancelOperation = operation;
    return operation;
  }

  Future<void> _cancelSession() async {
    final initialSnapshot = _initialSnapshot;
    final activeSave = _saveLoop;
    if (initialSnapshot == null) return;

    if (activeSave != null) await activeSave;
    if (_disposed) return;

    final repositoryValue = state.persisted ?? initialSnapshot;
    final needsCompensation =
        activeSave != null || repositoryValue != initialSnapshot;
    if (!needsCompensation) {
      _sessionRevision += 1;
      state = NodeInlineEditState(
        persisted: initialSnapshot,
        draft: initialSnapshot,
      );
      return;
    }

    state = NodeInlineEditState(
      status: NodeSaveStatus.saving,
      persisted: repositoryValue,
      draft: initialSnapshot,
    );
    try {
      final restored = await _save(initialSnapshot);
      if (_disposed) return;
      _sessionRevision += 1;
      state = NodeInlineEditState(persisted: restored, draft: restored);
    } catch (error) {
      if (_disposed) return;
      state = NodeInlineEditState(
        status: NodeSaveStatus.error,
        persisted: repositoryValue,
        draft: initialSnapshot,
        error: error,
      );
    }
  }

  void _scheduleAutosave() {
    _timer = _scheduler(_debounceDuration, () => flush());
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    _cancelTimer();
    _sessionRevision += 1;
    super.dispose();
  }
}

NodeInlineEditTimer _scheduleTimer(
  Duration duration,
  FutureOr<void> Function() callback,
) {
  return _DartNodeInlineEditTimer(duration, callback);
}

final class _DartNodeInlineEditTimer implements NodeInlineEditTimer {
  _DartNodeInlineEditTimer(
    Duration duration,
    FutureOr<void> Function() callback,
  ) : _timer = Timer(duration, () {
        final result = callback();
        if (result is Future<void>) unawaited(result);
      });

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
