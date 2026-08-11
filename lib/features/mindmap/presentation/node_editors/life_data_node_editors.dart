import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_utils.dart';
import '../../application/fitness_health_providers.dart';
import '../../application/weather_providers.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_presentation.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/weather_snapshot.dart';
import 'knowledge_node_editors.dart';
import 'productivity_node_editors.dart';

final class ConvertEmptyNodeAction {
  const ConvertEmptyNodeAction(this.targetType);
  final NodeType targetType;
}

Widget buildLifeDataNodeContent(NodeRenderContext context) {
  if (!_isLifeData(context.node.type)) {
    return buildKnowledgeNodeContent(context);
  }
  if (context.node.type == NodeType.fit) return _FitnessNodeContent(context);
  if (context.node.type == NodeType.expense) {
    return _ExpenseNodeContent(context);
  }
  if (context.node.type == NodeType.mood) return _MoodNodeContent(context);
  return _LifeDataContent(context);
}

Widget buildLifeDataNodeInlineEditor(NodeEditContext context) =>
    _isLifeData(context.node.type)
    ? _LifeDataEditor(context)
    : buildKnowledgeNodeInlineEditor(context);

bool _isLifeData(NodeType type) => switch (type) {
  NodeType.event ||
  NodeType.contact ||
  NodeType.metric ||
  NodeType.expense ||
  NodeType.mood ||
  NodeType.weather ||
  NodeType.fit ||
  NodeType.empty => true,
  _ => false,
};

