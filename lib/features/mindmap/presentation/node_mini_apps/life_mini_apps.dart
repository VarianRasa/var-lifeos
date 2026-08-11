import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../insights/application/expense_budget_analytics.dart';
import '../../application/mindmap_providers.dart';
import '../../domain/habit_completion.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_mini_app_data.dart';
import '../../domain/node_type_payloads.dart';
import 'node_mini_app_common.dart';

Widget? buildLifeMiniApp({
  required MindmapNode node,
  required ValueChanged<MindmapNode> onChanged,
  required Widget editor,
  Future<void> Function()? onReceiptAdd,
  Future<void> Function(ResourceAsset receipt)? onReceiptOpen,
  Future<void> Function(ResourceAsset receipt)? onReceiptExport,
  Future<void> Function(ResourceAsset receipt)? onReceiptDelete,
}) => switch (node.type) {
  NodeType.habit || NodeType.routine => HabitMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  NodeType.fit => FitnessMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  NodeType.expense => ExpenseMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
    onReceiptAdd: onReceiptAdd,
    onReceiptOpen: onReceiptOpen,
    onReceiptExport: onReceiptExport,
    onReceiptDelete: onReceiptDelete,
  ),
  NodeType.itinerary => ItineraryMiniApp(node: node, editor: editor),
  _ => null,
};

class HabitMiniApp extends StatelessWidget {
  const HabitMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final stats = calculateHabitStreakStats(node, DateTime.now());
    final section = nodeMiniAppSection(node, 'habit');
    final reminderEnabled = section['reminderEnabled'] == true;
    final reminderTime = section['reminderTime'] as String? ?? '08:00';
    final badges = <String>[
      if (stats.maxStreak >= 7) '7-day streak',
      if (stats.maxStreak >= 30) '30-day streak',
      if (stats.totalCompletions >= 100) 'Century club',
      if (stats.completionRate30Days >= 0.8) 'Consistency 80%',
    ];

