import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/date_utils.dart';
import '../../domain/hybrid_timer.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';

final class TimerNodeEditor extends StatefulWidget {
  const TimerNodeEditor({
    required this.node,
    required this.payload,
    required this.onTitleChanged,
    required this.onBodyChanged,
    required this.onPayloadChanged,
    super.key,
  });

  final MindmapNode node;
  final TimerPayload payload;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final ValueChanged<TimerPayload> onPayloadChanged;

  @override
  State<TimerNodeEditor> createState() => _TimerNodeEditorState();
}

final class _TimerNodeEditorState extends State<TimerNodeEditor> {
  Timer? _ticker;
  final TextEditingController _distractionController = TextEditingController();

  HybridTimerState get timer => widget.payload.timer;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant TimerNodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload.timer.isRunning != timer.isRunning) _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _distractionController.dispose();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (!timer.isRunning) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _emit(HybridTimerState value) =>
      widget.onPayloadChanged(TimerPayload(timer: value));

  Future<bool> _confirmLoss() async {
    if (!timer.hasElapsedWork) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard current timer?'),
            content: const Text(
              'Elapsed work in this active timer will reset.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _switchMode(TimerMode mode) async {
    if (timer.mode == mode || !await _confirmLoss()) return;
    final planned = switch (mode) {
      TimerMode.focus => timer.focusSeconds,
      TimerMode.countdown => 1500,
      TimerMode.stopwatch => 0,
    };
    _emit(timer.reset().copyWith(mode: mode, plannedSeconds: planned));
  }

  void _primary() {
    final now = DateTime.now();
    _emit(timer.isRunning ? timer.pause(now) : timer.start(now));
  }

  void _complete() => _emit(
    timer.complete(DateTime.now(), recordId: 'session-${const Uuid().v4()}'),
  );

  Future<void> _reset() async {
    if (await _confirmLoss()) _emit(timer.reset());
  }

  void _addDistraction() {
    final text = _distractionController.text.trim();
    if (text.isEmpty) return;
    _emit(
      timer.addDistraction(
        TimerDistraction(
          id: 'distraction-${const Uuid().v4()}',
          text: text,
          createdAt: DateTime.now(),
        ),
      ),
    );
    _distractionController.clear();
  }

  void _addLap() =>
      _emit(timer.addLap(DateTime.now(), id: 'lap-${const Uuid().v4()}'));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey<String>('timer-hybrid-editor'),
      color: colors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              key: ValueKey<String>(
                'productivity-${widget.node.id}-title-field',
              ),
              initialValue: widget.node.title,
              maxLength: 80,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.timer_outlined),
                hintText: 'Timer title',
                counterText: '',
                isDense: true,
              ),
              onChanged: widget.onTitleChanged,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey<String>(
                'productivity-${widget.node.id}-body-field',
              ),
              initialValue: widget.node.body,
              maxLines: 2,
              maxLength: 240,
              decoration: const InputDecoration(
                hintText: 'Session objective or notes',
                counterText: '',
                isDense: true,
              ),
              onChanged: widget.onBodyChanged,
            ),
            const SizedBox(height: 12),
            SegmentedButton<TimerMode>(
              segments: <ButtonSegment<TimerMode>>[
                for (final mode in TimerMode.values)
                  ButtonSegment<TimerMode>(
                    value: mode,
                    icon: Icon(_modeIcon(mode), size: 18),
                    label: Text(_modeLabel(mode)),
                  ),
              ],
              selected: <TimerMode>{timer.mode},
              onSelectionChanged: (values) => _switchMode(values.single),
            ),
            const SizedBox(height: 12),
            _Hero(timer: timer, now: now),
            const SizedBox(height: 12),
            _controls(),
            const SizedBox(height: 12),
            _settings(),
            const SizedBox(height: 12),
            if (timer.mode == TimerMode.stopwatch) _laps(),
            if (timer.mode == TimerMode.stopwatch) const SizedBox(height: 12),
            _distractions(),
            const SizedBox(height: 12),
            _summary(now),
            if (timer.history.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _history(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      FilledButton.icon(
        key: const ValueKey<String>('timer-primary-action'),
        onPressed: _primary,
        icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
        label: Text(timer.isRunning ? 'Pause' : 'Start'),
      ),
      FilledButton.tonalIcon(
        key: const ValueKey<String>('timer-complete-action'),
        onPressed: timer.hasElapsedWork ? _complete : null,
        icon: const Icon(Icons.check_rounded),
        label: const Text('Complete'),
      ),
      OutlinedButton.icon(
        key: const ValueKey<String>('timer-reset-action'),
        onPressed: timer.hasElapsedWork ? _reset : null,
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Reset'),
      ),
      if (timer.mode == TimerMode.stopwatch)
        OutlinedButton.icon(
          key: const ValueKey<String>('timer-add-lap'),
          onPressed: timer.hasElapsedWork ? _addLap : null,
          icon: const Icon(Icons.flag_outlined),
          label: const Text('Lap'),
        ),
    ],
  );

  Widget _settings() => _Section(
    title: '${_modeLabel(timer.mode)} settings',
    icon: Icons.tune_rounded,
    child: switch (timer.mode) {
      TimerMode.focus => _focusSettings(),
      TimerMode.countdown => _countdownSettings(),
      TimerMode.stopwatch => TextFormField(
        initialValue: timer.label,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Stopwatch label',
          counterText: '',
          isDense: true,
        ),
        onChanged: (value) => _emit(timer.copyWith(label: value.trim())),
      ),
    },
  );

  Widget _focusSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _Preset(
            label: '25 / 5',
            selected: timer.focusSeconds == 1500 && timer.breakSeconds == 300,
            onTap: () => _emit(
              timer.copyWith(
                focusSeconds: 1500,
                breakSeconds: 300,
                plannedSeconds: 1500,
              ),
            ),
          ),
          _Preset(
            label: '50 / 10',
            selected: timer.focusSeconds == 3000 && timer.breakSeconds == 600,
            onTap: () => _emit(
              timer.copyWith(
                focusSeconds: 3000,
                breakSeconds: 600,
                plannedSeconds: 3000,
              ),
            ),
          ),
          _Preset(
            label: timer.segment == FocusSegment.focus ? 'Focus' : 'Break',
            selected: true,
            onTap: () => _emit(
              timer.reset().copyWith(
                segment: timer.segment == FocusSegment.focus
                    ? FocusSegment.breakTime
                    : FocusSegment.focus,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          _MinutesField(
            label: 'Focus minutes',
            value: timer.focusSeconds ~/ 60,
            onChanged: (value) => _emit(
              timer.copyWith(
                focusSeconds: value * 60,
                plannedSeconds: value * 60,
              ),
            ),
          ),
          _MinutesField(
            label: 'Break minutes',
            value: timer.breakSeconds ~/ 60,
            onChanged: (value) =>
                _emit(timer.copyWith(breakSeconds: value * 60)),
          ),
          _MinutesField(
            label: 'Cycles',
            value: timer.cycleTarget,
            max: 12,
            onChanged: (value) => _emit(timer.copyWith(cycleTarget: value)),
          ),
        ],
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Auto-start break'),
        value: timer.autoStartBreak,
        onChanged: (value) => _emit(timer.copyWith(autoStartBreak: value)),
      ),
    ],
  );

  Widget _countdownSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final minutes in const <int>[5, 15, 25, 45, 60])
            _Preset(
              label: '$minutes min',
              selected: timer.plannedSeconds == minutes * 60,
              onTap: () =>
                  _emit(timer.reset().copyWith(plannedSeconds: minutes * 60)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _MinutesField(
        label: 'Custom minutes',
        value: timer.plannedSeconds ~/ 60,
        onChanged: (value) =>
            _emit(timer.reset().copyWith(plannedSeconds: value * 60)),
      ),
    ],
  );

  Widget _laps() => _Section(
    title: 'Laps',
    icon: Icons.flag_outlined,
    child: timer.laps.isEmpty
        ? const Text('No laps yet')
        : Column(
            children: <Widget>[
              for (var index = timer.laps.length - 1; index >= 0; index--)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 13,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(_duration(timer.laps[index].elapsedSeconds)),
                  trailing: Text(
                    DateFormat.Hms().format(timer.laps[index].createdAt),
                  ),
                ),
            ],
          ),
  );

  Widget _distractions() => _Section(
    title: 'Distraction log',
    icon: Icons.notifications_off_outlined,
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _distractionController,
                inputFormatters: <TextInputFormatter>[
                  LengthLimitingTextInputFormatter(160),
                ],
                decoration: const InputDecoration(
                  hintText: 'What interrupted the session?',
                  isDense: true,
                ),
                onSubmitted: (_) => _addDistraction(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const ValueKey<String>('timer-add-distraction'),
              tooltip: 'Add distraction',
              onPressed: _addDistraction,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        if (timer.distractions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final item in timer.distractions.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt_outlined, size: 18),
              title: Text(item.text),
              trailing: Text(DateFormat.Hm().format(item.createdAt)),
            ),
        ],
      ],
    ),
  );

  Widget _summary(DateTime now) {
    final today = now.dateOnly;
    final records = timer.history.where(
      (record) => record.completedAt.dateOnly == today,
    );
    final focusSeconds = records
        .where(
          (record) =>
              record.mode == TimerMode.focus &&
              record.segment == FocusSegment.focus,
        )
        .fold<int>(0, (sum, record) => sum + record.actualSeconds);
    final distractions = records.fold<int>(
      0,
      (sum, record) => sum + record.distractions.length,
    );
    return _Section(
      key: const ValueKey<String>('timer-summary'),
      title: 'Today',
      icon: Icons.insights_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _Metric(label: 'Focus', value: _duration(focusSeconds)),
          _Metric(label: 'Sessions', value: '${records.length}'),
          _Metric(label: 'Distractions', value: '$distractions'),
        ],
      ),
    );
  }

  Widget _history() => _Section(
    key: const ValueKey<String>('timer-history'),
    title: 'Recent sessions',
    icon: Icons.history_rounded,
    child: Column(
      children: <Widget>[
        for (final record in timer.history.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_modeIcon(record.mode), size: 20),
            title: Text(
              record.label.isEmpty ? _modeLabel(record.mode) : record.label,
            ),
            subtitle: Text(
              DateFormat('MMM d, HH:mm').format(record.completedAt),
            ),
            trailing: Text(_duration(record.actualSeconds)),
          ),
      ],
    ),
  );
}

