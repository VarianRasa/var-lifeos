import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../domain/inline_node_workspace_policy.dart';
import '../domain/mindmap_node.dart';
import '../domain/node_type_payloads.dart';
import '../domain/node_validation.dart';
import '../presentation/inline_node_workspace.dart';
import 'mindmap_mutation_controller.dart';
import 'mindmap_providers.dart';

typedef InlineNodeAutosaveScheduler =
    void Function() Function(Duration delay, void Function() callback);

final inlineNodeAutosaveSchedulerProvider =
    Provider<InlineNodeAutosaveScheduler>((ref) {
      return (delay, callback) {
        final timer = Timer(delay, callback);
        return timer.cancel;
      };
    });

final inlineNodeAutosaveClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

final inlineNodeWorkspaceControllerProvider =
    NotifierProvider<InlineNodeWorkspaceController, InlineNodeWorkspaceState>(
      InlineNodeWorkspaceController.new,
    );

final class InlineNodeWorkspaceState {
  const InlineNodeWorkspaceState({
    this.expandedNodeId,
    this.nodes = const <String, InlineNodeDraftState>{},
    this.transitionGeneration = 0,
    this.isFlushing = false,
  });

  final String? expandedNodeId;
  final Map<String, InlineNodeDraftState> nodes;
  final int transitionGeneration;
  final bool isFlushing;

  InlineNodeWorkspaceState copyWith({
    String? expandedNodeId,
    bool clearExpandedNodeId = false,
    Map<String, InlineNodeDraftState>? nodes,
    int? transitionGeneration,
    bool? isFlushing,
  }) => InlineNodeWorkspaceState(
    expandedNodeId: clearExpandedNodeId
        ? null
        : expandedNodeId ?? this.expandedNodeId,
    nodes: Map<String, InlineNodeDraftState>.unmodifiable(nodes ?? this.nodes),
    transitionGeneration: transitionGeneration ?? this.transitionGeneration,
    isFlushing: isFlushing ?? this.isFlushing,
  );
}

final class InlineNodeDraftState {
  const InlineNodeDraftState({
    required this.base,
    required this.draft,
    required this.patch,
    required this.status,
    required this.generation,
    this.error,
  });

  final MindmapNode base;
  final MindmapNode draft;
  final InlineNodeDraftPatch patch;
  final InlineNodeSaveStatus status;
  final int generation;
  final Object? error;

  InlineNodeDraftState copyWith({
    MindmapNode? base,
    MindmapNode? draft,
    InlineNodeDraftPatch? patch,
    InlineNodeSaveStatus? status,
    int? generation,
    Object? error,
    bool clearError = false,
  }) => InlineNodeDraftState(
    base: base ?? this.base,
    draft: draft ?? this.draft,
    patch: patch ?? this.patch,
    status: status ?? this.status,
    generation: generation ?? this.generation,
    error: clearError ? null : error ?? this.error,
  );
}

