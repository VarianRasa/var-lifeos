import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/node_visuals.dart';
import '../../domain/mindmap_node.dart';
import '../../domain/node_presentation.dart';
import '../../domain/node_type_payloads.dart';
import '../../domain/quote_catalog.dart';
import '../widgets/file_card_widget.dart';
import 'audio_node_editor.dart';
import 'canvas_node_editor.dart';
import 'productivity_node_editors.dart';
import 'quote_discovery_panel.dart';
import 'resource_node_editor.dart';

sealed class KnowledgeNodeAction {
  const KnowledgeNodeAction();
}

final class OpenKnowledgeExternalAction extends KnowledgeNodeAction {
  const OpenKnowledgeExternalAction(this.target);

  final String target;
}

final class OpenSubCanvasAction extends KnowledgeNodeAction {
  const OpenSubCanvasAction(this.nodeId);

  final String nodeId;
}

Widget buildKnowledgeNodeContent(NodeRenderContext context) {
  if (context.node.type == NodeType.journal) {
    return _JournalContent(context);
  }
  return _isKnowledge(context.node.type)
      ? _KnowledgeContent(context)
      : buildProductivityNodeContent(context);
}

Widget buildKnowledgeNodeInlineEditor(NodeEditContext context) =>
    _isKnowledge(context.node.type)
    ? _KnowledgeEditor(context)
    : buildProductivityNodeInlineEditor(context);

bool _isKnowledge(NodeType type) => switch (type) {
  NodeType.journal ||
  NodeType.link ||
  NodeType.bookmark ||
  NodeType.resource ||
  NodeType.idea ||
  NodeType.question ||
  NodeType.decision ||
  NodeType.quote ||
  NodeType.audio ||
  NodeType.canvas => true,
  _ => false,
};

final class _JournalContent extends StatelessWidget {
  const _JournalContent(this.context);

  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final node = context.node;
    final compact = context.effectivePreset == NodeSizePreset.compact;
    final payload = JournalPayload.fromNode(node);
    final theme = Theme.of(buildContext);
    final semantic = AppSemanticColors.of(buildContext);

