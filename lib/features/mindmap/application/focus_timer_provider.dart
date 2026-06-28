import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import '../domain/mindmap_node.dart';
import 'mindmap_providers.dart';

enum FocusTimerPhase {
  focus('Focus'),
  shortBreak('Short Break'),
  longBreak('Long Break');

  const FocusTimerPhase(this.label);
  final String label;
}

class FocusTimerState {
  const FocusTimerState({
    required this.durationSeconds,
    required this.elapsedSeconds,
    required this.isRunning,
    required this.phase,
    this.selectedNodeId,
    this.selectedNodeTitle,
    required this.completedSessionsCount,
  });

  final int durationSeconds;
  final int elapsedSeconds;
  final bool isRunning;
  final FocusTimerPhase phase;
  final String? selectedNodeId;
  final String? selectedNodeTitle;
  final int completedSessionsCount;

  int get remainingSeconds =>
      (durationSeconds - elapsedSeconds).clamp(0, durationSeconds);
  double get progress => durationSeconds == 0
      ? 0.0
      : (elapsedSeconds / durationSeconds).clamp(0.0, 1.0);

  FocusTimerState copyWith({
    int? durationSeconds,
    int? elapsedSeconds,
    bool? isRunning,
    FocusTimerPhase? phase,
    String? Function()? selectedNodeId,
    String? Function()? selectedNodeTitle,
    int? completedSessionsCount,
  }) {
    return FocusTimerState(
      durationSeconds: durationSeconds ?? this.durationSeconds,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isRunning: isRunning ?? this.isRunning,
      phase: phase ?? this.phase,
      selectedNodeId: selectedNodeId != null
          ? selectedNodeId()
          : this.selectedNodeId,
      selectedNodeTitle: selectedNodeTitle != null
          ? selectedNodeTitle()
          : this.selectedNodeTitle,
      completedSessionsCount:
          completedSessionsCount ?? this.completedSessionsCount,
    );
  }
}

class FocusTimerNotifier extends StateNotifier<FocusTimerState> {
  FocusTimerNotifier(this._ref)
    : super(
        const FocusTimerState(
          durationSeconds: 25 * 60,
          elapsedSeconds: 0,
          isRunning: false,
          phase: FocusTimerPhase.focus,
          completedSessionsCount: 0,
        ),
      );

  final Ref _ref;
  Timer? _timer;

  void start() {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void pause() {
    if (!state.isRunning) return;
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(isRunning: false);
  }

  void reset() {
    pause();
    state = state.copyWith(elapsedSeconds: 0);
  }

  void skip() {
    pause();
    _completePhase();
  }

  void setDuration(int minutes) {
    pause();
    state = state.copyWith(durationSeconds: minutes * 60, elapsedSeconds: 0);
  }

  void selectNode(String? id, String? title) {
    state = state.copyWith(
      selectedNodeId: () => id,
      selectedNodeTitle: () => title,
    );
  }

  void _tick() {
    if (state.elapsedSeconds >= state.durationSeconds) {
      _completePhase();
    } else {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    }
  }

  Future<void> _completePhase() async {
    _timer?.cancel();
    _timer = null;

    final completedPhase = state.phase;
    final durationMins = (state.durationSeconds / 60).round();
    final completedTaskId = state.selectedNodeId;
    final completedTaskTitle = state.selectedNodeTitle;

    if (completedPhase == FocusTimerPhase.focus) {
      state = state.copyWith(
        completedSessionsCount: state.completedSessionsCount + 1,
      );

      await _logFocusSession(durationMins, completedTaskId, completedTaskTitle);

      final nextPhase = (state.completedSessionsCount % 4 == 0)
          ? FocusTimerPhase.longBreak
          : FocusTimerPhase.shortBreak;

      final nextDuration = nextPhase == FocusTimerPhase.longBreak
          ? 15 * 60
          : 5 * 60;

      state = state.copyWith(
        phase: nextPhase,
        durationSeconds: nextDuration,
        elapsedSeconds: 0,
        isRunning: false,
      );
    } else {
      state = state.copyWith(
        phase: FocusTimerPhase.focus,
        durationSeconds: 25 * 60,
        elapsedSeconds: 0,
        isRunning: false,
      );
    }
  }

  Future<void> _logFocusSession(
    int durationMins,
    String? taskId,
    String? taskTitle,
  ) async {
    final today = DateTime.now().dateOnly;
    final repository = _ref.read(mindmapRepositoryProvider);

    final dayNodes = await repository.listNodes(day: today);
    MindmapNode? journalNode;
    for (final n in dayNodes) {
      if (n.type == NodeType.journal && !n.isArchived) {
        journalNode = n;
        break;
      }
    }

    if (journalNode == null) {
      final dateFormat = DateFormat('yyyy-MM-dd');
      journalNode = MindmapNode(
        id: const Uuid().v4(),
        type: NodeType.journal,
        title: 'Daily Journal - ${dateFormat.format(today)}',
        day: today,
        area: 'Mind',
        tags: const ['journal'],
        data: const {
          'journal': {
            'mood': 0,
            'energy': 0,
            'prompt': 'What mattered today?',
            'gratitude': <String>[],
            'isWeeklyReview': false,
          },
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final focusSessions = List<Map<String, Object?>>.from(
      (journalNode.data['focus_sessions'] as List?)?.map(
            (e) => Map<String, Object?>.from(e as Map),
          ) ??
          [],
    );

    focusSessions.add({
      'task_id': taskId,
      'task_title': taskTitle,
      'duration_mins': durationMins,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final updatedNode = journalNode.copyWith(
      data: {...journalNode.data, 'focus_sessions': focusSessions},
      updatedAt: DateTime.now(),
    );

    await repository.saveNode(updatedNode);

    invalidateMindmapStateFromRef(_ref, day: today);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final focusTimerProvider =
    StateNotifierProvider<FocusTimerNotifier, FocusTimerState>((ref) {
      return FocusTimerNotifier(ref);
    });
