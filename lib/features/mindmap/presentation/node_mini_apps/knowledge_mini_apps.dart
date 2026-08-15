import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_utils.dart';
import '../../application/mindmap_providers.dart';
import '../../data/canvas_export_stub.dart'
    if (dart.library.io) '../../data/canvas_export_io.dart'
    if (dart.library.html) '../../data/canvas_export_web.dart';
import '../../domain/journal_prompts.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_type_payloads.dart';
import '../node_editors/canvas_document_renderer.dart';
import 'node_mini_app_common.dart';

Widget? buildKnowledgeMiniApp({
  required MindmapNode node,
  required ValueChanged<MindmapNode> onChanged,
  required Widget editor,
}) => switch (node.type) {
  NodeType.note => NoteMiniApp(node: node, editor: editor),
  NodeType.journal => JournalMiniApp(node: node, editor: editor),
  NodeType.decision => DecisionMiniApp(node: node, editor: editor),
  NodeType.idea => IdeaMiniApp(node: node, editor: editor),
  NodeType.canvas => CanvasMiniApp(
    node: node,
    onChanged: onChanged,
    editor: editor,
  ),
  _ => null,
};

class NoteMiniApp extends StatelessWidget {
  const NoteMiniApp({required this.node, required this.editor, super.key});

  final MindmapNode node;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final body = node.body;
    final words = RegExp(r'\S+').allMatches(body).length;
    final headings = <String>[
      for (final line in body.split('\n'))
        if (RegExp(r'^#{1,6}\s+').hasMatch(line.trim()))
          line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''),
    ];
    final readingMinutes = words == 0 ? 0 : (words / 200).ceil();

    return _KnowledgeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Markdown workspace',
          subtitle: 'Author in editor below; preview and outline stay visible.',
          icon: Icons.edit_note,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Words',
                    value: '$words',
                    icon: Icons.notes,
                  ),
                  MiniAppStat(
                    label: 'Characters',
                    value: '${body.characters.length}',
                    icon: Icons.text_fields,
                  ),
                  MiniAppStat(
                    label: 'Reading time',
                    value: '$readingMinutes min',
                    icon: Icons.schedule,
                  ),
                  MiniAppStat(
                    label: 'Headings',
                    value: '${headings.length}',
                    icon: Icons.format_size,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final preview = Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: body.trim().isEmpty
                        ? const MiniAppEmptyState(
                            icon: Icons.preview_outlined,
                            message: 'Write Markdown to see preview.',
                          )
                        : MarkdownBody(data: body, selectable: true),
                  );
                  final outline = Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: headings.isEmpty
                        ? const Text('No Markdown headings')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Outline',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              for (final heading in headings)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.tag, size: 16),
                                  title: Text(heading),
                                ),
                            ],
                          ),
                  );
                  final previewPane = Column(
                    children: [preview, const SizedBox(height: 12), outline],
                  );
                  if (constraints.maxWidth < 820) {
                    return Column(
                      key: const ValueKey('note-editor-preview-stack'),
                      children: [
                        editor,
                        const SizedBox(height: 12),
                        previewPane,
                      ],
                    );
                  }
                  return Row(
                    key: const ValueKey('note-editor-preview-split'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: editor),
                      const SizedBox(width: 12),
                      Expanded(child: previewPane),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class JournalMiniApp extends ConsumerWidget {
  const JournalMiniApp({required this.node, required this.editor, super.key});

  final MindmapNode node;
  final Widget editor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = JournalPayload.fromNode(node);
    final allNodes = ref.watch(allMindmapNodesProvider).valueOrNull ?? const [];
    final journals =
        allNodes
            .where((item) => item.type == NodeType.journal && !item.isArchived)
            .toList()
          ..sort((left, right) => left.day.compareTo(right.day));
    final dayNodes = allNodes
        .where((item) => item.day.isSameDay(node.day) && !item.isArchived)
        .toList();
    final prompts = JournalPromptGenerator.generateContextualPrompts(
      dayNodes: dayNodes,
    );
    final body = node.body;
    final words = RegExp(r'\S+').allMatches(body).length;
    final headings = <String>[
      for (final line in body.split('\n'))
        if (RegExp(r'^#{1,6}\s+').hasMatch(line.trim()))
          line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), ''),
    ];
    return _KnowledgeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Reflection dashboard',
          subtitle: 'Daily mood, energy, gratitude, and review signals.',
          icon: Icons.auto_stories_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Mood',
                    value: payload.mood == null
                        ? 'Unset'
                        : '${payload.mood}/10',
                    icon: Icons.mood,
                  ),
                  MiniAppStat(
                    label: 'Energy',
                    value: payload.energy == null
                        ? 'Unset'
                        : '${payload.energy}/10',
                    icon: Icons.bolt,
                  ),
                  MiniAppStat(
                    label: 'Gratitude',
                    value: '${payload.gratitude.length}',
                    icon: Icons.favorite_outline,
                  ),
                  MiniAppStat(
                    label: 'Review',
                    value: payload.isMonthlyReview
                        ? 'Monthly'
                        : payload.isWeeklyReview
                        ? 'Weekly'
                        : 'Daily',
                    icon: Icons.rate_review_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (payload.mood != null)
                MiniAppProgressMeter(
                  label: 'Mood level',
                  value: payload.mood! / 10,
                  detail: '${payload.mood}/10',
                ),
              if (payload.mood != null && payload.energy != null)
                const SizedBox(height: 12),
              if (payload.energy != null)
                MiniAppProgressMeter(
                  label: 'Energy level',
                  value: payload.energy! / 10,
                  detail: '${payload.energy}/10',
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              if (journals.isNotEmpty) ...[
                const SizedBox(height: 16),
                _JournalTrend(nodes: journals),
              ],
              if (payload.dailyHighlight.isNotEmpty) ...[
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Daily highlight'),
                  subtitle: Text(payload.dailyHighlight),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        MiniAppSection(
          title: 'Journal Markdown workspace',
          subtitle: 'Editor, live preview, outline, and contextual prompts.',
          icon: Icons.edit_note,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Words',
                    value: '$words',
                    icon: Icons.notes,
                  ),
                  MiniAppStat(
                    label: 'Characters',
                    value: '${body.characters.length}',
                    icon: Icons.text_fields,
                  ),
                  MiniAppStat(
                    label: 'Reading time',
                    value: '${words == 0 ? 0 : (words / 200).ceil()} min',
                    icon: Icons.schedule,
                  ),
                  MiniAppStat(
                    label: 'Headings',
                    value: '${headings.length}',
                    icon: Icons.format_size,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Contextual prompts',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                key: const ValueKey('journal-contextual-prompts'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final prompt in prompts) Chip(label: Text(prompt)),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final preview = Container(
                    key: const ValueKey('journal-markdown-preview'),
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: body.trim().isEmpty
                        ? const MiniAppEmptyState(
                            icon: Icons.preview_outlined,
                            message: 'Write Markdown to see preview.',
                          )
                        : MarkdownBody(data: body, selectable: true),
                  );
                  final outline = Column(
                    key: const ValueKey('journal-markdown-outline'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Outline',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      if (headings.isEmpty)
                        const Text('No Markdown headings')
                      else
                        for (final heading in headings)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.tag, size: 16),
                            title: Text(heading),
                          ),
                    ],
                  );
                  final previewPane = Column(
                    children: [preview, const SizedBox(height: 12), outline],
                  );
                  if (constraints.maxWidth < 820) {
                    return Column(
                      key: const ValueKey('journal-editor-preview-stack'),
                      children: [
                        editor,
                        const SizedBox(height: 12),
                        previewPane,
                      ],
                    );
                  }
                  return Row(
                    key: const ValueKey('journal-editor-preview-split'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: editor),
                      const SizedBox(width: 12),
                      Expanded(child: previewPane),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JournalTrend extends StatelessWidget {
  const _JournalTrend({required this.nodes});

  final List<MindmapNode> nodes;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().dateOnly;
    final sevenDayCutoff = today.subtract(const Duration(days: 6));
    final thirtyDayCutoff = today.subtract(const Duration(days: 29));
    final visible = nodes
        .where(
          (node) =>
              !node.day.isBefore(thirtyDayCutoff) && !node.day.isAfter(today),
        )
        .toList();
    final points = <(DateTime, int?, int?)>[
      for (final node in visible)
        (
          node.day,
          JournalPayload.fromNode(node).mood,
          JournalPayload.fromNode(node).energy,
        ),
    ];
    double average(Iterable<int?> values) {
      final available = values.whereType<int>().toList();
      return available.isEmpty
          ? 0
          : available.fold<int>(0, (sum, value) => sum + value) /
                available.length;
    }

    final sevenDayPoints = points.where(
      (item) => !item.$1.isBefore(sevenDayCutoff),
    );
    final mood7 = average(sevenDayPoints.map((item) => item.$2));
    final energy7 = average(sevenDayPoints.map((item) => item.$3));
    final mood30 = average(points.map((item) => item.$2));
    final energy30 = average(points.map((item) => item.$3));
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('journal-mood-energy-trend'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mood and energy trend',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            MiniAppStat(
              label: '7-day mood',
              value: mood7 == 0 ? 'No data' : mood7.toStringAsFixed(1),
              icon: Icons.mood,
            ),
            MiniAppStat(
              label: '7-day energy',
              value: energy7 == 0 ? 'No data' : energy7.toStringAsFixed(1),
              icon: Icons.bolt,
              color: colors.tertiary,
            ),
            MiniAppStat(
              label: '30-day mood',
              value: mood30 == 0 ? 'No data' : mood30.toStringAsFixed(1),
              icon: Icons.calendar_view_month,
            ),
            MiniAppStat(
              label: '30-day energy',
              value: energy30 == 0 ? 'No data' : energy30.toStringAsFixed(1),
              icon: Icons.electric_bolt,
              color: colors.tertiary,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: points
              .map(
                (item) =>
                    '${item.$1.toIso8601String().split('T').first}: mood ${item.$2 ?? 'unset'}, energy ${item.$3 ?? 'unset'}',
              )
              .join(', '),
          child: SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${point.$1.toIso8601String().split('T').first}\nMood ${point.$2 ?? '-'} · Energy ${point.$3 ?? '-'}',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              height: (4 + 7 * (point.$2 ?? 0)).toDouble(),
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 1),
                          Expanded(
                            child: Container(
                              height: (4 + 7 * (point.$3 ?? 0)).toDouble(),
                              color: colors.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Wrap(
          spacing: 14,
          children: [
            _TrendLegend(label: 'Mood', color: null),
            _TrendLegend(label: 'Energy', tertiary: true),
          ],
        ),
      ],
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({required this.label, this.color, this.tertiary = false});

  final String label;
  final Color? color;
  final bool tertiary;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        color:
            color ??
            (tertiary
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.primary),
      ),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}

class DecisionMiniApp extends StatelessWidget {
  const DecisionMiniApp({required this.node, required this.editor, super.key});

  final MindmapNode node;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final payload = DecisionPayload.fromNode(node);
    final scores = payload.weightedScores;
    return _KnowledgeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Decision matrix',
          subtitle: 'Weighted option ranking and outcome review.',
          icon: Icons.balance_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MiniAppProgressMeter(
                label: 'Decision readiness',
                value: payload.decisionCompleted / 5,
                detail: '${payload.decisionCompleted}/5 checks',
              ),
              const SizedBox(height: 14),
              if (payload.rankedOptions.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.rule_folder_outlined,
                  message: 'Add criteria and options to build ranking.',
                )
              else
                for (
                  var index = 0;
                  index < payload.rankedOptions.length;
                  index++
                )
                  ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(payload.rankedOptions[index].title),
                    subtitle: Text(
                      scores[payload.rankedOptions[index].id] == null
                          ? 'Not fully scored'
                          : 'Weighted score ${scores[payload.rankedOptions[index].id]!.toStringAsFixed(1)}/10',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (payload.rankedOptions[index].riskExposure > 0)
                          Chip(
                            label: Text(
                              'Risk ${payload.rankedOptions[index].riskExposure}',
                            ),
                          ),
                        if (payload.selectedOptionId ==
                            payload.rankedOptions[index].id)
                          const Chip(label: Text('Selected')),
                      ],
                    ),
                  ),
              const Divider(),
              Text(
                'Outcome timeline',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (payload.reviewEntries.isEmpty)
                ListTile(
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: const Text('Outcome review'),
                  subtitle: Text(
                    payload.reviewNotes.trim().isEmpty
                        ? 'Add retrospective notes in editor below.'
                        : payload.reviewNotes,
                  ),
                )
              else
                for (final entry in [
                  ...payload.reviewEntries,
                ]..sort((left, right) => right.date.compareTo(left.date)))
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(entry.notes),
                    subtitle: Text(
                      '${entry.date}${entry.rating == null ? '' : ' · ${entry.rating}/5'}',
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

class IdeaMiniApp extends StatelessWidget {
  const IdeaMiniApp({required this.node, required this.editor, super.key});

  final MindmapNode node;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final payload = IdeaPayload.fromNode(node);
    final impactIndex = IdeaPayload.levels.indexOf(payload.impact);
    final effortIndex = IdeaPayload.levels.indexOf(payload.effort);
    final quadrant = switch ((impactIndex, effortIndex)) {
      (2, 0) || (2, 1) => 'Quick win',
      (2, 2) => 'Major project',
      (0, 2) || (1, 2) => 'Deprioritize',
      _ => 'Explore',
    };

    return _KnowledgeScroll(
      children: [
        MiniAppSection(
          title: 'Idea strategy canvas',
          subtitle: 'Impact-effort position and validation pipeline.',
          icon: Icons.lightbulb_outline,
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Stage',
                    value: payload.maturity,
                    icon: Icons.alt_route,
                  ),
                  MiniAppStat(
                    label: 'Quadrant',
                    value: quadrant,
                    icon: Icons.grid_view_outlined,
                  ),
                  MiniAppStat(
                    label: 'Confidence',
                    value: '${payload.confidence}%',
                    icon: Icons.verified_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              MiniAppProgressMeter(
                label: 'Validation evidence',
                value: payload.validationCompleted / 3,
                detail: '${payload.validationCompleted}/3 signals',
              ),
              const SizedBox(height: 16),
              _ImpactEffortMatrix(
                impactIndex: impactIndex,
                effortIndex: effortIndex,
              ),
              const SizedBox(height: 16),
              Column(
                key: const ValueKey('idea-validation-journal'),
                children: [
                  _IdeaValidationEntry(
                    label: 'Hypothesis',
                    value: payload.hypothesis,
                    emptyLabel: 'Define a testable hypothesis in editor below.',
                    icon: Icons.science_outlined,
                  ),
                  _IdeaValidationEntry(
                    label: 'Evidence',
                    value: payload.evidence,
                    emptyLabel: 'Record validation evidence in editor below.',
                    icon: Icons.fact_check_outlined,
                  ),
                  _IdeaValidationEntry(
                    label: 'Next action',
                    value: payload.nextAction,
                    emptyLabel:
                        'Choose next validation action in editor below.',
                    icon: Icons.next_plan_outlined,
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

class _IdeaValidationEntry extends StatelessWidget {
  const _IdeaValidationEntry({
    required this.label,
    required this.value,
    required this.emptyLabel,
    required this.icon,
  });

  final String label;
  final String value;
  final String emptyLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    subtitle: Text(value.trim().isEmpty ? emptyLabel : value),
  );
}

class CanvasMiniApp extends StatefulWidget {
  const CanvasMiniApp({
    required this.node,
    required this.onChanged,
    required this.editor,
    super.key,
  });

  final MindmapNode node;
  final ValueChanged<MindmapNode> onChanged;
  final Widget editor;

  @override
  State<CanvasMiniApp> createState() => _CanvasMiniAppState();
}

class _CanvasMiniAppState extends State<CanvasMiniApp> {
  final GlobalKey _previewKey = GlobalKey();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final payload = CanvasPayload.fromNode(widget.node);
    final byType = <String, int>{};
    for (final element in payload.elements) {
      byType[element.type] = (byType[element.type] ?? 0) + 1;
    }
    return _KnowledgeScroll(
      maxWidth: 1200,
      children: [
        MiniAppSection(
          title: 'Canvas layers',
          subtitle: 'Reorder object stack and export canvas data or images.',
          icon: Icons.layers_outlined,
          trailing: PopupMenuButton<String>(
            tooltip: 'Canvas export actions',
            onSelected: (value) async {
              switch (value) {
                case 'json':
                  await _copyJson(context, payload);
                case 'svg':
                  await _exportSvg(context, payload);
                case 'png':
                  await _exportPng(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'json', child: Text('Copy JSON')),
              const PopupMenuItem(
                key: ValueKey('canvas-export-svg'),
                value: 'svg',
                child: Text('Export SVG'),
              ),
              PopupMenuItem(
                key: const ValueKey('canvas-export-png'),
                value: 'png',
                enabled: !_exporting,
                child: const Text('Export PNG'),
              ),
            ],
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_outlined),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  MiniAppStat(
                    label: 'Elements',
                    value: '${payload.elements.length}',
                    icon: Icons.dashboard_customize_outlined,
                  ),
                  MiniAppStat(
                    label: 'Drawing',
                    value: '${payload.drawingCount}',
                    icon: Icons.gesture,
                  ),
                  MiniAppStat(
                    label: 'Text',
                    value: '${payload.textCount}',
                    icon: Icons.text_fields,
                  ),
                  MiniAppStat(
                    label: 'Shapes',
                    value: '${payload.shapeCount}',
                    icon: Icons.category_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RepaintBoundary(
                key: _previewKey,
                child: Container(
                  key: const ValueKey('canvas-export-preview'),
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CanvasDocumentView(payload: payload),
                ),
              ),
              const SizedBox(height: 14),
              if (payload.elements.isEmpty)
                const MiniAppEmptyState(
                  icon: Icons.layers_clear,
                  message: 'No canvas layers yet.',
                )
              else
                ReorderableListView.builder(
                  key: const ValueKey('canvas-layer-list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: payload.elements.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final elements = List<CanvasElement>.of(payload.elements);
                    if (newIndex > oldIndex) newIndex--;
                    elements.insert(newIndex, elements.removeAt(oldIndex));
                    _emit(payload.copyWith(elements: elements));
                  },
                  itemBuilder: (context, index) {
                    final element = payload.elements[index];
                    return ListTile(
                      key: ValueKey('canvas-layer-${element.id}'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator),
                      ),
                      title: Text('${element.type} · ${element.id}'),
                      subtitle: Text(
                        'Color ${element.color} · Layer ${index + 1}${payload.elementGroups[element.id] == null ? '' : ' · Group ${payload.elementGroups[element.id]}'}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          PopupMenuButton<String>(
                            tooltip: 'Set layer group',
                            initialValue: payload.elementGroups[element.id],
                            onSelected: (value) {
                              final groups = Map<String, String>.from(
                                payload.elementGroups,
                              );
                              value.isEmpty
                                  ? groups.remove(element.id)
                                  : groups[element.id] = value;
                              _emit(payload.copyWith(elementGroups: groups));
                            },
                            itemBuilder: (context) => <PopupMenuEntry<String>>[
                              const PopupMenuItem(
                                value: '',
                                child: Text('No group'),
                              ),
                              for (final group in <String>{
                                ...payload.elementGroups.values,
                                'Group 1',
                                'Group 2',
                              })
                                PopupMenuItem(value: group, child: Text(group)),
                            ],
                            icon: const Icon(Icons.folder_outlined),
                          ),
                          IconButton(
                            tooltip: 'Move layer down',
                            onPressed: index == 0
                                ? null
                                : () => _move(payload, index, index - 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: 'Move layer up',
                            onPressed: index == payload.elements.length - 1
                                ? null
                                : () => _move(payload, index, index + 1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (byType.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in byType.entries)
                      Chip(label: Text('${entry.key}: ${entry.value}')),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        widget.editor,
      ],
    );
  }

  void _emit(CanvasPayload payload) => widget.onChanged(
    widget.node.copyWith(
      data: payload.toData(widget.node.data),
      updatedAt: DateTime.now(),
    ),
  );

  void _move(CanvasPayload payload, int oldIndex, int newIndex) {
    final elements = List<CanvasElement>.of(payload.elements);
    elements.insert(newIndex, elements.removeAt(oldIndex));
    _emit(payload.copyWith(elements: elements));
  }

  Future<void> _copyJson(BuildContext context, CanvasPayload payload) async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'title': widget.node.title,
          'canvas': payload.toData(widget.node.data),
        }),
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Canvas JSON copied')));
    }
  }

  Future<void> _exportSvg(BuildContext context, CanvasPayload payload) async {
    setState(() => _exporting = true);
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = await saveCanvasSvg(
        canvasPayloadSvg(payload),
        'var-node-canvas-$timestamp.svg',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Canvas SVG saved to $path')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Canvas SVG export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPng(BuildContext context) async {
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _previewKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Canvas preview is unavailable.');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Canvas image could not be encoded.');
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = await saveCanvasPng(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        'var-node-canvas-$timestamp.png',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Canvas PNG saved to $path')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Canvas PNG export failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

String canvasPayloadSvg(CanvasPayload payload) {
  String escape(String value) => const HtmlEscape().convert(value);
  String point(CanvasPoint value) => '${value.x * 1000},${value.y * 700}';
  final arrowColors = <String, String>{
    for (final element in payload.elements.whereType<CanvasArrowElement>())
      element.color: switch (element.color) {
        'blue' => '#2563eb',
        'green' => '#16a34a',
        'amber' => '#d97706',
        'rose' => '#e11d48',
        'neutral' => '#374151',
        _ => '#7c3aed',
      },
  };
  final buffer = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="700" viewBox="0 0 1000 700">',
  );
  if (arrowColors.isNotEmpty) {
    buffer
      ..write('<defs>')
      ..writeAll([
        for (final entry in arrowColors.entries)
          '<marker id="arrow-${escape(entry.key)}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="${entry.value}"/></marker>',
      ])
      ..write('</defs>');
  }
  buffer.write('<rect width="1000" height="700" fill="#ffffff"/>');
  for (final element in payload.elements) {
    final color = switch (element.color) {
      'blue' => '#2563eb',
      'green' => '#16a34a',
      'amber' => '#d97706',
      'rose' => '#e11d48',
      'neutral' => '#374151',
      _ => '#7c3aed',
    };
    switch (element) {
      case CanvasStroke():
        buffer.write(
          '<polyline points="${element.points.map(point).join(' ')}" fill="none" stroke="$color" stroke-width="${element.width}" stroke-linecap="round" stroke-linejoin="round"/>',
        );
      case CanvasTextElement():
        buffer.write(
          '<text x="${element.position.x * 1000}" y="${element.position.y * 700}" fill="$color" font-size="${element.fontSize}">${escape(element.text)}</text>',
        );
      case CanvasStickyElement():
        buffer
          ..write(
            '<rect x="${element.position.x * 1000}" y="${element.position.y * 700}" width="${element.width * 1000}" height="${element.height * 700}" rx="8" fill="#fef3c7" stroke="$color"/>',
          )
          ..write(
            '<text x="${element.position.x * 1000 + 8}" y="${element.position.y * 700 + 22}" fill="$color" font-size="14">${escape(element.text)}</text>',
          );
      case CanvasShapeElement():
        final x = math.min(element.start.x, element.end.x) * 1000;
        final y = math.min(element.start.y, element.end.y) * 700;
        final width = (element.end.x - element.start.x).abs() * 1000;
        final height = (element.end.y - element.start.y).abs() * 700;
        buffer.write(
          element.shape == 'ellipse'
              ? '<ellipse cx="${x + width / 2}" cy="${y + height / 2}" rx="${width / 2}" ry="${height / 2}" fill="none" stroke="$color" stroke-width="${element.width}"/>'
              : '<rect x="$x" y="$y" width="$width" height="$height" fill="none" stroke="$color" stroke-width="${element.width}"/>',
        );
      case CanvasArrowElement():
        buffer.write(
          '<line x1="${element.start.x * 1000}" y1="${element.start.y * 700}" x2="${element.end.x * 1000}" y2="${element.end.y * 700}" stroke="$color" stroke-width="${element.width}" marker-end="url(#arrow-${escape(element.color)})"/>',
        );
      case CanvasUnknownElement():
        break;
    }
  }
  buffer.write('</svg>');
  return buffer.toString();
}

class _ImpactEffortMatrix extends StatelessWidget {
  const _ImpactEffortMatrix({
    required this.impactIndex,
    required this.effortIndex,
  });

  final int impactIndex;
  final int effortIndex;

  @override
  Widget build(BuildContext context) {
    final selected = switch ((impactIndex, effortIndex)) {
      (2, 0) || (2, 1) => 0,
      (2, 2) => 1,
      (0, 0) || (1, 0) || (1, 1) => 2,
      _ => 3,
    };
    const labels = <String>[
      'High impact\nLow effort',
      'High impact\nHigh effort',
      'Lower impact\nLow effort',
      'Lower impact\nHigh effort',
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (var index = 0; index < labels.length; index++)
          Semantics(
            label:
                '${labels[index]}, ${index == selected ? 'selected' : 'not selected'}',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: index == selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: index == selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: index == selected ? 2 : 1,
                ),
              ),
              child: Text(labels[index], textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }
}

class _KnowledgeScroll extends StatelessWidget {
  const _KnowledgeScroll({required this.children, this.maxWidth = 900});

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