    return Container(
      key: ValueKey<String>(
        'knowledge-${node.type.name}-${context.effectivePreset.name}',
      ),
      color: theme.colorScheme.surface,
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.book_outlined,
                size: compact ? 16 : 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.title.isEmpty ? 'Daily Journal' : node.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? theme.textTheme.labelLarge
                      : theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                ),
              ),
              if (payload.weather.isNotEmpty)
                Text(
                  _weatherEmoji(payload.weather),
                  style: const TextStyle(fontSize: 14),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (payload.mood != null)
                  _badgeChip(
                    theme,
                    _moodBadgeText(payload.mood!),
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.onPrimaryContainer,
                  ),
                if (payload.energy != null)
                  _badgeChip(
                    theme,
                    '⚡ ${payload.energy}/10',
                    theme.colorScheme.tertiaryContainer,
                    theme.colorScheme.onTertiaryContainer,
                  ),
                if (payload.isWeeklyReview)
                  _badgeChip(
                    theme,
                    'Weekly Review',
                    theme.colorScheme.secondaryContainer,
                    theme.colorScheme.onSecondaryContainer,
                  ),
                if (payload.isMonthlyReview)
                  _badgeChip(
                    theme,
                    'Monthly Review',
                    theme.colorScheme.secondaryContainer,
                    theme.colorScheme.onSecondaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (payload.dailyHighlight.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: semantic.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                payload.dailyHighlight,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (payload.prompt.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '💬 ${payload.prompt}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      node.body.isEmpty ? 'No content' : node.body,
                      key: const ValueKey<String>('knowledge-body'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (payload.gratitude.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Gratitude:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final item in payload.gratitude)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🙏 ', style: TextStyle(fontSize: 12)),
                              Expanded(
                                child: Text(
                                  item,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badgeChip(ThemeData theme, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _moodBadgeText(int mood) => switch (mood) {
    1 || 2 => '😞 $mood/10',
    3 || 4 => '🙁 $mood/10',
    5 || 6 => '😐 $mood/10',
    7 || 8 => '🙂 $mood/10',
    _ => '😊 $mood/10',
  };

  String _weatherEmoji(String weather) => switch (weather) {
    'sunny' => '☀️',
    'cloudy' => '⛅',
    'rainy' => '🌧️',
    'stormy' => '🌩️',
    'snowy' => '❄️',
    _ => weather,
  };
}

final class _KnowledgeContent extends StatelessWidget {
  const _KnowledgeContent(this.context);

  final NodeRenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final node = context.node;
    final compact = context.effectivePreset == NodeSizePreset.compact;
    if (node.type == NodeType.link && node.data['isLocalFile'] == true) {
      return FileCardWidget(
        fileName: node.data['title'] as String? ?? node.title,
        fileSize: (node.data['fileSize'] as num?)?.toInt() ?? 0,
        fileExtension: node.data['fileExtension'] as String? ?? '',
      );
    }
    if (node.type == NodeType.resource) {
      final payload = context.typedPayload is ResourcePayload
          ? context.typedPayload as ResourcePayload
          : ResourcePayload.fromNode(node);
      return LayoutBuilder(
        builder: (context, constraints) {
          final micro =
              constraints.hasBoundedHeight && constraints.maxHeight < 120;
          return Container(
            key: ValueKey<String>(
              'knowledge-resource-${this.context.effectivePreset.name}',
            ),
            color: Theme.of(context).colorScheme.surface,
            padding: EdgeInsets.all(micro ? 4 : (compact ? 10 : 14)),
            child: ResourceNodePreview(
              payload: payload,
              primaryBytes: this.context.attachmentBytes,
              primaryLoading: this.context.attachmentLoading,
              primaryError: this.context.attachmentError,
              compact: micro,
              collapsed: true,
            ),
          );
        },
      );
    }
    final expanded =
        context.effectivePreset == NodeSizePreset.large ||
        context.effectivePreset == NodeSizePreset.wide;
    return Container(
      key: ValueKey<String>(
        'knowledge-${node.type.name}-${context.effectivePreset.name}',
      ),
      color: Theme.of(buildContext).colorScheme.surface,
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                NodeVisuals.icon(node.type),
                size: compact ? 16 : 20,
                color: NodeVisuals.color(buildContext, node.type),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? Theme.of(buildContext).textTheme.labelLarge
                      : Theme.of(buildContext).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.body.isEmpty ? 'No content' : node.body,
                      key: const ValueKey<String>('knowledge-body'),
                      maxLines: expanded ? 14 : 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    _KnowledgeMetadata(node: node, expanded: expanded),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _KnowledgeMetadata extends StatelessWidget {
  const _KnowledgeMetadata({required this.node, required this.expanded});

  final MindmapNode node;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final values = switch (node.type) {
      NodeType.link ||
      NodeType.bookmark ||
      NodeType.resource => [LinkResourcePayload.fromNode(node).url],
      NodeType.decision => [
        ...DecisionPayload.fromNode(node).options.map((option) => option.title),
        DecisionPayload.fromNode(node).outcome,
      ],
      NodeType.quote => [
        QuotePayload.fromNode(node).author,
        QuotePayload.fromNode(node).source,
      ],
      NodeType.journal => [
        if (JournalPayload.fromNode(node).mood != null)
          'Mood: ${JournalPayload.fromNode(node).mood}/10',
        if (JournalPayload.fromNode(node).energy != null)
          'Energy: ${JournalPayload.fromNode(node).energy}/10',
        if (JournalPayload.fromNode(node).weather.isNotEmpty)
          JournalPayload.fromNode(node).weather,
        if (JournalPayload.fromNode(node).isWeeklyReview) 'Weekly Review',
        if (JournalPayload.fromNode(node).isMonthlyReview) 'Monthly Review',
        if (JournalPayload.fromNode(node).dailyHighlight.isNotEmpty)
          'Highlight: ${JournalPayload.fromNode(node).dailyHighlight}',
        if (JournalPayload.fromNode(node).gratitude.isNotEmpty)
          '${JournalPayload.fromNode(node).gratitude.length} Gratitudes',
      ],
      NodeType.audio => [
        AudioPayload.fromNode(node).audioDuration,
        AudioPayload.fromNode(node).audioTranscript,
      ],
      NodeType.canvas => [
        '${CanvasPayload.fromNode(node).elements.length} elements',
        CanvasPayload.fromNode(node).background,
      ],
      _ => const <String>[],
    }.where((value) => value.trim().isNotEmpty).toList(growable: false);
    if (values.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final value in values.take(expanded ? 6 : 3))
          Chip(
            visualDensity: VisualDensity.compact,
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(value, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
    );
  }
}

final class _KnowledgeEditor extends StatefulWidget {
  const _KnowledgeEditor(this.context);

  final NodeEditContext context;

  @override
  State<_KnowledgeEditor> createState() => _KnowledgeEditorState();
}

final class _KnowledgeEditorState extends State<_KnowledgeEditor> {
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  late TextEditingController _ideaHypothesisController;
  late TextEditingController _ideaEvidenceController;
  late TextEditingController _ideaNextActionController;
  late TextEditingController _questionTextController;
  late TextEditingController _questionContextController;
  late TextEditingController _questionAnswerController;
  late TextEditingController _questionEvidenceController;
  late TextEditingController _questionNextActionController;
  late FocusNode _ideaHypothesisFocusNode;
  late FocusNode _ideaEvidenceFocusNode;
  late FocusNode _ideaNextActionFocusNode;
  late FocusNode _questionTextFocusNode;
  late FocusNode _questionContextFocusNode;
  late FocusNode _questionAnswerFocusNode;
  late FocusNode _questionEvidenceFocusNode;
  late FocusNode _questionNextActionFocusNode;
  late Object _latestDraft;
  var _draftRevision = 0;
  String? _journalMoodError;
  String? _journalEnergyError;

  NodeEditContext get editContext => widget.context;

  @override
  void initState() {
    super.initState();
    _latestDraft = editContext.typedDraft;
    _createControllers();
  }

  @override
  void didUpdateWidget(covariant _KnowledgeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.node.id != editContext.node.id) {
      _disposeControllers();
      _latestDraft = editContext.typedDraft;
      _draftRevision++;
      _journalMoodError = null;
      _journalEnergyError = null;
      _createControllers();
    } else if (!identical(
          oldWidget.context.typedDraft,
          editContext.typedDraft,
        ) &&
        !_sameTypedDraft(_latestDraft, editContext.typedDraft)) {
      _latestDraft = editContext.typedDraft;
      _syncIdeaControllers(editContext.typedDraft);
      _syncQuestionControllers(editContext.typedDraft);
      if (!_hasFocusedTypedField) {
        _draftRevision++;
      }
      _journalMoodError = null;
      _journalEnergyError = null;
    }
  }

  bool _sameTypedDraft(Object left, Object right) {
    if (identical(left, right)) return true;
    if (left is IdeaPayload && right is IdeaPayload) {
      return left.maturity == right.maturity &&
          left.hypothesis == right.hypothesis &&
          left.impact == right.impact &&
          left.effort == right.effort &&
          left.confidence == right.confidence &&
          left.evidence == right.evidence &&
          left.nextAction == right.nextAction;
    }
    if (left is QuestionPayload && right is QuestionPayload) {
      return left.investigationStatus == right.investigationStatus &&
          left.questionText == right.questionText &&
          left.questionContext == right.questionContext &&
          _sameStrings(left.possibleAnswers, right.possibleAnswers) &&
          left.answer == right.answer &&
          left.evidence == right.evidence &&
          _sameStrings(left.questionSources, right.questionSources) &&
          left.nextResearchAction == right.nextResearchAction &&
          left.questionConfidence == right.questionConfidence;
    }
    if (left is JournalPayload && right is JournalPayload) {
      return left.mood == right.mood &&
          left.energy == right.energy &&
          left.prompt == right.prompt &&
          left.weather == right.weather &&
          left.dailyHighlight == right.dailyHighlight &&
          left.isWeeklyReview == right.isWeeklyReview &&
          left.isMonthlyReview == right.isMonthlyReview &&
          _sameStrings(left.gratitude, right.gratitude);
    }
    if (left is DecisionPayload && right is DecisionPayload) {
      return jsonEncode(left.toData(const <String, Object?>{})) ==
          jsonEncode(right.toData(const <String, Object?>{}));
    }
    if (left is CanvasPayload && right is CanvasPayload) {
      return jsonEncode(left.toData(const <String, Object?>{})) ==
          jsonEncode(right.toData(const <String, Object?>{}));
    }
    if (left is ResourcePayload && right is ResourcePayload) {
      return jsonEncode(left.toData(const <String, Object?>{})) ==
          jsonEncode(right.toData(const <String, Object?>{}));
    }
    if (left is AudioPayload && right is AudioPayload) {
      return jsonEncode(left.toData(const <String, Object?>{})) ==
          jsonEncode(right.toData(const <String, Object?>{}));
    }
    if (left is QuotePayload && right is QuotePayload) {
      return left.author == right.author &&
          left.source == right.source &&
          left.collection == right.collection &&
          left.isFavorite == right.isFavorite &&
          left.remoteQuoteId == right.remoteQuoteId &&
          left.quoteProvider == right.quoteProvider &&
          left.sourceUrl == right.sourceUrl &&
          _sameStrings(left.tags, right.tags);
    }
    if (left is LinkResourcePayload && right is LinkResourcePayload) {
      return left.type == right.type &&
          left.url == right.url &&
          left.collection == right.collection &&
          left.description == right.description &&
          left.bookmarkStatus == right.bookmarkStatus &&
          left.isFavorite == right.isFavorite &&
          _sameStrings(left.tags, right.tags);
    }
    return false;
  }

  bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _emitDraft(Object value) {
    if (value is! KnowledgeNodeAction) {
      setState(() => _latestDraft = value);
    }
    editContext.onDraftChanged(value);
  }

  void _setJournalNumericError(String field, String? error) {
    setState(() {
      if (field == 'mood') {
        _journalMoodError = error;
      } else {
        _journalEnergyError = error;
      }
    });
  }

  void _createControllers() {
    _titleController = TextEditingController(text: editContext.node.title);
    final normalizedBody = editContext.node.type == NodeType.quote
        ? normalizeLegacyQuoteBody(editContext.node.body)
        : editContext.node.body;
    _bodyController = TextEditingController(text: normalizedBody);
    if (normalizedBody != editContext.node.body) {
      scheduleMicrotask(() => editContext.onBodyChanged(normalizedBody));
    }
    final idea = editContext.typedDraft is IdeaPayload
        ? editContext.typedDraft as IdeaPayload
        : IdeaPayload.fromNode(editContext.node);
    _ideaHypothesisController = TextEditingController(text: idea.hypothesis);
    _ideaEvidenceController = TextEditingController(text: idea.evidence);
    _ideaNextActionController = TextEditingController(text: idea.nextAction);
    _ideaHypothesisFocusNode = FocusNode();
    _ideaEvidenceFocusNode = FocusNode();
    _ideaNextActionFocusNode = FocusNode();
    _ideaHypothesisFocusNode.addListener(_syncIdeaControllersAfterBlur);
    _ideaEvidenceFocusNode.addListener(_syncIdeaControllersAfterBlur);
    _ideaNextActionFocusNode.addListener(_syncIdeaControllersAfterBlur);
    final question = editContext.typedDraft is QuestionPayload
        ? editContext.typedDraft as QuestionPayload
        : QuestionPayload.fromNode(editContext.node);
    _questionTextController = TextEditingController(
      text: question.questionText,
    );
    _questionContextController = TextEditingController(
      text: question.questionContext,
    );
    _questionAnswerController = TextEditingController(text: question.answer);
    _questionEvidenceController = TextEditingController(
      text: question.evidence,
    );
    _questionNextActionController = TextEditingController(
      text: question.nextResearchAction,
    );
    _questionTextFocusNode = FocusNode();
    _questionContextFocusNode = FocusNode();
    _questionAnswerFocusNode = FocusNode();
    _questionEvidenceFocusNode = FocusNode();
    _questionNextActionFocusNode = FocusNode();
    _questionTextFocusNode.addListener(_syncQuestionControllersAfterBlur);
    _questionContextFocusNode.addListener(_syncQuestionControllersAfterBlur);
    _questionAnswerFocusNode.addListener(_syncQuestionControllersAfterBlur);
    _questionEvidenceFocusNode.addListener(_syncQuestionControllersAfterBlur);
    _questionNextActionFocusNode.addListener(_syncQuestionControllersAfterBlur);
  }

  bool get _hasFocusedIdeaField =>
      _ideaHypothesisFocusNode.hasFocus ||
      _ideaEvidenceFocusNode.hasFocus ||
      _ideaNextActionFocusNode.hasFocus;

  bool get _hasFocusedQuestionField =>
      _questionTextFocusNode.hasFocus ||
      _questionContextFocusNode.hasFocus ||
      _questionAnswerFocusNode.hasFocus ||
      _questionEvidenceFocusNode.hasFocus ||
      _questionNextActionFocusNode.hasFocus;

  bool get _hasFocusedTypedField =>
      _hasFocusedIdeaField || _hasFocusedQuestionField;

  void _syncIdeaControllersAfterBlur() {
    if (!_hasFocusedIdeaField) _syncIdeaControllers(_latestDraft);
  }

  void _syncQuestionControllersAfterBlur() {
    if (!_hasFocusedQuestionField) _syncQuestionControllers(_latestDraft);
  }

  void _syncIdeaControllers(Object draft) {
    if (draft is! IdeaPayload) return;
    _syncIdeaController(
      _ideaHypothesisController,
      _ideaHypothesisFocusNode,
      draft.hypothesis,
    );
    _syncIdeaController(
      _ideaEvidenceController,
      _ideaEvidenceFocusNode,
      draft.evidence,
    );
    _syncIdeaController(
      _ideaNextActionController,
      _ideaNextActionFocusNode,
      draft.nextAction,
    );
  }

  void _syncQuestionControllers(Object draft) {
    if (draft is! QuestionPayload) return;
    _syncIdeaController(
      _questionTextController,
      _questionTextFocusNode,
      draft.questionText,
    );
    _syncIdeaController(
      _questionContextController,
      _questionContextFocusNode,
      draft.questionContext,
    );
    _syncIdeaController(
      _questionAnswerController,
      _questionAnswerFocusNode,
      draft.answer,
    );
    _syncIdeaController(
      _questionEvidenceController,
      _questionEvidenceFocusNode,
      draft.evidence,
    );
    _syncIdeaController(
      _questionNextActionController,
      _questionNextActionFocusNode,
      draft.nextResearchAction,
    );
  }

  void _syncIdeaController(
    TextEditingController controller,
    FocusNode focusNode,
    String value,
  ) {
    if (focusNode.hasFocus || controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _disposeControllers() {
    _titleController.dispose();
    _bodyController.dispose();
    _ideaHypothesisFocusNode.dispose();
    _ideaEvidenceFocusNode.dispose();
    _ideaNextActionFocusNode.dispose();
    _ideaHypothesisController.dispose();
    _ideaEvidenceController.dispose();
    _ideaNextActionController.dispose();
    _questionTextFocusNode.dispose();
    _questionContextFocusNode.dispose();
    _questionAnswerFocusNode.dispose();
    _questionEvidenceFocusNode.dispose();
    _questionNextActionFocusNode.dispose();
    _questionTextController.dispose();
    _questionContextController.dispose();
    _questionAnswerController.dispose();
    _questionEvidenceController.dispose();
    _questionNextActionController.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext buildContext) => Material(
    color: Theme.of(buildContext).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: ValueKey<String>(
                'knowledge-${editContext.node.id}-title-field',
              ),
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                isDense: true,
              ),
              onChanged: editContext.onTitleChanged,
            ),
            const SizedBox(height: 10),
            TextField(
              key: ValueKey<String>(
                'knowledge-${editContext.node.id}-body-field',
              ),
              controller: _bodyController,
              decoration: const InputDecoration(
                labelText: 'Content',
                alignLabelWithHint: true,
                isDense: true,
              ),
              minLines: editContext.effectivePreset == NodeSizePreset.compact
                  ? 1
                  : 2,
              maxLines: editContext.effectivePreset == NodeSizePreset.compact
                  ? 3
                  : 4,
              onChanged: editContext.onBodyChanged,
            ),
            const SizedBox(height: 12),
            _TypeFields(
              NodeEditContext(
                node: editContext.node,
                typedDraft: _latestDraft,
                cachedPayload: editContext.cachedPayload,
                effectivePreset: editContext.effectivePreset,
                validationErrors: editContext.validationErrors,
                onTitleChanged: editContext.onTitleChanged,
                onBodyChanged: editContext.onBodyChanged,
                onDraftChanged: _emitDraft,
                onNodeDraftChanged: editContext.onNodeDraftChanged,
                attachmentBytes: editContext.attachmentBytes,
                attachmentLoading: editContext.attachmentLoading,
                attachmentError: editContext.attachmentError,
                onResourceAssetAdd: editContext.onResourceAssetAdd,
                onResourceAssetOpen: editContext.onResourceAssetOpen,
                resourceFolderSuggestions:
                    editContext.resourceFolderSuggestions,
                onKnowledgeAction: editContext.onKnowledgeAction,
                onActionError: editContext.onActionError,
              ),
              onJournalNumericError: _setJournalNumericError,
              ideaHypothesisController: _ideaHypothesisController,
              ideaEvidenceController: _ideaEvidenceController,
              ideaNextActionController: _ideaNextActionController,
              ideaHypothesisFocusNode: _ideaHypothesisFocusNode,
              ideaEvidenceFocusNode: _ideaEvidenceFocusNode,
              ideaNextActionFocusNode: _ideaNextActionFocusNode,
              questionTextController: _questionTextController,
              questionContextController: _questionContextController,
              questionAnswerController: _questionAnswerController,
              questionEvidenceController: _questionEvidenceController,
              questionNextActionController: _questionNextActionController,
              questionTextFocusNode: _questionTextFocusNode,
              questionContextFocusNode: _questionContextFocusNode,
              questionAnswerFocusNode: _questionAnswerFocusNode,
              questionEvidenceFocusNode: _questionEvidenceFocusNode,
              questionNextActionFocusNode: _questionNextActionFocusNode,
              key: ValueKey<String>(
                'knowledge-type-fields-${editContext.node.id}-$_draftRevision',
              ),
            ),
            if (_journalMoodError != null) _LocalError(_journalMoodError!),
            if (_journalEnergyError != null) _LocalError(_journalEnergyError!),
            for (final error in editContext.validationErrors)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(buildContext).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

final class _TypeFields extends StatelessWidget {
  const _TypeFields(
    this.context, {
    required this.onJournalNumericError,
    required this.ideaHypothesisController,
    required this.ideaEvidenceController,
    required this.ideaNextActionController,
    required this.ideaHypothesisFocusNode,
    required this.ideaEvidenceFocusNode,
    required this.ideaNextActionFocusNode,
    required this.questionTextController,
    required this.questionContextController,
    required this.questionAnswerController,
    required this.questionEvidenceController,
    required this.questionNextActionController,
    required this.questionTextFocusNode,
    required this.questionContextFocusNode,
    required this.questionAnswerFocusNode,
    required this.questionEvidenceFocusNode,
    required this.questionNextActionFocusNode,
    super.key,
  });

  final NodeEditContext context;
  final void Function(String field, String? error) onJournalNumericError;
  final TextEditingController ideaHypothesisController;
  final TextEditingController ideaEvidenceController;
  final TextEditingController ideaNextActionController;
  final FocusNode ideaHypothesisFocusNode;
  final FocusNode ideaEvidenceFocusNode;
  final FocusNode ideaNextActionFocusNode;
  final TextEditingController questionTextController;
  final TextEditingController questionContextController;
  final TextEditingController questionAnswerController;
  final TextEditingController questionEvidenceController;
  final TextEditingController questionNextActionController;
  final FocusNode questionTextFocusNode;
  final FocusNode questionContextFocusNode;
  final FocusNode questionAnswerFocusNode;
  final FocusNode questionEvidenceFocusNode;
  final FocusNode questionNextActionFocusNode;

  @override
  Widget build(BuildContext buildContext) => switch (context.node.type) {
    NodeType.link || NodeType.bookmark => _linkFields(),
    NodeType.resource => _resourceFields(),
    NodeType.decision => _decisionFields(buildContext),
    NodeType.quote => _quoteFields(),
    NodeType.question => _questionFields(buildContext),
    NodeType.idea => _ideaFields(buildContext),
    NodeType.journal => _JournalFields(
      context: context,
      payload: context.typedDraft is JournalPayload
          ? context.typedDraft as JournalPayload
          : JournalPayload.fromNode(context.node),
    ),
    NodeType.audio => _audioFields(buildContext),
    NodeType.canvas => _canvasFields(buildContext),
    _ => const SizedBox.shrink(),
  };

  Widget _linkFields() {
    final payload = context.typedDraft is LinkResourcePayload
        ? context.typedDraft as LinkResourcePayload
        : LinkResourcePayload.fromNode(context.node);
    if (context.node.type == NodeType.bookmark) {
      return _BookmarkFields(context: context, payload: payload);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          key: 'knowledge-link-url-field',
          label: 'URL',
          value: payload.url,
          keyboardType: TextInputType.url,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(url: value)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey<String>('knowledge-link-open-action'),
          onPressed:
              payload.validate(title: context.node.title).isEmpty &&
                  payload.url.trim().isNotEmpty &&
                  context.onKnowledgeAction != null
              ? () async => context.onKnowledgeAction!(
                  OpenKnowledgeExternalAction(payload.url),
                )
              : null,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open link'),
        ),
      ],
    );
  }

  Widget _resourceFields() {
    final payload = context.typedDraft is ResourcePayload
        ? context.typedDraft as ResourcePayload
        : ResourcePayload.fromNode(context.node);
    return ResourceNodeEditor(
      payload: payload,
      onChanged: context.onDraftChanged,
      primaryBytes: context.attachmentBytes,
      primaryLoading: context.attachmentLoading,
      primaryError: context.attachmentError,
      onChooseFile: context.onResourceAssetAdd,
      onOpenAsset: context.onResourceAssetOpen,
      folderSuggestions: context.resourceFolderSuggestions,
    );
  }

  Widget _ideaFields(BuildContext buildContext) {
    final payload = context.typedDraft is IdeaPayload
        ? context.typedDraft as IdeaPayload
        : IdeaPayload.fromNode(context.node);
    final suggested = payload.suggestedMaturity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lifecycle', style: Theme.of(buildContext).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final maturity in IdeaPayload.maturities)
              ChoiceChip(
                key: ValueKey<String>('knowledge-idea-stage-$maturity'),
                label: Text(_ideaLabel(maturity)),
                selected: payload.maturity == maturity,
                onSelected: (_) => context.onDraftChanged(
                  payload.copyWith(maturity: maturity),
                ),
              ),
          ],
        ),
        if (suggested != payload.maturity &&
            payload.maturity != 'archived') ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey<String>('knowledge-idea-stage-suggestion'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(buildContext).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Suggested stage: ${_ideaLabel(suggested)}'),
                ),
                TextButton(
                  key: const ValueKey<String>(
                    'knowledge-idea-apply-stage-suggestion',
                  ),
                  onPressed: () => context.onDraftChanged(
                    payload.copyWith(maturity: suggested),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text('Validation ${payload.validationCompleted}/3'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          key: const ValueKey<String>('knowledge-idea-validation-progress'),
          value: payload.validationCompleted / 3,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-idea-hypothesis-field',
          label: 'Hypothesis',
          value: payload.hypothesis,
          controller: ideaHypothesisController,
          focusNode: ideaHypothesisFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(hypothesis: value)),
        ),
        const SizedBox(height: 10),
        _ideaLevelSelector(
          label: 'Impact',
          keyPrefix: 'knowledge-idea-impact',
          selected: payload.impact,
          onSelected: (value) =>
              context.onDraftChanged(payload.copyWith(impact: value)),
        ),
        const SizedBox(height: 10),
        _ideaLevelSelector(
          label: 'Effort',
          keyPrefix: 'knowledge-idea-effort',
          selected: payload.effort,
          onSelected: (value) =>
              context.onDraftChanged(payload.copyWith(effort: value)),
        ),
        const SizedBox(height: 10),
        Text('Confidence ${payload.confidence}%'),
        Slider(
          key: const ValueKey<String>('knowledge-idea-confidence-slider'),
          value: payload.confidence.toDouble(),
          min: 0,
          max: 100,
          label: '${payload.confidence}%',
          onChanged: (value) => context.onDraftChanged(
            payload.copyWith(confidence: value.round()),
          ),
        ),
        _field(
          key: 'knowledge-idea-evidence-field',
          label: 'Evidence',
          value: payload.evidence,
          controller: ideaEvidenceController,
          focusNode: ideaEvidenceFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(evidence: value)),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-idea-next-action-field',
          label: 'Next experiment',
          value: payload.nextAction,
          controller: ideaNextActionController,
          focusNode: ideaNextActionFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(nextAction: value)),
        ),
      ],
    );
  }

  Widget _ideaLevelSelector({
    required String label,
    required String keyPrefix,
    required String selected,
    required ValueChanged<String> onSelected,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        children: [
          for (final level in IdeaPayload.levels)
            ChoiceChip(
              key: ValueKey<String>('$keyPrefix-$level'),
              label: Text(_ideaLabel(level)),
              selected: selected == level,
              onSelected: (_) => onSelected(level),
            ),
        ],
      ),
    ],
  );
  Widget _questionFields(BuildContext buildContext) {
    final payload = context.typedDraft is QuestionPayload
        ? context.typedDraft as QuestionPayload
        : QuestionPayload.fromNode(context.node);
    final suggested = payload.suggestedInvestigationStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Investigation',
          style: Theme.of(buildContext).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final status in QuestionPayload.statuses)
              ChoiceChip(
                key: ValueKey<String>('knowledge-question-status-$status'),
                label: Text(_ideaLabel(status)),
                selected: payload.investigationStatus == status,
                onSelected: (_) => context.onDraftChanged(
                  payload.copyWith(investigationStatus: status),
                ),
              ),
          ],
        ),
        if (suggested != payload.investigationStatus &&
            payload.investigationStatus != 'blocked') ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey<String>('knowledge-question-status-suggestion'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(buildContext).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Suggested status: ${_ideaLabel(suggested)}'),
                ),
                TextButton(
                  key: const ValueKey<String>(
                    'knowledge-question-apply-status-suggestion',
                  ),
                  onPressed: () => context.onDraftChanged(
                    payload.copyWith(investigationStatus: suggested),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text('Research ${payload.researchCompleted}/4'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          key: const ValueKey<String>('knowledge-question-research-progress'),
          value: payload.researchCompleted / 4,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-question-text-field',
          label: 'Question',
          value: payload.questionText,
          controller: questionTextController,
          focusNode: questionTextFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(questionText: value)),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-question-context-field',
          label: 'Context',
          value: payload.questionContext,
          controller: questionContextController,
          focusNode: questionContextFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(questionContext: value)),
        ),
        const SizedBox(height: 12),
        _questionStringList(
          title: 'Possible answers',
          itemLabel: 'Possible answer',
          keyPrefix: 'knowledge-question-possible-answer',
          values: payload.possibleAnswers,
          onChanged: (values) =>
              context.onDraftChanged(payload.copyWith(possibleAnswers: values)),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-question-answer-field',
          label: 'Accepted answer',
          value: payload.answer,
          controller: questionAnswerController,
          focusNode: questionAnswerFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(answer: value)),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-question-evidence-field',
          label: 'Evidence',
          value: payload.evidence,
          controller: questionEvidenceController,
          focusNode: questionEvidenceFocusNode,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(evidence: value)),
        ),
        const SizedBox(height: 12),
        _questionStringList(
          title: 'Sources',
          itemLabel: 'Source',
          keyPrefix: 'knowledge-question-source',
          values: payload.questionSources,
          onChanged: (values) =>
              context.onDraftChanged(payload.copyWith(questionSources: values)),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-question-next-action-field',
          label: 'Next research action',
          value: payload.nextResearchAction,
          controller: questionNextActionController,
          focusNode: questionNextActionFocusNode,
          lines: true,
          onChanged: (value) => context.onDraftChanged(
            payload.copyWith(nextResearchAction: value),
          ),
        ),
        const SizedBox(height: 10),
        Text('Confidence ${payload.questionConfidence}%'),
        Slider(
          key: const ValueKey<String>('knowledge-question-confidence-slider'),
          value: payload.questionConfidence.toDouble(),
          min: 0,
          max: 100,
          label: '${payload.questionConfidence}%',
          onChanged: (value) => context.onDraftChanged(
            payload.copyWith(questionConfidence: value.round()),
          ),
        ),
      ],
    );
  }

  Widget _questionStringList({
    required String title,
    required String itemLabel,
    required String keyPrefix,
    required List<String> values,
    required ValueChanged<List<String>> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            key: ValueKey<String>('$keyPrefix-add'),
            tooltip: 'Add $itemLabel',
            onPressed: () => onChanged(<String>[...values, 'New $itemLabel']),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      for (var index = 0; index < values.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _field(
                  key: '$keyPrefix-field-$index',
                  label: '$itemLabel ${index + 1}',
                  value: values[index],
                  lines: true,
                  onChanged: (value) {
                    final updated = List<String>.of(values);
                    updated[index] = value;
                    onChanged(updated);
                  },
                ),
              ),
              IconButton(
                key: ValueKey<String>('$keyPrefix-delete-$index'),
                tooltip: 'Delete $itemLabel',
                onPressed: () {
                  final updated = List<String>.of(values)..removeAt(index);
                  onChanged(updated);
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _decisionFields(BuildContext buildContext) {
    final payload = context.typedDraft is DecisionPayload
        ? context.typedDraft as DecisionPayload
        : DecisionPayload.fromNode(context.node);
    final suggested = payload.suggestedStatus;
    final scores = payload.weightedScores;
    final recommended = payload.options
        .where((option) => option.id == payload.recommendedOptionId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lifecycle', style: Theme.of(buildContext).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final status in DecisionPayload.statuses)
              ChoiceChip(
                key: ValueKey<String>('knowledge-decision-status-$status'),
                label: Text(_ideaLabel(status)),
                selected: payload.status == status,
                onSelected: (_) =>
                    context.onDraftChanged(payload.copyWith(status: status)),
              ),
          ],
        ),
        if (suggested != payload.status &&
            payload.status != 'reviewing' &&
            payload.status != 'reversed') ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey<String>('knowledge-decision-status-suggestion'),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(buildContext).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Suggested status: ${_ideaLabel(suggested)}'),
                ),
                TextButton(
                  key: const ValueKey<String>(
                    'knowledge-decision-apply-status-suggestion',
                  ),
                  onPressed: () => context.onDraftChanged(
                    payload.copyWith(status: suggested),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text('Decision ${payload.decisionCompleted}/5'),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          key: const ValueKey<String>('knowledge-decision-progress'),
          value: payload.decisionCompleted / 5,
          borderRadius: BorderRadius.circular(999),
        ),
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-decision-question-field',
          label: 'Decision question',
          value: payload.question,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(question: value)),
        ),
        const SizedBox(height: 8),
        _field(
          key: 'knowledge-decision-context-field',
          label: 'Context',
          value: payload.context,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(context: value)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _field(
                key: 'knowledge-decision-owner-field',
                label: 'Owner',
                value: payload.owner,
                onChanged: (value) =>
                    context.onDraftChanged(payload.copyWith(owner: value)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _field(
                key: 'knowledge-decision-deadline-field',
                label: 'Deadline (YYYY-MM-DD)',
                value: payload.deadline,
                onChanged: (value) =>
                    context.onDraftChanged(payload.copyWith(deadline: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _field(
          key: 'knowledge-decision-review-date-field',
          label: 'Review date (YYYY-MM-DD)',
          value: payload.reviewDate,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(reviewDate: value)),
        ),
        const SizedBox(height: 8),
        Text('Confidence ${payload.confidence}%'),
        Slider(
          key: const ValueKey<String>('knowledge-decision-confidence-slider'),
          value: payload.confidence.toDouble(),
          min: 0,
          max: 100,
          label: '${payload.confidence}%',
          onChanged: (value) => context.onDraftChanged(
            payload.copyWith(confidence: value.round()),
          ),
        ),
        const SizedBox(height: 8),
        _decisionCriteriaEditor(payload),
        const SizedBox(height: 12),
        _decisionOptionsEditor(payload),
        if (payload.options.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Ranking', style: Theme.of(buildContext).textTheme.labelLarge),
          const SizedBox(height: 6),
          for (final option in payload.rankedOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                key: ValueKey<String>('knowledge-decision-rank-${option.id}'),
                children: [
                  Expanded(child: Text(option.title)),
                  if (scores[option.id] case final score?)
                    Text(score.toStringAsFixed(1)),
                  if (option.id == payload.recommendedOptionId) ...[
                    const SizedBox(width: 6),
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Recommended'),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey<String>('knowledge-decision-outcome-field'),
            initialValue: payload.selectedOptionId.isEmpty
                ? null
                : payload.selectedOptionId,
            decoration: const InputDecoration(
              labelText: 'Selected outcome',
              isDense: true,
            ),
            items: <DropdownMenuItem<String>>[
              for (final option in payload.options)
                DropdownMenuItem<String>(
                  value: option.id,
                  child: Text(option.title),
                ),
            ],
            onChanged: (value) => context.onDraftChanged(
              value == null
                  ? payload.copyWith(clearSelectedOption: true)
                  : payload.copyWith(selectedOptionId: value),
            ),
          ),
        ],
        if (recommended != null &&
            recommended.id != payload.selectedOptionId) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey<String>(
              'knowledge-decision-outcome-suggestion',
            ),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(buildContext).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(child: Text('Recommended: ${recommended.title}')),
                TextButton(
                  key: const ValueKey<String>(
                    'knowledge-decision-apply-outcome-suggestion',
                  ),
                  onPressed: () => context.onDraftChanged(
                    payload.copyWith(selectedOptionId: recommended.id),
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        _field(
          key: 'knowledge-decision-rationale-field',
          label: 'Rationale',
          value: payload.rationale,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(rationale: value)),
        ),
        const SizedBox(height: 8),
        _field(
          key: 'knowledge-decision-assumptions-field',
          label: 'Assumptions',
          value: payload.assumptions,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(assumptions: value)),
        ),
        const SizedBox(height: 8),
        _field(
          key: 'knowledge-decision-expected-outcome-field',
          label: 'Expected outcome',
          value: payload.expectedOutcome,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(expectedOutcome: value)),
        ),
        const SizedBox(height: 8),
        _field(
          key: 'knowledge-decision-review-notes-field',
          label: 'Review notes',
          value: payload.reviewNotes,
          lines: true,
          onChanged: (value) =>
              context.onDraftChanged(payload.copyWith(reviewNotes: value)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Text('Outcome review timeline')),
            IconButton(
              key: const ValueKey<String>(
                'knowledge-decision-review-entry-add',
              ),
              tooltip: 'Add outcome review',
              onPressed: () => context.onDraftChanged(
                payload.copyWith(
                  reviewEntries: <DecisionReviewEntry>[
                    ...payload.reviewEntries,
                    DecisionReviewEntry(
                      id: 'review-${const Uuid().v4()}',
                      date: DateTime.now().toIso8601String().split('T').first,
                      notes: 'New review',
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
        for (final entry in payload.reviewEntries)
          Card(
            key: ValueKey<String>(
              'knowledge-decision-review-entry-${entry.id}',
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: ValueKey<String>(
                            'knowledge-decision-review-date-${entry.id}',
                          ),
                          onPressed: () => _pickDecisionReviewDate(
                            buildContext,
                            payload,
                            entry,
                          ),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(entry.date),
                        ),
                      ),
                      IconButton(
                        key: ValueKey<String>(
                          'knowledge-decision-review-entry-delete-${entry.id}',
                        ),
                        tooltip: 'Delete review entry',
                        onPressed: () => context.onDraftChanged(
                          payload.copyWith(
                            reviewEntries: payload.reviewEntries
                                .where((item) => item.id != entry.id)
                                .toList(),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _field(
                    key: 'knowledge-decision-review-notes-${entry.id}',
                    label: 'Review notes',
                    value: entry.notes,
                    lines: true,
                    onChanged: (value) => _updateDecisionReviewEntry(
                      payload,
                      entry.copyWith(notes: value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var rating = 1; rating <= 5; rating++)
                        ChoiceChip(
                          key: ValueKey<String>(
                            'knowledge-decision-review-rating-${entry.id}-$rating',
                          ),
                          label: Text('$rating'),
                          selected: entry.rating == rating,
                          onSelected: (selected) => _updateDecisionReviewEntry(
                            payload,
                            entry.copyWith(
                              rating: selected ? rating : null,
                              clearRating: !selected,
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

  Widget _decisionCriteriaEditor(DecisionPayload payload) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Weighted criteria')),
          IconButton(
            key: const ValueKey<String>('knowledge-decision-criterion-add'),
            tooltip: 'Add criterion',
            onPressed: () {
              final id = _nextDecisionId(
                'criterion',
                payload.criteria.map((item) => item.id),
              );
              context.onDraftChanged(
                payload.copyWith(
                  criteria: <DecisionCriterion>[
                    ...payload.criteria,
                    DecisionCriterion(id: id, name: 'New criterion'),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      for (final criterion in payload.criteria)
        Padding(
          key: ValueKey<String>('knowledge-decision-criterion-${criterion.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _field(
                  key: 'knowledge-decision-criterion-name-${criterion.id}',
                  label: 'Criterion',
                  value: criterion.name,
                  onChanged: (value) => context.onDraftChanged(
                    payload.copyWith(
                      criteria: <DecisionCriterion>[
                        for (final item in payload.criteria)
                          item.id == criterion.id
                              ? item.copyWith(name: value)
                              : item,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  key: 'knowledge-decision-criterion-weight-${criterion.id}',
                  label: 'Weight',
                  value: criterion.weight.toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) => context.onDraftChanged(
                    payload.copyWith(
                      criteria: <DecisionCriterion>[
                        for (final item in payload.criteria)
                          item.id == criterion.id
                              ? item.copyWith(
                                  weight: double.tryParse(value) ?? 0,
                                )
                              : item,
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey<String>(
                  'knowledge-decision-criterion-delete-${criterion.id}',
                ),
                tooltip: 'Delete criterion',
                onPressed: () => context.onDraftChanged(
                  payload.removeCriterion(criterion.id),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _decisionOptionsEditor(DecisionPayload payload) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Options')),
          IconButton(
            key: const ValueKey<String>('knowledge-decision-option-add'),
            tooltip: 'Add option',
            onPressed: () {
              final id = _nextDecisionId(
                'option',
                payload.options.map((item) => item.id),
              );
              context.onDraftChanged(
                payload.copyWith(
                  options: <DecisionOption>[
                    ...payload.options,
                    DecisionOption(id: id, title: 'New option'),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
      for (final option in payload.options)
        Card(
          key: ValueKey<String>('knowledge-decision-option-${option.id}'),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        key: 'knowledge-decision-option-title-${option.id}',
                        label: 'Option',
                        value: option.title,
                        onChanged: (value) => _updateDecisionOption(
                          payload,
                          option.copyWith(title: value),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey<String>(
                        'knowledge-decision-option-delete-${option.id}',
                      ),
                      tooltip: 'Delete option',
                      onPressed: () => context.onDraftChanged(
                        payload.removeOption(option.id),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _field(
                  key: 'knowledge-decision-option-description-${option.id}',
                  label: 'Description',
                  value: option.description,
                  lines: true,
                  onChanged: (value) => _updateDecisionOption(
                    payload,
                    option.copyWith(description: value),
                  ),
                ),
                const SizedBox(height: 8),
                _decisionStringList(
                  title: 'Pros',
                  keyPrefix: 'knowledge-decision-option-${option.id}-pro',
                  values: option.pros,
                  onChanged: (values) => _updateDecisionOption(
                    payload,
                    option.copyWith(pros: values),
                  ),
                ),
                _decisionStringList(
                  title: 'Cons',
                  keyPrefix: 'knowledge-decision-option-${option.id}-con',
                  values: option.cons,
                  onChanged: (values) => _updateDecisionOption(
                    payload,
                    option.copyWith(cons: values),
                  ),
                ),
                _decisionStringList(
                  title: 'Risks',
                  keyPrefix: 'knowledge-decision-option-${option.id}-risk',
                  values: option.risks,
                  onChanged: (values) => _updateDecisionOption(
                    payload,
                    option.copyWith(risks: values),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Quantified risks')),
                    IconButton(
                      key: ValueKey<String>(
                        'knowledge-decision-option-${option.id}-risk-assessment-add',
                      ),
                      tooltip: 'Add quantified risk',
                      onPressed: () => _updateDecisionOption(
                        payload,
                        option.copyWith(
                          riskAssessments: <DecisionRisk>[
                            ...option.riskAssessments,
                            DecisionRisk(
                              id: 'risk-${const Uuid().v4()}',
                              title: 'New risk',
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
                for (final risk in option.riskAssessments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _field(
                                key:
                                    'knowledge-decision-risk-title-${option.id}-${risk.id}',
                                label: 'Risk',
                                value: risk.title,
                                onChanged: (value) => _updateDecisionOption(
                                  payload,
                                  option.copyWith(
                                    riskAssessments: <DecisionRisk>[
                                      for (final item in option.riskAssessments)
                                        item.id == risk.id
                                            ? item.copyWith(title: value)
                                            : item,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete quantified risk',
                              onPressed: () => _updateDecisionOption(
                                payload,
                                option.copyWith(
                                  riskAssessments: option.riskAssessments
                                      .where((item) => item.id != risk.id)
                                      .toList(),
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        Text(
                          'Probability ${risk.probability}/5 · Impact ${risk.impact}/5 · Exposure ${risk.exposure}/25',
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                key: ValueKey<String>(
                                  'knowledge-decision-risk-probability-${option.id}-${risk.id}',
                                ),
                                value: risk.probability.toDouble(),
                                min: 1,
                                max: 5,
                                divisions: 4,
                                onChanged: (value) => _updateDecisionOption(
                                  payload,
                                  option.copyWith(
                                    riskAssessments: <DecisionRisk>[
                                      for (final item in option.riskAssessments)
                                        item.id == risk.id
                                            ? item.copyWith(
                                                probability: value.round(),
                                              )
                                            : item,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                key: ValueKey<String>(
                                  'knowledge-decision-risk-impact-${option.id}-${risk.id}',
                                ),
                                value: risk.impact.toDouble(),
                                min: 1,
                                max: 5,
                                divisions: 4,
                                onChanged: (value) => _updateDecisionOption(
                                  payload,
                                  option.copyWith(
                                    riskAssessments: <DecisionRisk>[
                                      for (final item in option.riskAssessments)
                                        item.id == risk.id
                                            ? item.copyWith(
                                                impact: value.round(),
                                              )
                                            : item,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                for (final criterion in payload.criteria) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${criterion.name}: ${option.scores[criterion.id] ?? 5}/10',
                  ),
                  Slider(
                    key: ValueKey<String>(
                      'knowledge-decision-score-${option.id}-${criterion.id}',
                    ),
                    value: (option.scores[criterion.id] ?? 5).toDouble(),
                    min: 1,
                    max: 10,
                    label: '${option.scores[criterion.id] ?? 5}',
                    onChanged: (value) {
                      final scores = Map<String, int>.from(option.scores)
                        ..[criterion.id] = value.round();
                      _updateDecisionOption(
                        payload,
                        option.copyWith(scores: scores),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );

  Widget _decisionStringList({
    required String title,
    required String keyPrefix,
    required List<String> values,
    required ValueChanged<List<String>> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            key: ValueKey<String>('$keyPrefix-add'),
            tooltip: 'Add $title',
            onPressed: () => onChanged(<String>[...values, 'New item']),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      for (var index = 0; index < values.length; index++)
        Row(
          children: [
            Expanded(
              child: _field(
                key: '$keyPrefix-field-$index',
                label: '$title ${index + 1}',
                value: values[index],
                onChanged: (value) {
                  final updated = List<String>.of(values);
                  updated[index] = value;
                  onChanged(updated);
                },
              ),
            ),
            IconButton(
              key: ValueKey<String>('$keyPrefix-delete-$index'),
              tooltip: 'Delete item',
              onPressed: () {
                final updated = List<String>.of(values)..removeAt(index);
                onChanged(updated);
              },
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
          ],
        ),
    ],
  );

  Future<void> _pickDecisionReviewDate(
    BuildContext buildContext,
    DecisionPayload payload,
    DecisionReviewEntry entry,
  ) async {
    final initialDate = DateTime.tryParse(entry.date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: buildContext,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !buildContext.mounted) return;
    _updateDecisionReviewEntry(
      payload,
      entry.copyWith(
        date:
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      ),
    );
  }

  void _updateDecisionReviewEntry(
    DecisionPayload payload,
    DecisionReviewEntry updated,
  ) => context.onDraftChanged(
    payload.copyWith(
      reviewEntries: <DecisionReviewEntry>[
        for (final entry in payload.reviewEntries)
          entry.id == updated.id ? updated : entry,
      ],
    ),
  );

  void _updateDecisionOption(DecisionPayload payload, DecisionOption updated) =>
      context.onDraftChanged(
        payload.copyWith(
          options: <DecisionOption>[
            for (final option in payload.options)
              option.id == updated.id ? updated : option,
          ],
        ),
      );

  Widget _quoteFields() {
    final payload = context.typedDraft is QuotePayload
        ? context.typedDraft as QuotePayload
        : QuotePayload.fromNode(context.node);
    return QuoteDiscoveryPanel(
      node: context.node,
      payload: payload,
      manualEditor: _QuoteFields(context: context, payload: payload),
      onBodyChanged: context.onBodyChanged,
      onPayloadChanged: context.onDraftChanged,
    );
  }

  Widget _field({
    required String key,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    bool lines = false,
    TextInputType? keyboardType,
    TextEditingController? controller,
    FocusNode? focusNode,
  }) => TextFormField(
    key: ValueKey<String>(key),
    controller: controller,
    focusNode: focusNode,
    initialValue: controller == null ? value : null,
    decoration: InputDecoration(labelText: label, isDense: true),
    keyboardType: keyboardType,
    minLines: lines ? 2 : 1,
    maxLines: lines ? 6 : 1,
    onChanged: onChanged,
  );

  Widget _audioFields(BuildContext buildContext) {
    final payload = context.typedDraft is AudioPayload
        ? context.typedDraft as AudioPayload
        : AudioPayload.fromNode(context.node);
    return AudioNodeEditor(context: context, payload: payload);
  }

  Widget _canvasFields(BuildContext buildContext) {
    final payload = context.typedDraft is CanvasPayload
        ? context.typedDraft as CanvasPayload
        : CanvasPayload.fromNode(context.node);
    return CanvasNodeEditor(
      payload: payload,
      onChanged: context.onDraftChanged,
      onOpenCanvas: context.onKnowledgeAction == null
          ? null
          : () async {
              await context.onKnowledgeAction!(
                OpenSubCanvasAction(context.node.id),
              );
            },
    );
  }
}

final class _JournalFields extends StatefulWidget {
  const _JournalFields({required this.context, required this.payload});

  final NodeEditContext context;
  final JournalPayload payload;

  @override
  State<_JournalFields> createState() => _JournalFieldsState();
}

final class _JournalFieldsState extends State<_JournalFields> {
  late JournalPayload _draft;
  late TextEditingController _highlightController;
  late TextEditingController _promptController;
  late TextEditingController _gratitudeController;

  @override
  void initState() {
    super.initState();
    _draft = widget.payload;
    _highlightController = TextEditingController(text: _draft.dailyHighlight);
    _promptController = TextEditingController(text: _draft.prompt);
    _gratitudeController = TextEditingController(
      text: _draft.gratitude.join('\n'),
    );
  }

  @override
  void didUpdateWidget(covariant _JournalFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.node.id != widget.context.node.id) {
      _draft = widget.payload;
      _highlightController.text = _draft.dailyHighlight;
      _promptController.text = _draft.prompt;
      _gratitudeController.text = _draft.gratitude.join('\n');
    } else if (_draft != widget.payload) {
      _draft = widget.payload;
      if (_highlightController.text != _draft.dailyHighlight) {
        _highlightController.text = _draft.dailyHighlight;
      }
      if (_promptController.text != _draft.prompt) {
        _promptController.text = _draft.prompt;
      }
      final gratitudeText = _draft.gratitude.join('\n');
      if (_gratitudeController.text != gratitudeText) {
        _gratitudeController.text = gratitudeText;
      }
    }
  }

  @override
  void dispose() {
    _highlightController.dispose();
    _promptController.dispose();
    _gratitudeController.dispose();
    super.dispose();
  }

  void _emit(JournalPayload payload) {
    setState(() => _draft = payload);
    widget.context.onDraftChanged(payload);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _draft;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date: ${payload.date.year.toString().padLeft(4, '0')}-${payload.date.month.toString().padLeft(2, '0')}-${payload.date.day.toString().padLeft(2, '0')}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text('Mood Rating', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var score = 1; score <= 10; score++)
              ChoiceChip(
                key: ValueKey<String>('knowledge-journal-mood-$score'),
                label: Text(
                  _moodLabel(score),
                  style: const TextStyle(fontSize: 11),
                ),
                selected: payload.mood == score,
                onSelected: (selected) {
                  _emit(
                    payload.copyWith(
                      mood: selected ? score : null,
                      clearMood: !selected,
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Energy Rating', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var score = 1; score <= 10; score++)
              ChoiceChip(
                key: ValueKey<String>('knowledge-journal-energy-$score'),
                label: Text('⚡ $score', style: const TextStyle(fontSize: 11)),
                selected: payload.energy == score,
                onSelected: (selected) {
                  _emit(
                    payload.copyWith(
                      energy: selected ? score : null,
                      clearEnergy: !selected,
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Weather Condition', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final opt in JournalPayload.weatherOptions)
              ChoiceChip(
                key: ValueKey<String>('knowledge-journal-weather-$opt'),
                label: Text(_weatherLabel(opt)),
                selected: payload.weather == opt,
                onSelected: (selected) {
                  _emit(payload.copyWith(weather: selected ? opt : ''));
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('Periodic Review Badge', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          children: [
            FilterChip(
              key: const ValueKey<String>('knowledge-journal-weekly-review'),
              label: const Text('Weekly Review'),
              selected: payload.isWeeklyReview,
              onSelected: (val) => _emit(payload.copyWith(isWeeklyReview: val)),
            ),
            const SizedBox(width: 8),
            FilterChip(
              key: const ValueKey<String>('knowledge-journal-monthly-review'),
              label: const Text('Monthly Review'),
              selected: payload.isMonthlyReview,
              onSelected: (val) =>
                  _emit(payload.copyWith(isMonthlyReview: val)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey<String>('knowledge-journal-highlight-field'),
          controller: _highlightController,
          decoration: const InputDecoration(
            labelText: 'Daily Highlight / Win of the Day',
            isDense: true,
          ),
          onChanged: (value) => _emit(payload.copyWith(dailyHighlight: value)),
        ),
        const SizedBox(height: 10),
        Text('Reflection Prompt Template', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final template in JournalPayload.promptTemplates)
              ActionChip(
                label: Text(template, style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  _promptController.text = template;
                  _emit(payload.copyWith(prompt: template));
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: const ValueKey<String>('knowledge-journal-prompt-field'),
          controller: _promptController,
          decoration: const InputDecoration(
            labelText: 'Prompt / Focus Question',
            isDense: true,
          ),
          minLines: 2,
          maxLines: 4,
          onChanged: (value) => _emit(payload.copyWith(prompt: value)),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey<String>('knowledge-journal-gratitude-field'),
          controller: _gratitudeController,
          decoration: const InputDecoration(
            labelText: 'Gratitude List (one per line)',
            isDense: true,
          ),
          minLines: 2,
          maxLines: 4,
          onChanged: (value) =>
              _emit(payload.copyWith(gratitude: _commaLines(value))),
        ),
      ],
    );
  }

  String _moodLabel(int score) => switch (score) {
    1 || 2 => '😞 $score',
    3 || 4 => '🙁 $score',
    5 || 6 => '😐 $score',
    7 || 8 => '🙂 $score',
    _ => '😊 $score',
  };

  String _weatherLabel(String weather) => switch (weather) {
    'sunny' => '☀️ Sunny',
    'cloudy' => '⛅ Cloudy',
    'rainy' => '🌧️ Rainy',
    'stormy' => '🌩️ Stormy',
    'snowy' => '❄️ Snowy',
    _ => weather,
  };
}

final class _QuoteFields extends StatefulWidget {
  const _QuoteFields({required this.context, required this.payload});

  final NodeEditContext context;
  final QuotePayload payload;

  @override
  State<_QuoteFields> createState() => _QuoteFieldsState();
}

final class _QuoteFieldsState extends State<_QuoteFields> {
  late QuotePayload _draft;
  final _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.payload;
  }

  @override
  void didUpdateWidget(covariant _QuoteFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context.node.id != widget.context.node.id) {
      _draft = widget.payload;
    }
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _emit(QuotePayload payload) {
    setState(() => _draft = payload);
    widget.context.onDraftChanged(payload);
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty ||
        _draft.tags.any((item) => item.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    _emit(_draft.copyWith(tags: <String>[..._draft.tags, tag]));
    _tagController.clear();
  }

  Future<void> _editTag(String current) async {
    var edited = current;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit tag'),
        content: TextFormField(
          key: const ValueKey<String>('knowledge-quote-tag-edit-field'),
          initialValue: current,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) => edited = value,
          onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('knowledge-quote-tag-edit-save'),
            onPressed: () => Navigator.of(dialogContext).pop(edited),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final tag = result.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty) return;
    final updated = <String>[
      for (final item in _draft.tags)
        if (item == current) tag else item,
    ];
    _emit(_draft.copyWith(tags: updated));
  }

  Future<void> _copyQuote() async {
    final quote = widget.context.node.body.trim();
    if (quote.isEmpty) return;
    final text = _draft.author.trim().isEmpty
        ? quote
        : '?$quote? ? ${_draft.author.trim()}';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Quote copied')));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        key: const ValueKey<String>('knowledge-quote-author-field'),
        initialValue: _draft.author,
        decoration: const InputDecoration(labelText: 'Author', isDense: true),
        onChanged: (value) => _emit(_draft.copyWith(author: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey<String>('knowledge-quote-source-field'),
        initialValue: _draft.source,
        decoration: const InputDecoration(labelText: 'Source', isDense: true),
        onChanged: (value) => _emit(_draft.copyWith(source: value)),
      ),
      const SizedBox(height: 8),
      TextFormField(
        key: const ValueKey<String>('knowledge-quote-collection-field'),
        initialValue: _draft.collection,
        decoration: const InputDecoration(
          labelText: 'Collection',
          isDense: true,
        ),
        onChanged: (value) => _emit(_draft.copyWith(collection: value)),
      ),
      const SizedBox(height: 12),
      Text('Tags', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in _draft.tags)
            InputChip(
              key: ValueKey<String>('knowledge-quote-tag-$tag'),
              label: Text('#$tag'),
              onPressed: () => _editTag(tag),
              onDeleted: () => _emit(
                _draft.copyWith(
                  tags: _draft.tags
                      .where((item) => item != tag)
                      .toList(growable: false),
                ),
              ),
            ),
          SizedBox(
            width: 180,
            child: TextField(
              key: const ValueKey<String>('knowledge-quote-tag-input'),
              controller: _tagController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Add tag',
                prefixText: '#',
                isDense: true,
              ),
              onSubmitted: _addTag,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SwitchListTile.adaptive(
        key: const ValueKey<String>('knowledge-quote-favorite-toggle'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Favorite quote'),
        value: _draft.isFavorite,
        onChanged: (value) => _emit(_draft.copyWith(isFavorite: value)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('knowledge-quote-copy-action'),
          onPressed: widget.context.node.body.trim().isEmpty
              ? null
              : _copyQuote,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy quote'),
        ),
      ),
    ],
  );
}

final class _BookmarkFields extends StatefulWidget {
  const _BookmarkFields({required this.context, required this.payload});

  final NodeEditContext context;
  final LinkResourcePayload payload;

  @override
  State<_BookmarkFields> createState() => _BookmarkFieldsState();
}

final class _BookmarkFieldsState extends State<_BookmarkFields> {
  final TextEditingController _tagController = TextEditingController();
  late LinkResourcePayload _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.payload;
  }

  @override
  void didUpdateWidget(covariant _BookmarkFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    _draft = widget.payload;
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _emit(LinkResourcePayload payload) {
    setState(() => _draft = payload);
    widget.context.onDraftChanged(payload);
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty ||
        _draft.tags.any((item) => item.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    _emit(_draft.copyWith(tags: <String>[..._draft.tags, tag]));
    _tagController.clear();
  }

  void _removeTag(String tag) {
    _emit(
      _draft.copyWith(
        tags: _draft.tags.where((item) => item != tag).toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payload = _draft;
    final host = _bookmarkHost(payload.url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const ValueKey<String>('knowledge-bookmark-url-preview'),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.language_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.isEmpty ? 'Add a valid URL' : host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      payload.url.trim().isEmpty ? 'No URL yet' : payload.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey<String>('knowledge-bookmark-favorite'),
                tooltip: payload.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                onPressed: () =>
                    _emit(_draft.copyWith(isFavorite: !payload.isFavorite)),
                icon: Icon(
                  payload.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey<String>('knowledge-bookmark-url-field'),
          initialValue: payload.url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'URL', isDense: true),
          onChanged: (value) => _emit(_draft.copyWith(url: value)),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey<String>('knowledge-bookmark-why-field'),
          initialValue: payload.description,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Why saved',
            hintText: 'What makes this worth revisiting?',
            isDense: true,
          ),
          onChanged: (value) => _emit(_draft.copyWith(description: value)),
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey<String>('knowledge-bookmark-collection-field'),
          initialValue: payload.collection,
          decoration: const InputDecoration(
            labelText: 'Collection',
            hintText: 'Research, Inspiration, Read later...',
            isDense: true,
          ),
          onChanged: (value) => _emit(_draft.copyWith(collection: value)),
        ),
        const SizedBox(height: 12),
        Text('Reading status', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label, icon)
                in const <(String, String, IconData)>[
                  ('inbox', 'Inbox', Icons.inbox_outlined),
                  ('reading', 'Reading', Icons.chrome_reader_mode_outlined),
                  ('read', 'Read', Icons.check_circle_outline_rounded),
                ])
              ChoiceChip(
                key: ValueKey<String>('knowledge-bookmark-status-$value'),
                selected: payload.bookmarkStatus == value,
                avatar: Icon(icon, size: 16),
                label: Text(label),
                onSelected: (_) =>
                    _emit(_draft.copyWith(bookmarkStatus: value)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Tags', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in payload.tags)
              InputChip(
                key: ValueKey<String>('knowledge-bookmark-tag-$tag'),
                label: Text('#$tag'),
                onDeleted: () => _removeTag(tag),
              ),
            SizedBox(
              width: 180,
              child: TextField(
                key: const ValueKey<String>('knowledge-bookmark-tag-input'),
                controller: _tagController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'Add tag',
                  isDense: true,
                  prefixText: '#',
                ),
                onSubmitted: _addTag,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey<String>('knowledge-bookmark-open-action'),
          onPressed:
              payload.validate(title: widget.context.node.title).isEmpty &&
                  payload.url.trim().isNotEmpty &&
                  widget.context.onKnowledgeAction != null
              ? () async => widget.context.onKnowledgeAction!(
                  OpenKnowledgeExternalAction(payload.url),
                )
              : null,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Open link'),
        ),
      ],
    );
  }
}

final class _LocalError extends StatelessWidget {
  const _LocalError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

String _nextDecisionId(String prefix, Iterable<String> existingIds) {
  final existing = existingIds.toSet();
  var index = existing.length + 1;
  while (existing.contains('$prefix-$index')) {
    index++;
  }
  return '$prefix-$index';
}

String _bookmarkHost(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
  return uri.host.replaceFirst(RegExp(r'^www\.'), '');
}

String _ideaLabel(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

List<String> _commaLines(String value) => value
    .split(RegExp(r'[,\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
