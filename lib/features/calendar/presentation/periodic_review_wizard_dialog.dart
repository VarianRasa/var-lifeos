library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/node_visuals.dart';
import '../../../core/utils/date_utils.dart';
import '../../mindmap/application/mindmap_mutation_controller.dart';
import '../../mindmap/application/mindmap_providers.dart';
import '../../mindmap/domain/canvas_position.dart';
import '../../mindmap/domain/mindmap_node.dart';

Future<MindmapNode?> showPeriodicReviewWizardDialog(
  BuildContext context, {
  bool isMonthly = false,
  required DateTime today,
  required DateTime start,
  required DateTime end,
  MindmapNode? existingReview,
}) {
  return showDialog<MindmapNode>(
    context: context,
    builder: (context) => PeriodicReviewWizardDialog(
      isMonthly: isMonthly,
      today: today,
      start: start,
      end: end,
      existingReview: existingReview,
    ),
  );
}

class PeriodicReviewWizardDialog extends ConsumerStatefulWidget {
  const PeriodicReviewWizardDialog({
    super.key,
    this.isMonthly = false,
    required this.today,
    required this.start,
    required this.end,
    this.existingReview,
  });

  final bool isMonthly;
  final DateTime today;
  final DateTime start;
  final DateTime end;
  final MindmapNode? existingReview;

  @override
  ConsumerState<PeriodicReviewWizardDialog> createState() =>
      _PeriodicReviewWizardDialogState();
}