final class _Hero extends StatelessWidget {
  const _Hero({required this.timer, required this.now});

  final HybridTimerState timer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seconds = timer.mode == TimerMode.stopwatch
        ? timer.elapsedSecondsAt(now)
        : timer.remainingSecondsAt(now) ?? 0;
    final status = timer.effectiveStatusAt(now);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  timer.label.isEmpty ? _modeLabel(timer.mode) : timer.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _Status(status: status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _duration(seconds),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
            ),
          ),
          if (timer.isBounded) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: timer.progressAt(now)),
          ],
          if (timer.mode == TimerMode.focus) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              '${timer.segment == FocusSegment.focus ? 'Focus' : 'Break'} · '
              '${timer.completedCycles}/${timer.cycleTarget} cycles',
            ),
          ],
        ],
      ),
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    super.key,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

final class _Preset extends StatelessWidget {
  const _Preset({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}

final class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 1440,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: TextFormField(
      key: ValueKey<String>('timer-field-${label.toLowerCase()}'),
      initialValue: '$value',
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (text) {
        final parsed = int.tryParse(text);
        if (parsed != null && parsed >= 1 && parsed <= max) onChanged(parsed);
      },
    ),
  );
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text('$label · $value'),
  );
}

final class _Status extends StatelessWidget {
  const _Status({required this.status});

  final TimerRunStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: status == TimerRunStatus.running
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(_statusLabel(status)),
  );
}

String _duration(int seconds) {
  final safe = seconds.clamp(0, 359999);
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remainder = safe % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainder.toString().padLeft(2, '0')}';
}

String _modeLabel(TimerMode mode) => switch (mode) {
  TimerMode.focus => 'Focus',
  TimerMode.countdown => 'Countdown',
  TimerMode.stopwatch => 'Stopwatch',
};

IconData _modeIcon(TimerMode mode) => switch (mode) {
  TimerMode.focus => Icons.center_focus_strong_outlined,
  TimerMode.countdown => Icons.hourglass_bottom_rounded,
  TimerMode.stopwatch => Icons.timer_outlined,
};

String _statusLabel(TimerRunStatus status) => switch (status) {
  TimerRunStatus.idle => 'Idle',
  TimerRunStatus.running => 'Running',
  TimerRunStatus.paused => 'Paused',
  TimerRunStatus.expired => 'Expired',
  TimerRunStatus.completed => 'Completed',
};