final class InlineNodeWorkspaceController
    extends Notifier<InlineNodeWorkspaceState> {
  static const debounceDuration = Duration(milliseconds: 450);

  final Map<String, void Function()> _cancelScheduledFlushes = {};
  final Map<String, Future<void>> _nodeTransactions = {};

  @override
  InlineNodeWorkspaceState build() {
    ref.onDispose(() {
      for (final cancel in _cancelScheduledFlushes.values) {
        cancel();
      }
    });
    return const InlineNodeWorkspaceState();
  }

  Future<bool> requestExpansion(String? nextNodeId) async {
    final requestGeneration = state.transitionGeneration + 1;
    state = state.copyWith(transitionGeneration: requestGeneration);
    final currentNodeId = state.expandedNodeId;
    if (currentNodeId == nextNodeId &&
        (nextNodeId == null || state.nodes.containsKey(nextNodeId))) {
      return true;
    }
    if (currentNodeId != null && currentNodeId != nextNodeId) {
      if (!await _flushForTransition(currentNodeId)) return false;
    }
    if (state.transitionGeneration != requestGeneration) return false;
    if (nextNodeId == null) {
      state = state.copyWith(clearExpandedNodeId: true);
      return true;
    }
    final latest = await ref
        .read(mindmapRepositoryProvider)
        .getNode(nextNodeId);
    if (state.transitionGeneration != requestGeneration) return false;
    if (latest == null) return false;
    final nodes = <String, InlineNodeDraftState>{...state.nodes};
    nodes[nextNodeId] = InlineNodeDraftState(
      base: latest,
      draft: latest,
      patch: InlineNodeDraftPatch(),
      status: InlineNodeSaveStatus.idle,
      generation: 0,
    );
    state = state.copyWith(expandedNodeId: nextNodeId, nodes: nodes);
    return true;
  }

  Future<bool> _flushForTransition(String nodeId) => flush(nodeId);

  void updateDraft(String nodeId, InlineNodeDraftPatch change) {
    final current = state.nodes[nodeId];
    if (current == null) return;
    final draft = change.mergeInto(
      current.draft,
      ref.read(inlineNodeAutosaveClockProvider)(),
    );
    final generation = current.generation + 1;
    final validationError = _validationError(draft);
    final isValid = validationError == null;
    final nodes = <String, InlineNodeDraftState>{...state.nodes};
    nodes[nodeId] = current.copyWith(
      draft: draft,
      patch: InlineNodeDraftPatch.between(current.base, draft),
      status: isValid ? InlineNodeSaveStatus.dirty : InlineNodeSaveStatus.error,
      generation: generation,
      error: validationError,
      clearError: isValid,
    );
    state = state.copyWith(nodes: nodes);
    _cancelScheduledFlushes.remove(nodeId)?.call();
    if (!isValid) {
      return;
    }
    _scheduleFlush(nodeId);
  }

  Future<bool> flush([String? nodeId]) {
    final targetNodeId = nodeId ?? state.expandedNodeId;
    if (targetNodeId == null) return Future<bool>.value(true);
    return _serialize(targetNodeId, () => _flushUntilClean(targetNodeId));
  }

  Future<bool> flushThenMutateLatest(
    String nodeId,
    Future<void> Function(MindmapNode latest) mutation,
  ) => _serialize(nodeId, () async {
    if (state.nodes.containsKey(nodeId) && !await _flushUntilClean(nodeId)) {
      return false;
    }
    final latest = await ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (latest == null) {
      discardMissingNode(nodeId);
      return false;
    }
    await mutation(latest);
    final mutated = await ref.read(mindmapRepositoryProvider).getNode(nodeId);
    if (mutated == null) {
      discardMissingNode(nodeId);
      return false;
    }
    final current = state.nodes[nodeId];
    if (current != null) {
      if (current.status == InlineNodeSaveStatus.dirty) {
        final draft = current.patch.mergeInto(
          mutated,
          ref.read(inlineNodeAutosaveClockProvider)(),
        );
        _setNode(
          nodeId,
          current.copyWith(
            base: mutated,
            draft: draft,
            patch: InlineNodeDraftPatch.between(mutated, draft),
          ),
        );
        _scheduleFlush(nodeId);
      } else {
        rebaseNode(mutated);
      }
    }
    return true;
  });

  Future<T> _serialize<T>(String nodeId, Future<T> Function() operation) {
    final previous = _nodeTransactions[nodeId] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    late final Future<void> tail;
    tail = result.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_nodeTransactions[nodeId], tail)) {
        _nodeTransactions.remove(nodeId);
      }
      _updateFlushFlag();
    });
    _nodeTransactions[nodeId] = tail;
    _updateFlushFlag();
    return result;
  }

  Future<bool> _flushUntilClean(String nodeId) async {
    while (true) {
      if (!await _performFlush(nodeId)) return false;
      final current = state.nodes[nodeId];
      if (current == null) return false;
      if (current.status == InlineNodeSaveStatus.error) return false;
      if (current.status != InlineNodeSaveStatus.dirty) return true;
    }
  }

  Future<bool> _performFlush(String? nodeId) async {
    if (nodeId == null) return true;
    _cancelScheduledFlushes.remove(nodeId)?.call();
    final current = state.nodes[nodeId];
    if (current == null ||
        current.status == InlineNodeSaveStatus.idle ||
        current.status == InlineNodeSaveStatus.saved) {
      return true;
    }
    final validationError = _validationError(current.draft);
    if (validationError != null) {
      _setNode(
        nodeId,
        current.copyWith(
          status: InlineNodeSaveStatus.error,
          error: validationError,
        ),
      );
      return false;
    }
    final generation = current.generation;
    _setNode(nodeId, current.copyWith(status: InlineNodeSaveStatus.saving));
    try {
      final saved = await ref
          .read(mindmapMutationControllerProvider)
          .savePatch(
            nodeId,
            current.patch,
            now: ref.read(inlineNodeAutosaveClockProvider)(),
          );
      if (saved == null) {
        discardMissingNode(nodeId);
        return false;
      }
      final latestState = state.nodes[nodeId];
      if (latestState?.generation == generation) {
        _setNode(
          nodeId,
          latestState!.copyWith(
            base: saved,
            draft: saved,
            patch: InlineNodeDraftPatch(),
            status: InlineNodeSaveStatus.saved,
            clearError: true,
          ),
        );
      }
      return true;
    } on Object catch (error) {
      _setFailure(nodeId, generation, error);
      return false;
    }
  }

  void rebaseNode(MindmapNode node) {
    final current = state.nodes[node.id];
    if (current == null) return;
    _cancelScheduledFlushes.remove(node.id)?.call();
    _setNode(
      node.id,
      current.copyWith(
        base: node,
        draft: node,
        patch: InlineNodeDraftPatch(),
        status: InlineNodeSaveStatus.saved,
        generation: current.generation + 1,
        clearError: true,
      ),
    );
  }

  void discardMissingNode(String nodeId) {
    _cancelScheduledFlushes.remove(nodeId)?.call();
    final nodes = <String, InlineNodeDraftState>{...state.nodes}
      ..remove(nodeId);
    state = state.copyWith(
      clearExpandedNodeId: state.expandedNodeId == nodeId,
      nodes: nodes,
    );
  }

  void _scheduleFlush(String nodeId) {
    _cancelScheduledFlushes.remove(nodeId)?.call();
    late final void Function() cancel;
    cancel = ref.read(inlineNodeAutosaveSchedulerProvider)(
      debounceDuration,
      () {
        if (identical(_cancelScheduledFlushes[nodeId], cancel)) {
          _cancelScheduledFlushes.remove(nodeId);
        }
        unawaited(flush(nodeId));
      },
    );
    _cancelScheduledFlushes[nodeId] = cancel;
  }

  void _updateFlushFlag() {
    final isFlushing = _nodeTransactions.isNotEmpty;
    if (state.isFlushing != isFlushing) {
      state = state.copyWith(isFlushing: isFlushing);
    }
  }

  void _setFailure(String nodeId, int generation, Object error) {
    final current = state.nodes[nodeId];
    if (current == null || current.generation != generation) return;
    _setNode(
      nodeId,
      current.copyWith(status: InlineNodeSaveStatus.error, error: error),
    );
  }

  void _setNode(String nodeId, InlineNodeDraftState value) {
    state = state.copyWith(
      nodes: <String, InlineNodeDraftState>{...state.nodes, nodeId: value},
    );
  }
}