    return _LifeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Habit streak lab',
          subtitle: 'Year heatmap, badges, consistency, and reminder settings.',
          icon: Icons.local_fire_department_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Current streak',
                    value: '${stats.currentStreak} days',
                    icon: Icons.local_fire_department,
                  ),
                  MiniAppStat(
                    label: 'Best streak',
                    value: '${stats.maxStreak} days',
                    icon: Icons.emoji_events_outlined,
                  ),
                  MiniAppStat(
                    label: 'Completions',
                    value: '${stats.totalCompletions}',
                    icon: Icons.check_circle_outline,
                  ),
                  MiniAppStat(
                    label: '30-day rate',
                    value: '${(stats.completionRate30Days * 100).round()}%',
                    icon: Icons.insights,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _HabitYearHeatmap(node: node),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: badges.isEmpty
                    ? const <Widget>[
                        Chip(label: Text('Next badge: 7-day streak')),
                      ]
                    : <Widget>[
                        for (final badge in badges)
                          Chip(
                            avatar: const Icon(
                              Icons.workspace_premium,
                              size: 16,
                            ),
                            label: Text(badge),
                          ),
                      ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily reminder'),
                subtitle: Text(
                  reminderEnabled
                      ? 'Reminder preference saved for $reminderTime'
                      : 'Disabled',
                ),
                value: reminderEnabled,
                onChanged: (value) => onChanged(
                  updateNodeMiniAppSection(node, 'habit', <String, Object?>{
                    'reminderEnabled': value,
                    'reminderTime': reminderTime,
                  }),
                ),
              ),
              if (reminderEnabled)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final time in const <String>[
                      '07:00',
                      '08:00',
                      '18:00',
                      '21:00',
                    ])
                      ChoiceChip(
                        label: Text(time),
                        selected: reminderTime == time,
                        onSelected: (_) => onChanged(
                          updateNodeMiniAppSection(
                            node,
                            'habit',
                            <String, Object?>{
                              'reminderEnabled': true,
                              'reminderTime': time,
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'Reminder time is stored locally. OS notification delivery uses app reminder scheduler when enabled in Settings.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }
}

class FitnessMiniApp extends StatelessWidget {
  const FitnessMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final fit = FitPayload.fromNode(node);
    return _LifeScroll(
      children: [
        MiniAppSection(
          title: 'Fitness dashboard',
          subtitle: 'Activity rings, workout detail, and health sync status.',
          icon: Icons.fitness_center,
          child: Column(
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 16,
                children: [
                  _ProgressRing(
                    label: 'Steps',
                    value: fit.steps ?? 0,
                    target: fit.stepGoal,
                    unit: '',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  _ProgressRing(
                    label: 'Water',
                    value: fit.water ?? 0,
                    target: fit.waterGoal,
                    unit: fit.waterUnit,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  _ProgressRing(
                    label: 'Active',
                    value: fit.durationMinutes ?? 0,
                    target: fit.durationGoalMinutes,
                    unit: 'min',
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  _ProgressRing(
                    label: 'Calories',
                    value: fit.calories ?? 0,
                    target: fit.calorieGoal,
                    unit: 'kcal',
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.sports_gymnastics),
                title: Text(
                  fit.workout.isEmpty ? 'No workout selected' : fit.workout,
                ),
                subtitle: Text('${fit.intensity} intensity'),
                trailing: fit.completed
                    ? const Chip(label: Text('Completed'))
                    : const Chip(label: Text('Planned')),
              ),
              ListTile(
                leading: Icon(
                  fit.syncEnabled ? Icons.sync : Icons.sync_disabled,
                ),
                title: Text(
                  fit.syncEnabled ? 'Health sync enabled' : 'Health sync off',
                ),
                subtitle: Text(
                  fit.syncSource.isEmpty
                      ? 'No health provider connected'
                      : '${fit.syncSource}${fit.syncedAt.isEmpty ? '' : ' · ${fit.syncedAt}'}',
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Workout routine',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('fitness-exercise-add'),
                    tooltip: 'Add exercise',
                    onPressed: () {
                      final exerciseId = _nextFitnessId(
                        'exercise',
                        fit.exercises.map((exercise) => exercise.id),
                      );
                      _emitFitness(
                        fit.copyWith(
                          exercises: <FitnessExercise>[
                            ...fit.exercises,
                            FitnessExercise(
                              id: exerciseId,
                              name: 'New exercise',
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (fit.exercises.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.fitness_center,
                  message: 'Add exercises and sets to build workout routine.',
                )
              else
                for (final exercise in fit.exercises)
                  Card(
                    key: ValueKey('fitness-exercise-${exercise.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: ValueKey(
                                    'fitness-exercise-name-${exercise.id}',
                                  ),
                                  initialValue: exercise.name,
                                  decoration: const InputDecoration(
                                    labelText: 'Exercise',
                                  ),
                                  onChanged: (value) => _updateExercise(
                                    fit,
                                    exercise.copyWith(name: value),
                                  ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey(
                                  'fitness-exercise-delete-${exercise.id}',
                                ),
                                tooltip: 'Delete exercise',
                                onPressed: () => _emitFitness(
                                  fit.copyWith(
                                    exercises: fit.exercises
                                        .where((item) => item.id != exercise.id)
                                        .toList(),
                                  ),
                                ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          for (final set in exercise.sets)
                            Row(
                              key: ValueKey(
                                'fitness-set-${exercise.id}-${set.id}',
                              ),
                              children: [
                                Checkbox(
                                  value: set.completed,
                                  onChanged: (value) => _updateSet(
                                    fit,
                                    exercise,
                                    set.copyWith(completed: value ?? false),
                                  ),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey(
                                      'fitness-set-reps-${exercise.id}-${set.id}',
                                    ),
                                    initialValue: '${set.reps}',
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Reps',
                                    ),
                                    onChanged: (value) {
                                      final reps = int.tryParse(value);
                                      if (reps != null && reps > 0) {
                                        _updateSet(
                                          fit,
                                          exercise,
                                          set.copyWith(reps: reps),
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey(
                                      'fitness-set-weight-${exercise.id}-${set.id}',
                                    ),
                                    initialValue: set.weight?.toString() ?? '',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Weight',
                                    ),
                                    onChanged: (value) => _updateSet(
                                      fit,
                                      exercise,
                                      value.trim().isEmpty
                                          ? set.copyWith(clearWeight: true)
                                          : set.copyWith(
                                              weight: double.tryParse(value),
                                            ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete set',
                                  onPressed: () => _updateExercise(
                                    fit,
                                    exercise.copyWith(
                                      sets: exercise.sets
                                          .where((item) => item.id != set.id)
                                          .toList(),
                                    ),
                                  ),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: ValueKey('fitness-set-add-${exercise.id}'),
                              onPressed: () => _updateExercise(
                                fit,
                                exercise.copyWith(
                                  sets: <FitnessWorkoutSet>[
                                    ...exercise.sets,
                                    FitnessWorkoutSet(
                                      id: _nextFitnessId(
                                        'set',
                                        exercise.sets.map((set) => set.id),
                                      ),
                                      reps: 10,
                                    ),
                                  ],
                                ),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Add set'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }

  void _emitFitness(FitPayload payload) => onChanged(
    node.copyWith(data: payload.toData(node.data), updatedAt: DateTime.now()),
  );

  void _updateExercise(FitPayload payload, FitnessExercise updated) =>
      _emitFitness(
        payload.copyWith(
          exercises: <FitnessExercise>[
            for (final exercise in payload.exercises)
              exercise.id == updated.id ? updated : exercise,
          ],
        ),
      );

  void _updateSet(
    FitPayload payload,
    FitnessExercise exercise,
    FitnessWorkoutSet updated,
  ) => _updateExercise(
    payload,
    exercise.copyWith(
      sets: <FitnessWorkoutSet>[
        for (final set in exercise.sets) set.id == updated.id ? updated : set,
      ],
    ),
  );
}

String _nextFitnessId(String prefix, Iterable<String> ids) {
  final used = ids.toSet();
  var suffix = 1;
  while (used.contains('$prefix-$suffix')) {
    suffix++;
  }
  return '$prefix-$suffix';
}

class ExpenseMiniApp extends ConsumerWidget {
  const ExpenseMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    this.onReceiptAdd,
    this.onReceiptOpen,
    this.onReceiptExport,
    this.onReceiptDelete,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;
  final Future<void> Function()? onReceiptAdd;
  final Future<void> Function(ResourceAsset receipt)? onReceiptOpen;
  final Future<void> Function(ResourceAsset receipt)? onReceiptExport;
  final Future<void> Function(ResourceAsset receipt)? onReceiptDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expense = ExpensePayload.fromNode(node);
    final section = nodeMiniAppSection(node, 'expense');
    final budget = (section['monthlyBudget'] as num?)?.toDouble() ?? 0;
    final currency = expense.currency.isEmpty
        ? 'USD'
        : expense.currency.trim().toUpperCase();
    final amount = expense.amount ?? 0;
    final nodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? const [];
    final monthly = ExpenseBudgetAnalytics.computeMonthly(
      nodes: nodes,
      month: node.day,
      defaultBudgets: <String, double>{if (budget > 0) 'General': budget},
    ).where((summary) => summary.currency == currency).firstOrNull;
    return _LifeScroll(
      children: [
        MiniAppSection(
          title: 'Expense & budget',
          subtitle: 'Transaction summary, category allocation, and receipts.',
          icon: Icons.account_balance_wallet_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label:
                        expense.transactionType == ExpenseTransactionType.income
                        ? 'Income'
                        : 'Expense',
                    value: '$currency ${amount.toStringAsFixed(2)}',
                    icon:
                        expense.transactionType == ExpenseTransactionType.income
                        ? Icons.south_west
                        : Icons.north_east,
                  ),
                  MiniAppStat(
                    label: 'Month expenses',
                    value:
                        '$currency ${(monthly?.expenses ?? 0).toStringAsFixed(2)}',
                    icon: Icons.calendar_month_outlined,
                  ),
                  MiniAppStat(
                    label: 'Month income',
                    value:
                        '$currency ${(monthly?.income ?? 0).toStringAsFixed(2)}',
                    icon: Icons.account_balance_outlined,
                  ),
                  MiniAppStat(
                    label: 'Month net',
                    value:
                        '$currency ${(monthly?.net ?? 0).toStringAsFixed(2)}',
                    icon: Icons.balance_outlined,
                  ),
                  MiniAppStat(
                    label: 'Category',
                    value: expense.category.isEmpty
                        ? 'Uncategorized'
                        : expense.category,
                    icon: Icons.category_outlined,
                  ),
                  MiniAppStat(
                    label: 'Receipts',
                    value: '${expense.receipts.length}',
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: budget == 0 ? '' : budget.toStringAsFixed(0),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Monthly budget ($currency)',
                  prefixIcon: const Icon(Icons.savings_outlined),
                ),
                onFieldSubmitted: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed == null || parsed < 0) return;
                  onChanged(
                    updateNodeMiniAppSection(node, 'expense', <String, Object?>{
                      'monthlyBudget': parsed,
                    }),
                  );
                },
              ),
              if (budget > 0) ...[
                const SizedBox(height: 14),
                MiniAppProgressMeter(
                  label: 'Monthly budget usage',
                  value: (monthly?.expenses ?? 0) / budget,
                  detail:
                      '$currency ${(monthly?.expenses ?? 0).toStringAsFixed(2)} / ${budget.toStringAsFixed(2)}',
                  color: (monthly?.expenses ?? 0) > budget
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ],
              const SizedBox(height: 16),
              if (monthly == null ||
                  monthly.categories.every((item) => item.totalSpent == 0))
                const MiniAppEmptyState(
                  icon: Icons.pie_chart_outline,
                  message: 'No expense categories recorded this month.',
                )
              else
                _MonthlyCategoryChart(summary: monthly, currency: currency),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Receipt gallery',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (onReceiptAdd != null)
                    IconButton(
                      key: const ValueKey('expense-receipt-add'),
                      tooltip: 'Add receipt',
                      onPressed: () => onReceiptAdd!(),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (expense.receipts.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'Add receipt images or files for this transaction.',
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final receipt in expense.receipts)
                      _ReceiptCard(
                        receipt: receipt,
                        onOpen: onReceiptOpen == null
                            ? null
                            : () => onReceiptOpen!(receipt),
                        onExport: onReceiptExport == null
                            ? null
                            : () => onReceiptExport!(receipt),
                        onDelete: onReceiptDelete == null
                            ? null
                            : () => onReceiptDelete!(receipt),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  const _ReceiptCard({
    required this.receipt,
    this.onOpen,
    this.onExport,
    this.onDelete,
  });

  final ResourceAsset receipt;
  final Future<void> Function()? onOpen;
  final Future<void> Function()? onExport;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = receipt.isImage
        ? ref.watch(nodeAttachmentPreviewBytesProvider(receipt.attachmentId))
        : null;
    return SizedBox(
      key: ValueKey('expense-receipt-${receipt.id}'),
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onOpen,
              child: SizedBox(
                height: 104,
                child: preview == null
                    ? Icon(
                        receipt.isImage
                            ? Icons.image_outlined
                            : Icons.description_outlined,
                        size: 40,
                      )
                    : preview.when(
                        data: (bytes) => bytes == null
                            ? const Icon(Icons.broken_image_outlined, size: 40)
                            : Image.memory(bytes, fit: BoxFit.cover),
                        loading: () => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        error: (_, _) =>
                            const Icon(Icons.broken_image_outlined, size: 40),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      receipt.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<_ReceiptAction>(
                    key: ValueKey('expense-receipt-actions-${receipt.id}'),
                    tooltip: 'Receipt actions',
                    onSelected: (action) => switch (action) {
                      _ReceiptAction.open => onOpen?.call(),
                      _ReceiptAction.export => onExport?.call(),
                      _ReceiptAction.delete => onDelete?.call(),
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _ReceiptAction.open,
                        enabled: onOpen != null,
                        child: const Text('Open'),
                      ),
                      PopupMenuItem(
                        value: _ReceiptAction.export,
                        enabled: onExport != null,
                        child: const Text('Export'),
                      ),
                      PopupMenuItem(
                        value: _ReceiptAction.delete,
                        enabled: onDelete != null,
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReceiptAction { open, export, delete }

class ItineraryMiniApp extends StatelessWidget {
  const ItineraryMiniApp({required this.node, required this.editor, super.key});

  final MindmapNode node;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final payload = ItineraryPayload.fromNode(node);
    final insights = ItineraryInsights.fromPayload(payload);
    final agenda = [...payload.agenda]
      ..sort((left, right) {
        final day = left.dayOffset.compareTo(right.dayOffset);
        return day != 0 ? day : left.startMinutes.compareTo(right.startMinutes);
      });
    return _LifeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Trip command center',
          subtitle: 'Agenda, bookings, packing, readiness, and budget.',
          icon: Icons.travel_explore,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Readiness',
                    value: '${insights.readinessScore}%',
                    icon: Icons.fact_check_outlined,
                  ),
                  MiniAppStat(
                    label: 'Agenda',
                    value:
                        '${insights.completedAgenda}/${payload.agenda.length}',
                    icon: Icons.event_note_outlined,
                  ),
                  MiniAppStat(
                    label: 'Bookings',
                    value:
                        '${insights.confirmedBookings}/${payload.bookings.length}',
                    icon: Icons.confirmation_number_outlined,
                  ),
                  MiniAppStat(
                    label: 'Packing',
                    value: '${insights.packedItems}/${payload.packing.length}',
                    icon: Icons.luggage_outlined,
                  ),
                  MiniAppStat(
                    label: 'Planned',
                    value:
                        '${payload.currency} ${insights.totalPlannedCost.toStringAsFixed(0)}',
                    icon: Icons.event_note_outlined,
                  ),
                  MiniAppStat(
                    label: 'Actual',
                    value:
                        '${payload.currency} ${payload.actualCost.toStringAsFixed(0)}',
                    icon: Icons.receipt_long_outlined,
                  ),
                  MiniAppStat(
                    label: 'Budget',
                    value: payload.budget <= 0
                        ? 'Unset'
                        : '${payload.currency} ${payload.budget.toStringAsFixed(0)}',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              MiniAppProgressMeter(
                label: 'Trip readiness',
                value: insights.readinessScore / 100,
              ),
              const SizedBox(height: 16),
              Text(
                '${payload.destination.isEmpty ? 'Destination unset' : payload.destination} · ${dayKey(payload.startDate)} to ${dayKey(payload.endDate)} · ${payload.timezone}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (agenda.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.event_busy,
                  message: 'Add itinerary agenda items below.',
                )
              else
                for (final item in agenda)
                  ListTile(
                    leading: CircleAvatar(child: Text('${item.dayOffset + 1}')),
                    title: Text(item.title),
                    subtitle: Text(
                      '${_timeLabel(item.startMinutes)} · ${item.durationMinutes} min · ${item.location.isEmpty ? item.category : item.location}',
                    ),
                    trailing: item.completed
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : Text(
                            '${payload.currency} ${item.cost.toStringAsFixed(0)}',
                          ),
                  ),
              const Divider(),
              MiniAppProgressMeter(
                label: 'Planned budget usage',
                value: payload.budget <= 0
                    ? 0
                    : insights.totalPlannedCost / payload.budget,
                detail: payload.budget <= 0
                    ? 'Budget unset'
                    : '${payload.currency} ${insights.totalPlannedCost.toStringAsFixed(0)} / ${payload.budget.toStringAsFixed(0)}',
                color:
                    payload.budget > 0 &&
                        insights.totalPlannedCost > payload.budget
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              const SizedBox(height: 10),
              MiniAppProgressMeter(
                label: 'Actual budget usage',
                value: payload.budget <= 0
                    ? 0
                    : payload.actualCost / payload.budget,
                detail: payload.budget <= 0
                    ? 'Budget unset'
                    : '${payload.currency} ${payload.actualCost.toStringAsFixed(0)} / ${payload.budget.toStringAsFixed(0)}',
                color: payload.budget > 0 && payload.actualCost > payload.budget
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              if (insights.warnings.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final warning in insights.warnings)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(warning),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        editor,
      ],
    );
  }
}

class _HabitYearHeatmap extends StatelessWidget {
  const _HabitYearHeatmap({required this.node});

  final MindmapNode node;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().dateOnly;
    final completionKeys = habitCompletionKeys(node).toSet();
    final start = today.subtract(const Duration(days: 364));
    final weeks = <List<DateTime>>[];
    for (var week = 0; week < 53; week++) {
      weeks.add(<DateTime>[
        for (var day = 0; day < 7; day++)
          start.add(Duration(days: week * 7 + day)),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '365-day consistency',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Semantics(
            label:
                '${completionKeys.length} habit completions in stored history',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final week in weeks)
                  Column(
                    children: [
                      for (final day in week)
                        Tooltip(
                          message:
                              '${dayKey(day)}: ${completionKeys.contains(dayKey(day)) ? 'completed' : 'not completed'}',
                          child: Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: day.isAfter(today)
                                  ? Colors.transparent
                                  : completionKeys.contains(dayKey(day))
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
  });

  final String label;
  final double value;
  final double target;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = target <= 0
        ? 0.0
        : (value / target).clamp(0, 1).toDouble();
    return Semantics(
      label:
          '$label ${value.toStringAsFixed(0)} $unit of ${target.toStringAsFixed(0)} $unit',
      child: SizedBox.square(
        dimension: 126,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 112,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 10,
                color: color,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(unit, style: Theme.of(context).textTheme.labelSmall),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyCategoryChart extends StatelessWidget {
  const _MonthlyCategoryChart({required this.summary, required this.currency});

  final ExpenseCurrencySummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spentCategories = summary.categories
        .where((item) => item.totalSpent > 0)
        .toList();
    final categories = <(String, double)>[
      for (final item in spentCategories.take(7))
        (item.category, item.totalSpent),
      if (spentCategories.length > 7)
        (
          'Other',
          spentCategories
              .skip(7)
              .fold<double>(0, (sum, item) => sum + item.totalSpent),
        ),
    ];
    final total = categories.fold<double>(0, (value, item) => value + item.$2);
    final colors = Theme.of(context).colorScheme;
    final palette = Theme.of(context).brightness == Brightness.dark
        ? const <Color>[
            Color(0xFF3987E5),
            Color(0xFFD95926),
            Color(0xFF199E70),
            Color(0xFFC98500),
            Color(0xFFD55181),
            Color(0xFF008300),
            Color(0xFF9085E9),
            Color(0xFFE66767),
          ]
        : const <Color>[
            Color(0xFF2A78D6),
            Color(0xFFEB6834),
            Color(0xFF1BAF7A),
            Color(0xFFEDA100),
            Color(0xFFE87BA4),
            Color(0xFF008300),
            Color(0xFF4A3AA7),
            Color(0xFFE34948),
          ];
    final description = categories
        .map((item) => '${item.$1} $currency ${item.$2.toStringAsFixed(2)}')
        .join(', ');
    return Semantics(
      container: true,
      label: 'Monthly category expenses, $description',
      child: Column(
        key: const ValueKey('expense-monthly-category-chart'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly category allocation',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = SizedBox.square(
                dimension: 180,
                child: CustomPaint(
                  key: const ValueKey('expense-monthly-category-pie'),
                  painter: _ExpenseCategoryPiePainter(
                    values: [for (final item in categories) item.$2],
                    colors: palette.take(categories.length).toList(),
                    surface: colors.surface,
                  ),
                ),
              );
              final legend = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < categories.length; index++)
                    Tooltip(
                      message:
                          '${categories[index].$1}: $currency ${categories[index].$2.toStringAsFixed(2)}',
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: palette[index],
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${categories[index].$1} · ${total == 0 ? 0 : (categories[index].$2 / total * 100).round()}% · $currency ${categories[index].$2.toStringAsFixed(0)}',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [chart, const SizedBox(height: 12), legend],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  chart,
                  const SizedBox(width: 20),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExpenseCategoryPiePainter extends CustomPainter {
  const _ExpenseCategoryPiePainter({
    required this.values,
    required this.colors,
    required this.surface,
  });

  final List<double> values;
  final List<Color> colors;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      canvas.drawArc(
        rect.deflate(2),
        start,
        math.max(0, sweep - 0.015),
        true,
        Paint()..color = colors[index],
      );
      start += sweep;
    }
    canvas.drawCircle(
      rect.center,
      size.shortestSide * 0.27,
      Paint()..color = surface,
    );
  }

  @override
  bool shouldRepaint(covariant _ExpenseCategoryPiePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.colors != colors ||
      oldDelegate.surface != surface;
}

String _timeLabel(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _LifeScroll extends StatelessWidget {
  const _LifeScroll({required this.children, this.maxWidth = 900});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}
