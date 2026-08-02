import 'package:flutter/material.dart';

class FocusSettingsDialog extends StatefulWidget {
  const FocusSettingsDialog({
    required this.workMins,
    required this.shortBreakMins,
    required this.longBreakMins,
    required this.sessionsPerCycle,
    required this.autoStartBreaks,
    required this.autoStartFocus,
    required this.onSaveSettings,
    super.key,
  });

  final int workMins;
  final int shortBreakMins;
  final int longBreakMins;
  final int sessionsPerCycle;
  final bool autoStartBreaks;
  final bool autoStartFocus;

  final void Function({
    required int workMins,
    required int shortBreakMins,
    required int longBreakMins,
    required int sessionsPerCycle,
    required bool autoStartBreaks,
    required bool autoStartFocus,
  })
  onSaveSettings;

  @override
  State<FocusSettingsDialog> createState() => _FocusSettingsDialogState();
}

class _FocusSettingsDialogState extends State<FocusSettingsDialog> {
  late int _workMins;
  late int _shortBreakMins;
  late int _longBreakMins;
  late int _sessionsPerCycle;
  late bool _autoStartBreaks;
  late bool _autoStartFocus;

  @override
  void initState() {
    super.initState();
    _workMins = widget.workMins;
    _shortBreakMins = widget.shortBreakMins;
    _longBreakMins = widget.longBreakMins;
    _sessionsPerCycle = widget.sessionsPerCycle;
    _autoStartBreaks = widget.autoStartBreaks;
    _autoStartFocus = widget.autoStartFocus;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Pengaturan Advanced Pomodoro'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Durasi Timer (Menit)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildNumberRow(
                'Fokus / Work:',
                _workMins,
                (v) => setState(() => _workMins = v),
              ),
              _buildNumberRow(
                'Short Break:',
                _shortBreakMins,
                (v) => setState(() => _shortBreakMins = v),
              ),
              _buildNumberRow(
                'Long Break:',
                _longBreakMins,
                (v) => setState(() => _longBreakMins = v),
              ),
              _buildNumberRow(
                'Sesi per Siklus:',
                _sessionsPerCycle,
                (v) => setState(() => _sessionsPerCycle = v),
              ),
              const Divider(height: 24),
              Text(
                'Opsi Otomatis',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-start Break'),
                subtitle: const Text(
                  'Mulai otomatis sesi istirahat saat fokus selesai',
                ),
                value: _autoStartBreaks,
                onChanged: (v) => setState(() => _autoStartBreaks = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-start Fokus'),
                subtitle: const Text(
                  'Mulai otomatis sesi fokus saat istirahat selesai',
                ),
                value: _autoStartFocus,
                onChanged: (v) => setState(() => _autoStartFocus = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSaveSettings(
              workMins: _workMins,
              shortBreakMins: _shortBreakMins,
              longBreakMins: _longBreakMins,
              sessionsPerCycle: _sessionsPerCycle,
              autoStartBreaks: _autoStartBreaks,
              autoStartFocus: _autoStartFocus,
            );
            Navigator.pop(context);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }

  Widget _buildNumberRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: value > 1 ? () => onChanged(value - 1) : null,
              ),
              Text(
                '$value',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