String? _validationError(MindmapNode node) {
  final errors = switch (node.type) {
    NodeType.task || NodeType.checklist => TaskChecklistPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.kanban => KanbanPayload.fromNode(node).validate(title: node.title),
    NodeType.plan => PlanPayload.fromNode(node).validate(title: node.title),
    NodeType.note || NodeType.empty => NodeValidation.requiredTitle(node.title),
    NodeType.journal => JournalPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.habit || NodeType.routine => HabitRoutinePayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.goal => GoalPayload.fromNode(node).validate(title: node.title),
    NodeType.link || NodeType.bookmark => LinkResourcePayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.resource => ResourcePayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.event => EventCalendarPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.decision => DecisionPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.idea => IdeaPayload.fromNode(node).validate(title: node.title),
    NodeType.question => QuestionPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.contact => ContactPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.metric => MetricPayload.fromNode(node).validate(title: node.title),
    NodeType.expense => ExpensePayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.mood => MoodPayload.fromNode(node).validate(title: node.title),
    NodeType.timer => TimerPayload.fromNode(node).validate(title: node.title),
    NodeType.quote => QuotePayload.fromNode(node).validate(title: node.title),
    NodeType.audio => AudioPayload.fromNode(node).validate(title: node.title),
    NodeType.canvas => CanvasPayload.fromNode(node).validate(title: node.title),
    NodeType.weather => WeatherPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.fit => FitPayload.fromNode(node).validate(title: node.title),
    NodeType.itinerary => ItineraryPayload.fromNode(
      node,
    ).validate(title: node.title),
    NodeType.image => ImagePayload.fromNode(node).validate(title: node.title),
    NodeType.video => VideoPayload.fromNode(node).validate(title: node.title),
    NodeType.frame || NodeType.swatch => NodeValidation.requiredTitle(node.title),
  };
  return errors.firstOrNull;
}