final class _LifeDataContent extends StatelessWidget {
  const _LifeDataContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final preset = context.effectivePreset;
    final compact = preset == NodeSizePreset.compact;
    final body = context.node.type == NodeType.weather
        ? normalizeLegacyWeatherBody(context.node.body)
        : context.node.body;
    final detail = switch (preset) {
      NodeSizePreset.compact => '',
      NodeSizePreset.standard => _summary(context.node),
      NodeSizePreset.large => '${_summary(context.node)}\n$body',
      NodeSizePreset.wide => '${_summary(context.node)}    $body',
      _ => _summary(context.node),
    };
    return Container(
      key: ValueKey(
        'life-data-${context.node.type.name}-${context.effectivePreset.name}',
      ),
      color: Theme.of(buildContext).colorScheme.surface,
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(key: ValueKey('life-data-content-${preset.name}')),
          Text(
            context.node.title,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                detail,
                maxLines: preset == NodeSizePreset.standard ? 2 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _ExpenseNodeContent extends StatelessWidget {
  const _ExpenseNodeContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final colors = theme.colorScheme;
    final payload = ExpensePayload.fromNode(context.node);
    final preset = context.effectivePreset;
    final compact = preset == NodeSizePreset.compact;
    final currency = payload.currency.isEmpty ? 'IDR' : payload.currency;
    final amountText = payload.amount == null
        ? 'No amount set'
        : '$currency ${payload.amount!.toStringAsFixed(0)}';

    return Container(
      key: ValueKey('life-data-expense-${preset.name}'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(left: BorderSide(color: colors.error, width: 4)),
      ),
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: compact ? 16 : 20,
                color: colors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.node.title.isEmpty ? 'Expense' : context.node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amountText,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (payload.category.isNotEmpty) ...[
                  Chip(
                    label: Text(payload.category),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelStyle: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: 6),
                ],
                if (payload.merchant.isNotEmpty)
                  Expanded(
                    child: Text(
                      payload.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final class _MoodNodeContent extends StatelessWidget {
  const _MoodNodeContent(this.context);
  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final colors = theme.colorScheme;
    final payload = MoodPayload.fromNode(context.node);
    final preset = context.effectivePreset;
    final compact = preset == NodeSizePreset.compact;

    final moodLabel = payload.mood ?? 'Neutral';
    final energy = payload.energy ?? 3.0;

    IconData moodIcon;
    Color moodColor;
    if (energy >= 4) {
      moodIcon = Icons.sentiment_very_satisfied_rounded;
      moodColor = Colors.amber;
    } else if (energy >= 3) {
      moodIcon = Icons.sentiment_satisfied_rounded;
      moodColor = Colors.lightGreen;
    } else if (energy >= 2) {
      moodIcon = Icons.sentiment_neutral_rounded;
      moodColor = Colors.orange;
    } else {
      moodIcon = Icons.sentiment_dissatisfied_rounded;
      moodColor = Colors.deepOrange;
    }

    return Container(
      key: ValueKey('life-data-mood-${preset.name}'),
      color: colors.surface,
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(moodIcon, size: compact ? 20 : 28, color: moodColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.node.title.isEmpty
                          ? moodLabel
                          : context.node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Energy: ${energy.toInt()}/5',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!compact && context.node.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              context.node.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

final class _FitnessNodeContent extends StatelessWidget {
  const _FitnessNodeContent(this.context);

  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final colors = theme.colorScheme;
    final payload = FitPayload.fromNode(context.node);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            this.context.effectivePreset == NodeSizePreset.compact ||
            constraints.maxWidth < 250 ||
            constraints.maxHeight < 170;
        final stepProgress = _fitProgress(payload.steps, payload.stepGoal);
        final waterProgress = _fitProgress(payload.water, payload.waterGoal);
        final activityProgress = _fitProgress(
          payload.durationMinutes,
          payload.durationGoalMinutes,
        );
        final workout = payload.workout.trim().isEmpty
            ? 'No activity selected'
            : payload.workout.trim();
        return Container(
          key: ValueKey('life-data-fit-${this.context.effectivePreset.name}'),
          color: colors.surface,
          padding: EdgeInsets.all(compact ? 10 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    payload.completed
                        ? Icons.fitness_center_rounded
                        : Icons.directions_run_rounded,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      this.context.node.title.trim().isEmpty
                          ? workout
                          : this.context.node.title.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (payload.completed)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                workout,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                _FitnessProgressLine(
                  icon: Icons.directions_walk_rounded,
                  label:
                      '${_fitNumber(payload.steps)} / ${_fitNumber(payload.stepGoal)} steps',
                  progress: stepProgress,
                ),
                const SizedBox(height: 8),
                _FitnessProgressLine(
                  icon: Icons.water_drop_outlined,
                  label:
                      '${_fitNumber(payload.water)} / ${_fitNumber(payload.waterGoal)} ${payload.waterUnit}',
                  progress: waterProgress,
                ),
                if (constraints.maxHeight >= 195) ...[
                  const SizedBox(height: 8),
                  _FitnessProgressLine(
                    icon: Icons.timer_outlined,
                    label:
                        '${_fitNumber(payload.durationMinutes)} / ${_fitNumber(payload.durationGoalMinutes)} active min',
                    progress: activityProgress,
                  ),
                ],
                if (constraints.maxHeight >= 240) ...[
                  const SizedBox(height: 10),
                  Text(
                    [
                      if (payload.durationMinutes != null)
                        '${_fitNumber(payload.durationMinutes)} min',
                      if (payload.distance != null)
                        '${_fitNumber(payload.distance)} ${payload.distanceUnit}',
                      if (payload.calories != null)
                        '${_fitNumber(payload.calories)} kcal',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

final class _FitnessProgressLine extends StatelessWidget {
  const _FitnessProgressLine({
    required this.icon,
    required this.label,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(8),
            ),
          ],
        ),
      ),
    ],
  );
}

final class _LifeDataEditor extends ConsumerStatefulWidget {
  const _LifeDataEditor(this.context);
  final NodeEditContext context;
  @override
  ConsumerState<_LifeDataEditor> createState() => _LifeDataEditorState();
}

final class _LifeDataEditorState extends ConsumerState<_LifeDataEditor> {
  late Object _draft = widget.context.typedDraft;
  final Map<String, String> _errors = {};
  final Map<String, TextEditingController> _eventControllers = {};
  bool _fitnessSyncing = false;
  String _contactQuery = '';
  final TextEditingController _weatherSearchController =
      TextEditingController();
  List<WeatherLocation> _weatherLocations = const [];

  @override
  void initState() {
    super.initState();
    final normalizedBody = normalizeLegacyWeatherBody(widget.context.node.body);
    if (widget.context.node.type == NodeType.weather &&
        normalizedBody != widget.context.node.body) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.context.onBodyChanged(normalizedBody);
      });
    }
    _scheduleFitnessAutoSync();
  }

  @override
  void dispose() {
    for (final controller in _eventControllers.values) {
      controller.dispose();
    }
    _weatherSearchController.dispose();
    super.dispose();
  }

  TextEditingController _eventController(String key, String value) {
    final controller = _eventControllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    return controller;
  }

  @override
  void didUpdateWidget(covariant _LifeDataEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.node.id != widget.context.node.id ||
        oldWidget.context.typedDraft != widget.context.typedDraft) {
      setState(() {
        _draft = widget.context.typedDraft;
      });
      _scheduleFitnessAutoSync();
    }
  }

  void _scheduleFitnessAutoSync() {
    if (widget.context.node.type != NodeType.fit) return;
    final payload = widget.context.typedDraft is FitPayload
        ? widget.context.typedDraft as FitPayload
        : FitPayload.fromNode(widget.context.node);
    if (!payload.syncEnabled || _fitnessSyncing) return;
    final lastSynced = DateTime.tryParse(payload.syncedAt);
    if (lastSynced != null &&
        DateTime.now().difference(lastSynced).inMinutes < 15) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.context.node.type != NodeType.fit) return;
      _syncFitnessData(authorizedOnly: true);
    });
  }

  Future<void> _syncFitnessData({required bool authorizedOnly}) async {
    if (_fitnessSyncing) return;
    setState(() {
      _fitnessSyncing = true;
    });
    try {
      final service = ref.read(fitnessHealthServiceProvider);
      if (!service.isSupported) {
        if (!mounted) return;
        setState(() {
          _fitnessSyncing = false;
        });
        return;
      }
      final snapshot = await service.syncDay(
        widget.context.node.day,
        requestAuthorization: !authorizedOnly,
      );
      if (!mounted || _draft is! FitPayload) return;
      final current = _draft as FitPayload;
      final payload = current.copyWith(
        steps: snapshot.steps ?? current.steps,
        distance: snapshot.distanceKilometers ?? current.distance,
        durationMinutes: snapshot.durationMinutes ?? current.durationMinutes,
        calories: snapshot.calories ?? current.calories,
        water: snapshot.waterLiters ?? current.water,
        sleepHours: snapshot.sleepHours ?? current.sleepHours,
        restingHeartRate: snapshot.restingHeartRate ?? current.restingHeartRate,
        workout: snapshot.workout.trim().isEmpty
            ? current.workout
            : snapshot.workout,
        syncEnabled: true,
        syncSource: snapshot.source,
        syncedAt: snapshot.syncedAt.toIso8601String(),
      );
      _emit(payload);
      if (mounted) setState(() => _fitnessSyncing = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _fitnessSyncing = false;
        });
      }
    }
  }

  void _emit(Object draft) {
    setState(() => _draft = draft);
    widget.context.onDraftChanged(draft);
  }

  void _updateEvent(EventCalendarPayload candidate) {
    final validation = candidate.rangeValidation;
    setState(() {
      _draft = candidate;
      _errors
        ..removeWhere((key, _) => key.startsWith('event-'))
        ..addAll({
          'event-start-date': ?validation.startDateError,
          'event-end-date': ?validation.endDateError,
          'event-start-time': ?validation.startTimeError,
          'event-end-time': ?validation.endTimeError,
        });
    });
    if (_errors.keys.every((key) => !key.startsWith('event-'))) {
      _emit(candidate);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.context.node.type == NodeType.empty) {
      return _buildEmptyEditor(context);
    }
    if (widget.context.node.type == NodeType.mood) {
      return _buildMoodEditor(context);
    }
    if (widget.context.node.type == NodeType.contact) {
      return _buildContactEditor(context);
    }
    if (widget.context.node.type == NodeType.metric) {
      return _buildMetricEditor(context);
    }
    if (widget.context.node.type == NodeType.expense) {
      return _buildExpenseEditor(context);
    }
    if (widget.context.node.type == NodeType.fit) {
      return _buildFitEditor(context);
    }
    if (widget.context.node.type == NodeType.weather) {
      return _buildWeatherEditor(context);
    }
    return _buildEventEditor(context);
  }

  Widget _buildEmptyEditor(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Convert empty node', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            key: const ValueKey('life-data-empty-convert-task'),
            onPressed: () => _emit(const ConvertEmptyNodeAction(NodeType.task)),
            icon: const Icon(Icons.check_box_outlined),
            label: const Text('Convert to Task'),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodEditor(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _draft as MoodPayload;
    final moodText = payload.mood ?? '';
    final energy = payload.energy ?? 3.0;

    const moods = [
      ('🤩', 'Great', 'great'),
      ('😊', 'Good', 'good'),
      ('😐', 'Neutral', 'neutral'),
      ('🙁', 'Bad', 'bad'),
    ];

    return Container(
      key: ValueKey('life-data-mood-editor-${widget.context.node.id}'),
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const ValueKey('life-data-mood-title-field'),
              initialValue: widget.context.node.title,
              decoration: const InputDecoration(
                labelText: 'Mood entry title',
                hintText: 'Example: Morning reflection',
                prefixIcon: Icon(Icons.sentiment_satisfied_alt_rounded),
                isDense: true,
              ),
              onChanged: widget.context.onTitleChanged,
            ),
            const SizedBox(height: 12),
            Text('Mood status', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (emoji, label, key) in moods)
                  ChoiceChip(
                    key: ValueKey('mood-choice-$key'),
                    label: Text('$emoji $label'),
                    selected: moodText == emoji,
                    onSelected: (selected) {
                      final updated = payload.copyWith(
                        mood: selected ? emoji : null,
                        clearMood: !selected,
                      );
                      _emit(updated);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Energy level: ${energy.toInt()}/5',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            Slider(
              key: const ValueKey('mood-energy-slider'),
              value: energy.clamp(1.0, 5.0),
              min: 1.0,
              max: 5.0,
              divisions: 4,
              label: '${energy.toInt()}',
              onChanged: (val) {
                _emit(payload.copyWith(energy: val));
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('life-data-mood-notes-field'),
              initialValue: widget.context.node.body,
              decoration: const InputDecoration(
                labelText: 'Notes & triggers',
                hintText: 'What influenced your mood or energy today?',
                prefixIcon: Icon(Icons.notes_outlined),
                isDense: true,
              ),
              minLines: 2,
              maxLines: 3,
              onChanged: widget.context.onBodyChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseEditor(BuildContext context) {
    final theme = Theme.of(context);
    final payload = _draft as ExpensePayload;

    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ExpenseTransactionType>(
              key: const ValueKey('life-data-expense-transaction-type'),
              segments: const [
                ButtonSegment(
                  value: ExpenseTransactionType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.arrow_upward),
                ),
                ButtonSegment(
                  value: ExpenseTransactionType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.arrow_downward),
                ),
              ],
              selected: <ExpenseTransactionType>{payload.transactionType},
              onSelectionChanged: (values) =>
                  _emit(payload.copyWith(transactionType: values.single)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('life-data-expense-title-field'),
              initialValue: widget.context.node.title,
              decoration: const InputDecoration(
                labelText: 'Expense title',
                prefixIcon: Icon(Icons.receipt_long_outlined),
                isDense: true,
              ),
              onChanged: widget.context.onTitleChanged,
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('life-data-expense-amount-field'),
              controller: _eventController(
                'expense-amount',
                payload.amount == null ? '' : payload.amount.toString(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: const Icon(Icons.attach_money_rounded),
                errorText: _errors['expense-amount'],
                isDense: true,
              ),
              onChanged: (text) {
                final trimmed = text.trim();
                if (trimmed.isEmpty) {
                  setState(() => _errors.remove('expense-amount'));
                  _emit(payload.copyWith(clearAmount: true));
                  return;
                }
                final val = double.tryParse(trimmed);
                if (val == null || !val.isFinite || val < 0) {
                  setState(
                    () => _errors['expense-amount'] = 'Enter a finite number.',
                  );
                  return;
                }
                setState(() => _errors.remove('expense-amount'));
                _emit(payload.copyWith(amount: val));
              },
            ),
            TextFormField(
              key: const ValueKey('life-data-expense-currency-field'),
              initialValue: payload.currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              onChanged: (text) => _emit(payload.copyWith(currency: text)),
            ),
            TextFormField(
              key: const ValueKey('life-data-expense-category-field'),
              initialValue: payload.category,
              decoration: const InputDecoration(labelText: 'Category'),
              onChanged: (text) => _emit(payload.copyWith(category: text)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactEditor(BuildContext context) {
    final payload = _draft as ContactPayload;
    final contacts = payload.additionalContacts
        .where(
          (contact) => '${contact.name} ${contact.company} ${contact.email}'
              .toLowerCase()
              .contains(_contactQuery.toLowerCase()),
        )
        .toList();
    final count = payload.additionalContacts.length + 1;

    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      padding: const EdgeInsets.all(14),
      child: ListView(
        children: [
          Text('Contact $count of $count'),
          TextFormField(
            key: const ValueKey('life-data-contact-role-field'),
            initialValue: payload.role,
            decoration: const InputDecoration(labelText: 'Role'),
            onChanged: (text) => _emit(payload.copyWith(role: text)),
          ),
          TextFormField(
            key: const ValueKey('life-data-contact-company-field'),
            initialValue: payload.company,
            decoration: const InputDecoration(labelText: 'Company'),
            onChanged: (text) => _emit(payload.copyWith(company: text)),
          ),
          TextFormField(
            key: const ValueKey('life-data-contact-email-field'),
            initialValue: payload.email,
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _errors['email'],
            ),
            onChanged: (text) {
              if (text.isNotEmpty &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                setState(
                  () => _errors['email'] = 'Enter a valid email address.',
                );
              } else {
                setState(() => _errors.remove('email'));
                _emit(payload.copyWith(email: text));
              }
            },
          ),
          TextFormField(
            key: const ValueKey('life-data-contact-phone-field'),
            initialValue: payload.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            onChanged: (text) => _emit(payload.copyWith(phone: text)),
          ),
          TextFormField(
            key: const ValueKey('contact-search-field'),
            decoration: const InputDecoration(labelText: 'Search contacts'),
            onChanged: (text) => setState(() => _contactQuery = text),
          ),
          ListView(
            key: const ValueKey('contact-sidebar-list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final contact in contacts)
                ListTile(
                  title: Text(contact.name),
                  subtitle: Text(contact.company),
                  onTap: () {},
                  trailing: IconButton(
                    key: ValueKey('contact-collapsed-toggle-${contact.id}'),
                    onPressed: () {
                      final ids = [...payload.collapsedContactIds];
                      ids.contains(contact.id)
                          ? ids.remove(contact.id)
                          : ids.add(contact.id);
                      _emit(payload.copyWith(collapsedContactIds: ids));
                    },
                    icon: const Icon(Icons.expand_less),
                  ),
                ),
            ],
          ),
          ElevatedButton(
            key: const ValueKey('contact-add-record'),
            onPressed: () => _emit(
              payload.copyWith(
                additionalContacts: [
                  ...payload.additionalContacts,
                  ContactRecord(id: 'contact-$count', name: 'New Contact'),
                ],
              ),
            ),
            child: const Text('Add Record'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricEditor(BuildContext context) {
    final payload = _draft as MetricPayload;

    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextFormField(
            key: const ValueKey('life-data-metric-value-field'),
            initialValue: payload.value?.toString() ?? '',
            onChanged: (text) {
              final val = double.tryParse(text);
              _emit(payload.copyWith(value: val));
            },
          ),
          TextFormField(
            key: const ValueKey('life-data-metric-unit-field'),
            initialValue: payload.unit,
            onChanged: (text) => _emit(payload.copyWith(unit: text)),
          ),
          TextButton(
            key: const ValueKey('metric-direction'),
            onPressed: () => _emit(payload.copyWith(direction: 'atMost')),
            child: const Text('Maximum'),
          ),
        ],
      ),
    );
  }

  Widget _buildFitEditor(BuildContext context) {
    final payload = _draft as FitPayload;

    return Container(
      key: const ValueKey('life-data-fit-editor'),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          children: [
            ElevatedButton(
              key: const ValueKey('life-data-fit-sync-button'),
              onPressed: () => _syncFitnessData(authorizedOnly: false),
              child: const Text('Sync Fitness'),
            ),
            for (final activity in const [('run', 'Run'), ('walk', 'Walk')])
              TextButton(
                key: ValueKey('life-data-fit-activity-${activity.$1}'),
                onPressed: () => _emit(payload.copyWith(workout: activity.$2)),
                child: Text(activity.$2),
              ),
            IconButton(
              key: const ValueKey('life-data-fit-add-steps'),
              onPressed: () =>
                  _emit(payload.copyWith(steps: (payload.steps ?? 0) + 1000)),
              icon: const Icon(Icons.add),
            ),
            IconButton(
              key: const ValueKey('life-data-fit-add-water'),
              onPressed: () =>
                  _emit(payload.copyWith(water: (payload.water ?? 0) + 0.25)),
              icon: const Icon(Icons.water_drop),
            ),
            IconButton(
              key: const ValueKey('life-data-fit-add-duration'),
              onPressed: () => _emit(
                payload.copyWith(
                  durationMinutes: (payload.durationMinutes ?? 0) + 10,
                ),
              ),
              icon: const Icon(Icons.timer),
            ),
            IconButton(
              key: const ValueKey('life-data-fit-add-calories'),
              onPressed: () => _emit(
                payload.copyWith(calories: (payload.calories ?? 0) + 50),
              ),
              icon: const Icon(Icons.local_fire_department),
            ),
            Wrap(
              key: const ValueKey('life-data-fit-intensity'),
              children: [
                for (final intensity in const ['Low', 'Moderate', 'High'])
                  ChoiceChip(
                    label: Text(intensity),
                    selected: payload.intensity == intensity.toLowerCase(),
                    onSelected: (_) => _emit(
                      payload.copyWith(intensity: intensity.toLowerCase()),
                    ),
                  ),
              ],
            ),
            CheckboxListTile(
              key: const ValueKey('life-data-fit-completed'),
              value: payload.completed,
              onChanged: (value) =>
                  _emit(payload.copyWith(completed: value ?? false)),
              title: const Text('Completed'),
            ),
            TextFormField(
              key: const ValueKey('life-data-fit-distance-unit-field'),
              initialValue: payload.distanceUnit,
              onChanged: (text) => _emit(payload.copyWith(distanceUnit: text)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherEditor(BuildContext context) {
    final payload = _draft as WeatherPayload;

    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Card(
              key: const ValueKey('life-data-weather-summary-card'),
              child: Column(
                children: [
                  Text(payload.location),
                  Text('${payload.temp}${payload.unit}'),
                ],
              ),
            ),
            TextFormField(
              key: const ValueKey('life-data-weather-location-search-field'),
              controller: _weatherSearchController,
              decoration: const InputDecoration(labelText: 'Search city'),
            ),
            IconButton(
              key: const ValueKey('life-data-weather-location-search'),
              onPressed: () async {
                final locations = await ref
                    .read(weatherServiceProvider)
                    .searchLocations(_weatherSearchController.text);
                if (mounted) setState(() => _weatherLocations = locations);
              },
              icon: const Icon(Icons.search),
            ),
            for (var index = 0; index < _weatherLocations.length; index++)
              TextButton(
                key: ValueKey('life-data-weather-location-result-$index'),
                onPressed: () async {
                  final location = _weatherLocations[index];
                  final snapshot = await ref
                      .read(weatherServiceProvider)
                      .currentWeather(
                        location: location,
                        temperatureUnit: payload.unit,
                      );
                  if (!mounted) return;
                  _emit(
                    payload.copyWith(
                      location: location.displayName,
                      temp: snapshot.temperature.toString(),
                      apparentTemp: snapshot.apparentTemperature.toString(),
                      humidity: snapshot.relativeHumidity,
                      windSpeed: snapshot.windSpeed,
                      weather: snapshot.conditionLabel,
                      weatherCode: snapshot.conditionCode,
                      weatherDate: snapshot.observedAt.substring(0, 10),
                      latitude: location.latitude,
                      longitude: location.longitude,
                      timezone: snapshot.timezone,
                      isDay: snapshot.isDay,
                    ),
                  );
                },
                child: Text(_weatherLocations[index].displayName),
              ),
            TextFormField(
              key: const ValueKey('life-data-weather-location-field'),
              initialValue: payload.location,
              onChanged: (text) => _emit(payload.copyWith(location: text)),
            ),
            TextFormField(
              key: const ValueKey('life-data-weather-date-field'),
              initialValue: payload.weatherDate,
              onChanged: (text) => _emit(payload.copyWith(weatherDate: text)),
            ),
            TextFormField(
              key: const ValueKey('life-data-weather-notes-field'),
              initialValue: normalizeLegacyWeatherBody(
                widget.context.node.body,
              ),
              onChanged: widget.context.onBodyChanged,
            ),
            TextFormField(
              key: const ValueKey('life-data-weather-temp-field'),
              initialValue: payload.temp,
              onChanged: (text) => _emit(payload.copyWith(temp: text)),
            ),
            TextButton(
              key: const ValueKey('life-data-weather-condition-rain'),
              onPressed: () =>
                  _emit(payload.copyWith(weather: 'Rain', weatherCode: 'rain')),
              child: const Text('Rain'),
            ),
            SegmentedButton<String>(
              key: const ValueKey('life-data-weather-unit-toggle'),
              segments: const [
                ButtonSegment(value: '°C', label: Text('°C')),
                ButtonSegment(value: '°F', label: Text('°F')),
              ],
              selected: {payload.unit},
              onSelectionChanged: (units) {
                final unit = units.single;
                final value = double.tryParse(payload.temp);
                final converted = value == null
                    ? payload.temp
                    : unit == '°F'
                    ? (value * 9 / 5 + 32).toStringAsFixed(0)
                    : ((value - 32) * 5 / 9).toStringAsFixed(0);
                _emit(payload.copyWith(temp: converted, unit: unit));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventEditor(BuildContext context) {
    final payload = _draft as EventCalendarPayload;

    return Container(
      key: ValueKey('life-data-editor-${widget.context.node.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          SizedBox(
            key: ValueKey(
              'life-data-editor-preset-${widget.context.effectivePreset.name}',
            ),
          ),
          Row(
            key: const ValueKey('life-data-event-editor-columns'),
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('life-data-event-start-date-field'),
                  controller: _eventController('start-date', payload.startDate),
                  decoration: InputDecoration(
                    labelText: 'Start date',
                    errorText: _errors['event-start-date'],
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Choose Start date',
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  DateTime.tryParse(payload.startDate) ??
                                  widget.context.node.day,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              final formatted = dayKey(picked);
                              _emit(
                                payload.copyWith(
                                  startDate: formatted,
                                  endDate: formatted,
                                ),
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Clear Start date',
                          icon: const Icon(Icons.clear),
                          onPressed: () => _emit(
                            payload.copyWith(startDate: '', endDate: ''),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onChanged: (text) =>
                      _updateEvent(payload.copyWith(startDate: text)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('life-data-event-end-date-field'),
                  controller: _eventController('end-date', payload.endDate),
                  decoration: InputDecoration(
                    labelText: 'End date',
                    errorText: _errors['event-end-date'],
                  ),
                  onChanged: (text) =>
                      _updateEvent(payload.copyWith(endDate: text)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('life-data-event-start-time-field'),
                  controller: _eventController('start-time', payload.startTime),
                  decoration: InputDecoration(
                    labelText: 'Start time',
                    errorText: _errors['event-start-time'],
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Choose Start time',
                          icon: const Icon(Icons.access_time),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null) {
                              final formatted =
                                  '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                              _emit(payload.copyWith(startTime: formatted));
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Clear Start time',
                          icon: const Icon(Icons.clear),
                          onPressed: () => _emit(
                            payload.copyWith(startTime: '', endTime: ''),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onChanged: (text) =>
                      _updateEvent(payload.copyWith(startTime: text)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('life-data-event-end-time-field'),
                  controller: _eventController('end-time', payload.endTime),
                  decoration: InputDecoration(
                    labelText: 'End time',
                    errorText: _errors['event-end-time'],
                  ),
                  onChanged: (text) =>
                      _updateEvent(payload.copyWith(endTime: text)),
                ),
              ),
            ],
          ),
          TextFormField(
            key: const ValueKey('life-data-event-title-field'),
            initialValue: widget.context.node.title,
            onChanged: widget.context.onTitleChanged,
          ),
          TextFormField(
            key: const ValueKey('life-data-event-description-field'),
            initialValue: widget.context.node.body,
            onChanged: widget.context.onBodyChanged,
          ),
          TextFormField(
            key: const ValueKey('life-data-event-location-field'),
            initialValue: payload.location,
            onChanged: (text) => _updateEvent(payload.copyWith(location: text)),
          ),
        ],
      ),
    );
  }
}

String _summary(MindmapNode node) {
  if (node.type == NodeType.weather) {
    final payload = WeatherPayload.fromNode(node);
    return [
      payload.location,
      payload.weatherDate,
    ].where((value) => value.isNotEmpty).join(' · ');
  }
  return node.body.isNotEmpty ? node.body : 'Life data node';
}

double _fitProgress(double? value, double? goal) {
  if (value == null || goal == null || goal <= 0) return 0.0;
  return (value / goal).clamp(0.0, 1.0);
}

String _fitNumber(num? value) {
  if (value == null) return '0';
  return value is int ? value.toString() : value.toStringAsFixed(1);
}