class _PeriodicReviewWizardDialogState
    extends ConsumerState<PeriodicReviewWizardDialog> {
  int _step = 0;
  final _winsController = TextEditingController();
  final _gratitudeController = TextEditingController();
  final _lessonsController = TextEditingController();
  final _nextFocusController = TextEditingController();
  double _moodRating = 4.0;
  bool _autoCreateTasks = true;
  bool _saving = false;
  Object? _saveError;

  @override
  void initState() {
    super.initState();
    final journal = _sectionData(widget.existingReview?.data, 'journal');
    _winsController.text = _stringValue(journal['wins']);
    _gratitudeController.text = _stringValue(journal['gratitude']);
    _lessonsController.text = _stringValue(journal['lessons']);
    _nextFocusController.text = _stringValue(journal['nextFocus']);
    _moodRating = (journal['moodRating'] as num?)?.toDouble() ?? 4.0;
  }

  @override
  void dispose() {
    _winsController.dispose();
    _gratitudeController.dispose();
    _lessonsController.dispose();
    _nextFocusController.dispose();
    super.dispose();
  }

  String _moodEmoji(double rating) {
    if (rating <= 1.5) return '😩 Lelah / Low Energy';
    if (rating <= 2.5) return '🙁 Kurang Kondusif';
    if (rating <= 3.5) return '😐 Stabil / Normal';
    if (rating <= 4.5) return '🙂 Produktif & Fokus';
    return '🚀 On Fire / Peak Performance';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isMonthly ? 'Monthly Review' : 'Weekly Review';
    final nodesAsync = ref.watch(allMindmapNodesProvider);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.isMonthly
                ? Icons.calendar_month
                : Icons.rate_review_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('$title Wizard (5-Steps Life OS)'),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Stepper(
          physics: const ClampingScrollPhysics(),
          key: const ValueKey('periodic-review-stepper'),
          currentStep: _step,
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: details.onStepContinue,
                  icon: Icon(
                    _step == 4 ? Icons.check : Icons.arrow_forward,
                    size: 16,
                  ),
                  label: Text(_step == 4 ? 'Simpan Review' : 'Lanjut'),
                ),
                if (_step > 0) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Kembali'),
                  ),
                ],
              ],
            ),
          ),
          onStepContinue: _saving
              ? null
              : () async {
                  if (_step < 4) {
                    setState(() => _step++);
                    return;
                  }
                  setState(() {
                    _saving = true;
                    _saveError = null;
                  });
                  final navigator = Navigator.of(context);
                  try {
                    final saved = await _completeReview();
                    if (mounted) navigator.pop(saved);
                  } catch (error) {
                    if (!mounted) return;
                    setState(() {
                      _saving = false;
                      _saveError = error;
                    });
                  }
                },
          onStepCancel: _saving
              ? null
              : () {
                  if (_step > 0) setState(() => _step--);
                },
          steps: [
            // Step 0: Celebrate Wins & Auto Accomplishments
            Step(
              title: const Text('1. Celebrate Wins & Pencapaian'),
              isActive: _step >= 0,
              content: nodesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (allNodes) {
                  final completedInPeriod = allNodes.where((node) {
                    if (!node.isDone && node.status != NodeStatus.done) {
                      return false;
                    }
                    final date = node.updatedAt;
                    return date.isAfter(
                          widget.start.subtract(const Duration(days: 1)),
                        ) &&
                        date.isBefore(widget.end.add(const Duration(days: 1)));
                  }).toList();

                  final completedTasks = completedInPeriod
                      .where((n) => n.type == NodeType.task)
                      .length;
                  final habitLogs = completedInPeriod
                      .where((n) => n.type == NodeType.habit)
                      .length;
                  final goalsProgress = completedInPeriod
                      .where((n) => n.type == NodeType.goal)
                      .length;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ringkasan Pencapaian Otomatis Periode Ini:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: Icon(
                              NodeVisuals.icon(NodeType.task),
                              color: semantic.success,
                              size: 16,
                            ),
                            label: Text('$completedTasks Tugas Selesai'),
                          ),
                          Chip(
                            avatar: Icon(
                              NodeVisuals.icon(NodeType.habit),
                              color: NodeVisuals.color(context, NodeType.habit),
                              size: 16,
                            ),
                            label: Text('$habitLogs Habit Terceklist'),
                          ),
                          if (goalsProgress > 0)
                            Chip(
                              avatar: Icon(
                                NodeVisuals.icon(NodeType.goal),
                                color: NodeVisuals.color(
                                  context,
                                  NodeType.goal,
                                ),
                                size: 16,
                              ),
                              label: Text('$goalsProgress Target Tercapai'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Catat Wins & Hal Positif Lainnya:'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _winsController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText:
                              '- Berhasil selesaikan modul X\n- Tidur teratur seminggu',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Step 1: Unfinished Tasks & Habit Audit
            Step(
              title: const Text('2. Audit Tugas Overdue & Habit'),
              isActive: _step >= 1,
              content: nodesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (allNodes) {
                  final overdue = allNodes
                      .where((node) {
                        final dueDate = node.dueDate;
                        return node.type == NodeType.task &&
                            !node.isArchived &&
                            !_isComplete(node) &&
                            dueDate != null &&
                            dueDate.dateOnly.isBefore(widget.today.dateOnly);
                      })
                      .take(4)
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (overdue.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '🎉 Tidak ada tugas overdue! Produktivitas bersih.',
                          ),
                        )
                      else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Overdue Tasks (${overdue.length}):',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.forward, size: 14),
                              label: const Text('Reschedule Semua ke Hari Ini'),
                              onPressed: () async {
                                for (final n in overdue) {
                                  await ref
                                      .read(mindmapMutationControllerProvider)
                                      .rescheduleDueDate(
                                        n,
                                        dueDate: widget.today.dateOnly,
                                      );
                                }
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        for (final n in overdue)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    await ref
                                        .read(mindmapMutationControllerProvider)
                                        .rescheduleDueDate(
                                          n,
                                          dueDate: widget.today.dateOnly,
                                        );
                                    setState(() {});
                                  },
                                  child: const Text('Hari Ini'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await ref
                                        .read(mindmapMutationControllerProvider)
                                        .rescheduleDueDate(
                                          n,
                                          dueDate: widget.today.dateOnly
                                              .addDays(7),
                                        );
                                    setState(() {});
                                  },
                                  child: const Text('+7 Hari'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),

            // Step 2: Goal Milestones & Alignment
            Step(
              title: const Text('3. Alignment Target & Goal'),
              isActive: _step >= 2,
              content: nodesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
                data: (allNodes) {
                  final activeGoals = allNodes
                      .where((n) => n.type == NodeType.goal && !n.isArchived)
                      .take(3)
                      .toList();

                  if (activeGoals.isEmpty) {
                    return const Text('Belum ada Goal aktif tersimpan.');
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Progres Target Aktif & Next Action:'),
                      const SizedBox(height: 8),
                      for (final goal in activeGoals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      goal.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    LinearProgressIndicator(
                                      value: goal.progress.clamp(0.0, 1.0),
                                      minHeight: 4,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.add_task, size: 18),
                                tooltip: 'Tambah Next Action',
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final actionNode = MindmapNode(
                                    id: 'goal-action-${now.microsecondsSinceEpoch}',
                                    type: NodeType.task,
                                    title: 'Next action: ${goal.title}',
                                    day: widget.today.dateOnly,
                                    createdAt: now,
                                    updatedAt: now,
                                    body:
                                        'Aksi turunan dari goal [[${goal.title}]]',
                                    priority: NodePriority.high,
                                    relatedNodeIds: [goal.id],
                                    dueDate: widget.today.dateOnly,
                                  );
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await ref
                                      .read(mindmapRepositoryProvider)
                                      .saveNode(actionNode);
                                  invalidateMindmapState(
                                    ref,
                                    day: widget.today.dateOnly,
                                  );
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Action dibuat untuk ${goal.title}!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Step 3: Mindset, Mood & Energy Rating
            Step(
              title: const Text('4. Rating Mood, Energi & Rasa Syukur'),
              isActive: _step >= 3,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Level Energi & Mood: ${_moodEmoji(_moodRating)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _moodRating,
                    min: 1.0,
                    max: 5.0,
                    divisions: 8,
                    label: _moodRating.toStringAsFixed(1),
                    onChanged: (val) => setState(() => _moodRating = val),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _gratitudeController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Jurnal Rasa Syukur (Gratitude)',
                      hintText:
                          'Apa yang membuat Anda paling bersyukur minggu/bulan ini?',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lessonsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Pelajaran Penting (Lessons Learned)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),

            // Step 4: Next Cycle Focus & Intention Setting
            Step(
              title: const Text('5. Fokus & Prioritas Siklus Depan'),
              isActive: _step >= 4,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tentukan 3 prioritas utama untuk minggu/bulan mendatang:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nextFocusController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText:
                          '- Prioritas 1: Selesaikan modul X\n- Prioritas 2: Rutin olahraga 3x\n- Prioritas 3: Evaluasi budget',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Buat Node Tugas Otomatis dari Prioritas di atas',
                    ),
                    value: _autoCreateTasks,
                    onChanged: (val) =>
                        setState(() => _autoCreateTasks = val ?? true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_saveError != null)
          Expanded(
            child: Text(
              'Review tidak tersimpan: $_saveError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ],
    );
  }

  Future<MindmapNode> _completeReview() async {
    final now = DateTime.now();
    final start = widget.start.dateOnly;
    final end = widget.end.dateOnly;
    final periodKey = widget.isMonthly
        ? '${start.year}-${start.month.toString().padLeft(2, '0')}'
        : '${dayKey(start)}_${dayKey(end)}';
    final tag = widget.isMonthly ? 'monthly-review' : 'weekly-review';
    final title = widget.isMonthly
        ? 'Monthly Review — $periodKey'
        : 'Weekly Review — ${dayKey(start)} to ${dayKey(end)}';
    final wins = _winsController.text.trim();
    final gratitude = _gratitudeController.text.trim();
    final lessons = _lessonsController.text.trim();
    final nextFocus = _nextFocusController.text.trim();

    final body = StringBuffer()
      ..writeln('### Wins & Accomplishments')
      ..writeln(wins)
      ..writeln('\n### Gratitude')
      ..writeln(gratitude)
      ..writeln('\n### Lessons')
      ..writeln(lessons)
      ..writeln('\n### Next Focus Priorities')
      ..writeln(nextFocus)
      ..writeln('\n### Mood & Energy Level')
      ..writeln(
        '${_moodRating.toStringAsFixed(1)}/5.0 (${_moodEmoji(_moodRating)})',
      );
    final existing = widget.existingReview;
    final node = MindmapNode(
      id: existing?.id ?? '${tag}_$periodKey',
      type: NodeType.journal,
      title: title,
      body: body.toString(),
      day: widget.today.dateOnly,
      tags: [tag],
      data: {
        'journal': {
          'isWeeklyReview': !widget.isMonthly,
          'isMonthlyReview': widget.isMonthly,
          'periodKey': periodKey,
          'periodStart': dayKey(start),
          'periodEnd': dayKey(end),
          'wins': wins,
          'gratitude': gratitude,
          'lessons': lessons,
          'nextFocus': nextFocus,
          'moodRating': _moodRating,
        },
      },
      position: existing?.position ?? const CanvasPosition(0, 0),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final savedReview = await ref
        .read(mindmapMutationControllerProvider)
        .saveNode(node);

    // Auto-create task nodes for next cycle if enabled
    if (_autoCreateTasks && nextFocus.isNotEmpty) {
      final lines = nextFocus.split('\n').where((l) => l.trim().isNotEmpty);
      final repo = ref.read(mindmapRepositoryProvider);
      final nextCycleStart = widget.end.dateOnly.addDays(1);

      for (final line in lines) {
        final cleanTitle = line.replaceAll(RegExp(r'^[-*\d.]+\s*'), '').trim();
        if (cleanTitle.isEmpty) continue;

        final taskNode = MindmapNode(
          id: 'focus-task-${now.microsecondsSinceEpoch}-${cleanTitle.hashCode}',
          type: NodeType.task,
          title: cleanTitle,
          day: nextCycleStart,
          createdAt: now,
          updatedAt: now,
          priority: NodePriority.high,
          tags: const ['next-cycle-priority'],
          dueDate: nextCycleStart,
          relatedNodeIds: [savedReview.id],
        );
        await repo.saveNode(taskNode);
      }
      invalidateMindmapState(ref, day: nextCycleStart);
    }

    return savedReview;
  }
}

bool _isComplete(MindmapNode node) {
  return node.isDone || node.status == NodeStatus.done || node.progress >= 1;
}

Map<String, Object?> _sectionData(Map<String, Object?>? data, String key) {
  final value = data?[key];
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

String _stringValue(Object? value) => value is String ? value : '';
