library;

import 'package:collection/collection.dart';

const int maxTimerHistory = 100;

enum TimerMode { focus, countdown, stopwatch }

enum TimerRunStatus { idle, running, paused, expired, completed }

enum FocusSegment { focus, breakTime }

TimerMode _mode(Object? value) => TimerMode.values.firstWhere(
  (item) => item.name == value,
  orElse: () => TimerMode.focus,
);

TimerRunStatus _status(Object? value) => TimerRunStatus.values.firstWhere(
  (item) => item.name == value,
  orElse: () => TimerRunStatus.idle,
);

FocusSegment _segment(Object? value) => FocusSegment.values.firstWhere(
  (item) => item.name == value,
  orElse: () => FocusSegment.focus,
);

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
int _nonNegativeInt(Object? value, [int fallback = 0]) =>
    value is int && value >= 0 ? value : fallback;
String _text(Object? value) => value is String ? value.trim() : '';

final class TimerDistraction {
  const TimerDistraction({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory TimerDistraction.fromJson(Map<String, Object?> json) =>
      TimerDistraction(
        id: _text(json['id']),
        text: _text(json['text']),
        createdAt:
            _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String id;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is TimerDistraction &&
      other.id == id &&
      other.text == text &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, text, createdAt);
}

final class TimerLap {
  const TimerLap({
    required this.id,
    required this.elapsedSeconds,
    required this.createdAt,
  });

  factory TimerLap.fromJson(Map<String, Object?> json) => TimerLap(
    id: _text(json['id']),
    elapsedSeconds: _nonNegativeInt(json['elapsedSeconds']),
    createdAt:
        _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;
  final int elapsedSeconds;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'elapsedSeconds': elapsedSeconds,
    'createdAt': createdAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is TimerLap &&
      other.id == id &&
      other.elapsedSeconds == elapsedSeconds &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, elapsedSeconds, createdAt);
}

final class TimerSessionRecord {
  const TimerSessionRecord({
    required this.id,
    required this.mode,
    required this.label,
    required this.startedAt,
    required this.completedAt,
    required this.plannedSeconds,
    required this.actualSeconds,
    required this.completed,
    required this.segment,
    this.distractions = const <TimerDistraction>[],
    this.laps = const <TimerLap>[],
  });

  factory TimerSessionRecord.fromJson(Map<String, Object?> json) {
    final distractions = json['distractions'];
    final laps = json['laps'];
    return TimerSessionRecord(
      id: _text(json['id']),
      mode: _mode(json['mode']),
      label: _text(json['label']),
      startedAt:
          _date(json['startedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      completedAt:
          _date(json['completedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      plannedSeconds: _nonNegativeInt(json['plannedSeconds']),
      actualSeconds: _nonNegativeInt(json['actualSeconds']),
      completed: json['completed'] as bool? ?? false,
      segment: _segment(json['segment']),
      distractions: <TimerDistraction>[
        if (distractions is List)
          for (final value in distractions)
            if (value is Map)
              TimerDistraction.fromJson(value.cast<String, Object?>()),
      ],
      laps: <TimerLap>[
        if (laps is List)
          for (final value in laps)
            if (value is Map) TimerLap.fromJson(value.cast<String, Object?>()),
      ],
    );
  }

  final String id;
  final TimerMode mode;
  final String label;
  final DateTime startedAt;
  final DateTime completedAt;
  final int plannedSeconds;
  final int actualSeconds;
  final bool completed;
  final FocusSegment segment;
  final List<TimerDistraction> distractions;
  final List<TimerLap> laps;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'mode': mode.name,
    'label': label,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'plannedSeconds': plannedSeconds,
    'actualSeconds': actualSeconds,
    'completed': completed,
    'segment': segment.name,
    'distractions': distractions.map((item) => item.toJson()).toList(),
    'laps': laps.map((item) => item.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is TimerSessionRecord &&
      other.id == id &&
      other.mode == mode &&
      other.label == label &&
      other.startedAt == startedAt &&
      other.completedAt == completedAt &&
      other.plannedSeconds == plannedSeconds &&
      other.actualSeconds == actualSeconds &&
      other.completed == completed &&
      other.segment == segment &&
      const ListEquality<TimerDistraction>().equals(
        other.distractions,
        distractions,
      ) &&
      const ListEquality<TimerLap>().equals(other.laps, laps);

  @override
  int get hashCode => Object.hash(
    id,
    mode,
    label,
    startedAt,
    completedAt,
    plannedSeconds,
    actualSeconds,
    completed,
    segment,
    const ListEquality<TimerDistraction>().hash(distractions),
    const ListEquality<TimerLap>().hash(laps),
  );
}

final class HybridTimerState {
  const HybridTimerState({
    this.mode = TimerMode.focus,
    this.status = TimerRunStatus.idle,
    this.label = '',
    this.plannedSeconds = 1500,
    this.accumulatedSeconds = 0,
    this.startedAt,
    this.sessionStartedAt,
    this.focusSeconds = 1500,
    this.breakSeconds = 300,
    this.cycleTarget = 4,
    this.completedCycles = 0,
    this.segment = FocusSegment.focus,
    this.autoStartBreak = false,
    this.distractions = const <TimerDistraction>[],
    this.laps = const <TimerLap>[],
    this.history = const <TimerSessionRecord>[],
  });

  factory HybridTimerState.fromJson(Map<String, Object?> json) {
    final distractions = json['distractions'];
    final laps = json['laps'];
    final history = json['history'];
    return HybridTimerState(
      mode: _mode(json['mode']),
      status: _status(json['status']),
      label: _text(json['label']),
      plannedSeconds: _nonNegativeInt(json['plannedSeconds'], 1500),
      accumulatedSeconds: _nonNegativeInt(json['accumulatedSeconds']),
      startedAt: _date(json['startedAt']),
      sessionStartedAt: _date(json['sessionStartedAt']),
      focusSeconds: _nonNegativeInt(json['focusSeconds'], 1500),
      breakSeconds: _nonNegativeInt(json['breakSeconds'], 300),
      cycleTarget: _nonNegativeInt(json['cycleTarget'], 4).clamp(1, 12),
      completedCycles: _nonNegativeInt(json['completedCycles']),
      segment: _segment(json['segment']),
      autoStartBreak: json['autoStartBreak'] as bool? ?? false,
      distractions: <TimerDistraction>[
        if (distractions is List)
          for (final value in distractions)
            if (value is Map)
              TimerDistraction.fromJson(value.cast<String, Object?>()),
      ],
      laps: <TimerLap>[
        if (laps is List)
          for (final value in laps)
            if (value is Map) TimerLap.fromJson(value.cast<String, Object?>()),
      ],
      history: <TimerSessionRecord>[
        if (history is List)
          for (final value in history.take(maxTimerHistory))
            if (value is Map)
              TimerSessionRecord.fromJson(value.cast<String, Object?>()),
      ],
    );
  }

  final TimerMode mode;
  final TimerRunStatus status;
  final String label;
  final int plannedSeconds;
  final int accumulatedSeconds;
  final DateTime? startedAt;
  final DateTime? sessionStartedAt;
  final int focusSeconds;
  final int breakSeconds;
  final int cycleTarget;
  final int completedCycles;
  final FocusSegment segment;
  final bool autoStartBreak;
  final List<TimerDistraction> distractions;
  final List<TimerLap> laps;
  final List<TimerSessionRecord> history;

  bool get isRunning => status == TimerRunStatus.running;
  bool get isBounded => mode != TimerMode.stopwatch;
  bool get hasElapsedWork => accumulatedSeconds > 0 || startedAt != null;
  int get activePlannedSeconds => mode == TimerMode.focus
      ? segment == FocusSegment.focus
            ? focusSeconds
            : breakSeconds
      : plannedSeconds;

  int elapsedSecondsAt(DateTime now) {
    if (!isRunning || startedAt == null) return accumulatedSeconds;
    return accumulatedSeconds +
        now.difference(startedAt!).inSeconds.clamp(0, 1 << 31);
  }

  int? remainingSecondsAt(DateTime now) => isBounded
      ? (activePlannedSeconds - elapsedSecondsAt(now)).clamp(
          0,
          activePlannedSeconds,
        )
      : null;

  double progressAt(DateTime now) {
    if (!isBounded || activePlannedSeconds <= 0) return 0;
    return (elapsedSecondsAt(now) / activePlannedSeconds).clamp(0, 1);
  }

  TimerRunStatus effectiveStatusAt(DateTime now) =>
      isRunning && isBounded && remainingSecondsAt(now) == 0
      ? TimerRunStatus.expired
      : status;

  HybridTimerState start(DateTime now) => copyWith(
    status: TimerRunStatus.running,
    startedAt: now,
    sessionStartedAt: sessionStartedAt ?? now,
  );

  HybridTimerState pause(DateTime now) => copyWith(
    status: TimerRunStatus.paused,
    accumulatedSeconds: elapsedSecondsAt(now),
    clearStartedAt: true,
  );

  HybridTimerState reset() => copyWith(
    status: TimerRunStatus.idle,
    accumulatedSeconds: 0,
    clearStartedAt: true,
    clearSessionStartedAt: true,
    distractions: const <TimerDistraction>[],
    laps: const <TimerLap>[],
  );

  HybridTimerState complete(DateTime now, {required String recordId}) {
    final actual = elapsedSecondsAt(now);
    final record = TimerSessionRecord(
      id: recordId,
      mode: mode,
      label: label,
      startedAt: sessionStartedAt ?? startedAt ?? now,
      completedAt: now,
      plannedSeconds: isBounded ? activePlannedSeconds : 0,
      actualSeconds: actual,
      completed: true,
      segment: segment,
      distractions: distractions,
      laps: laps,
    );
    final nextHistory = <TimerSessionRecord>[
      record,
      ...history,
    ].take(maxTimerHistory).toList(growable: false);
    final nextCycles = mode == TimerMode.focus && segment == FocusSegment.focus
        ? (completedCycles + 1).clamp(0, cycleTarget)
        : completedCycles;
    return copyWith(
      status: TimerRunStatus.completed,
      accumulatedSeconds: 0,
      completedCycles: nextCycles,
      clearStartedAt: true,
      clearSessionStartedAt: true,
      distractions: const <TimerDistraction>[],
      laps: const <TimerLap>[],
      history: nextHistory,
    );
  }

  HybridTimerState addDistraction(TimerDistraction value) =>
      copyWith(distractions: <TimerDistraction>[...distractions, value]);

  HybridTimerState addLap(DateTime now, {required String id}) => copyWith(
    laps: <TimerLap>[
      ...laps,
      TimerLap(id: id, elapsedSeconds: elapsedSecondsAt(now), createdAt: now),
    ],
  );

  HybridTimerState copyWith({
    TimerMode? mode,
    TimerRunStatus? status,
    String? label,
    int? plannedSeconds,
    int? accumulatedSeconds,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? sessionStartedAt,
    bool clearSessionStartedAt = false,
    int? focusSeconds,
    int? breakSeconds,
    int? cycleTarget,
    int? completedCycles,
    FocusSegment? segment,
    bool? autoStartBreak,
    List<TimerDistraction>? distractions,
    List<TimerLap>? laps,
    List<TimerSessionRecord>? history,
  }) => HybridTimerState(
    mode: mode ?? this.mode,
    status: status ?? this.status,
    label: label ?? this.label,
    plannedSeconds: plannedSeconds ?? this.plannedSeconds,
    accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
    startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
    sessionStartedAt: clearSessionStartedAt
        ? null
        : sessionStartedAt ?? this.sessionStartedAt,
    focusSeconds: focusSeconds ?? this.focusSeconds,
    breakSeconds: breakSeconds ?? this.breakSeconds,
    cycleTarget: cycleTarget ?? this.cycleTarget,
    completedCycles: completedCycles ?? this.completedCycles,
    segment: segment ?? this.segment,
    autoStartBreak: autoStartBreak ?? this.autoStartBreak,
    distractions: distractions ?? this.distractions,
    laps: laps ?? this.laps,
    history: history ?? this.history,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'status': status.name,
    'label': label,
    'plannedSeconds': plannedSeconds,
    'accumulatedSeconds': accumulatedSeconds,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (sessionStartedAt != null)
      'sessionStartedAt': sessionStartedAt!.toIso8601String(),
    'focusSeconds': focusSeconds,
    'breakSeconds': breakSeconds,
    'cycleTarget': cycleTarget,
    'completedCycles': completedCycles,
    'segment': segment.name,
    'autoStartBreak': autoStartBreak,
    'distractions': distractions.map((item) => item.toJson()).toList(),
    'laps': laps.map((item) => item.toJson()).toList(),
    'history': history
        .take(maxTimerHistory)
        .map((item) => item.toJson())
        .toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is HybridTimerState &&
      other.mode == mode &&
      other.status == status &&
      other.label == label &&
      other.plannedSeconds == plannedSeconds &&
      other.accumulatedSeconds == accumulatedSeconds &&
      other.startedAt == startedAt &&
      other.sessionStartedAt == sessionStartedAt &&
      other.focusSeconds == focusSeconds &&
      other.breakSeconds == breakSeconds &&
      other.cycleTarget == cycleTarget &&
      other.completedCycles == completedCycles &&
      other.segment == segment &&
      other.autoStartBreak == autoStartBreak &&
      const ListEquality<TimerDistraction>().equals(
        other.distractions,
        distractions,
      ) &&
      const ListEquality<TimerLap>().equals(other.laps, laps) &&
      const ListEquality<TimerSessionRecord>().equals(other.history, history);

  @override
  int get hashCode => Object.hashAll(<Object?>[
    mode,
    status,
    label,
    plannedSeconds,
    accumulatedSeconds,
    startedAt,
    sessionStartedAt,
    focusSeconds,
    breakSeconds,
    cycleTarget,
    completedCycles,
    segment,
    autoStartBreak,
    const ListEquality<TimerDistraction>().hash(distractions),
    const ListEquality<TimerLap>().hash(laps),
    const ListEquality<TimerSessionRecord>().hash(history),
  ]);
}
