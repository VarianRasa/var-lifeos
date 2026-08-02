import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/audio_node_editor.dart';
import 'package:var_app/features/mindmap/presentation/node_editors/knowledge_node_editors.dart';
import 'package:var_app/features/mindmap/presentation/node_type_content.dart';
import 'package:var_app/features/mindmap/presentation/node_type_inline_editor.dart';

void main() {
  const types = <NodeType>{
    NodeType.journal,
    NodeType.link,
    NodeType.bookmark,
    NodeType.resource,
    NodeType.idea,
    NodeType.question,
    NodeType.decision,
    NodeType.quote,
    NodeType.audio,
    NodeType.canvas,
  };
  for (final type in types) {
    for (final preset in const <NodeSizePreset>{
      NodeSizePreset.compact,
      NodeSizePreset.standard,
      NodeSizePreset.large,
      NodeSizePreset.wide,
    }) {
      testWidgets('${type.name} renders $preset without overflow', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: preset == NodeSizePreset.compact ? 220 : 520,
              height: preset == NodeSizePreset.compact ? 130 : 360,
              child: buildNodeTypeContent(
                NodeRenderContext(node: _node(type), effectivePreset: preset),
              ),
            ),
          ),
        );
        expect(
          find.byKey(ValueKey<String>('knowledge-${type.name}-${preset.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('long text thresholds expand for large and wide presets', (
    tester,
  ) async {
    final node = _node(NodeType.idea).copyWith(body: 'Long body ' * 80);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeContent(
          NodeRenderContext(
            node: node,
            effectivePreset: NodeSizePreset.standard,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('knowledge-body')))
          .maxLines,
      5,
    );
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeContent(
          NodeRenderContext(node: node, effectivePreset: NodeSizePreset.wide),
        ),
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('knowledge-body')))
          .maxLines,
      14,
    );
  });

  testWidgets('link editor preserves URL validation and production key', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.bookmark);
    await tester.pumpWidget(
      _app(
        buildNodeTypeInlineEditor(
          _editContext(
            node,
            const LinkResourcePayload(type: NodeType.bookmark, url: 'file://x'),
            drafts,
            validationErrors: const ['URL scheme is not supported.'],
          ),
        ),
      ),
    );
    expect(find.text('URL scheme is not supported.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-bookmark-url-field')),
      'https://example.com',
    );
    final payload = drafts.last as LinkResourcePayload;
    expect(payload.url, 'https://example.com');
    expect(payload.toData(node.data)['url'], 'https://example.com');
  });

  testWidgets('bookmark editor manages saved-link metadata', (tester) async {
    final node = _node(NodeType.bookmark);
    Object draft = const LinkResourcePayload(
      type: NodeType.bookmark,
      url: 'https://www.example.com/article',
      tags: <String>['flutter'],
    );
    final actions = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => buildKnowledgeNodeInlineEditor(
                NodeEditContext(
                  node: node,
                  typedDraft: draft,
                  effectivePreset: NodeSizePreset.standard,
                  validationErrors: const <String>[],
                  onTitleChanged: (_) {},
                  onBodyChanged: (_) {},
                  onDraftChanged: (value) {
                    draft = value;
                    setState(() {});
                  },
                  onNodeDraftChanged: (_) {},
                  onKnowledgeAction: (action) async => actions.add(action),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-bookmark-why-field')),
      'Useful reference',
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-bookmark-collection-field')),
      'Research',
    );
    await tester.tap(
      find.byKey(const ValueKey('knowledge-bookmark-status-reading')),
    );
    await tester.tap(find.byKey(const ValueKey('knowledge-bookmark-favorite')));
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-bookmark-tag-input')),
      'design',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    var payload = draft as LinkResourcePayload;
    expect(payload.description, 'Useful reference');
    expect(payload.collection, 'Research');
    expect(payload.bookmarkStatus, 'reading');
    expect(payload.isFavorite, isTrue);
    expect(payload.tags, ['flutter', 'design']);

    final flutterChip = tester.widget<InputChip>(
      find.byKey(const ValueKey('knowledge-bookmark-tag-flutter')),
    );
    flutterChip.onDeleted!();
    await tester.pump();
    payload = draft as LinkResourcePayload;
    expect(payload.tags, ['design']);

    final openAction = find.byKey(
      const ValueKey('knowledge-bookmark-open-action'),
    );
    await tester.ensureVisible(openAction);
    await tester.pump();
    await tester.tap(openAction);
    await tester.pump();
    expect(actions.single, isA<OpenKnowledgeExternalAction>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('idea editor emits structured experiment draft', (tester) async {
    final drafts = <Object>[];
    final node = _node(NodeType.idea);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            node,
            const IdeaPayload(
              maturity: 'spark',
              hypothesis: 'Initial hypothesis',
            ),
            drafts,
          ),
        ),
      ),
    );

    expect(find.text('Suggested stage: Exploring'), findsOneWidget);
    expect(find.text('Validation 1/3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('knowledge-idea-impact-high')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-idea-effort-medium')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('knowledge-idea-confidence-slider')),
      findsOneWidget,
    );
    final confidenceSlider = tester.widget<Slider>(
      find.byKey(const ValueKey('knowledge-idea-confidence-slider')),
    );
    expect(confidenceSlider.divisions, isNull);

    await tester.tap(
      find.byKey(const ValueKey('knowledge-idea-stage-exploring')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-idea-evidence-field')),
      'Five interviews',
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-idea-next-action-field')),
      'Build prototype',
    );

    final latest = drafts.last as IdeaPayload;
    expect(latest.maturity, 'exploring');
    expect(latest.hypothesis, 'Initial hypothesis');
    expect(latest.evidence, 'Five interviews');
    expect(latest.nextAction, 'Build prototype');
  });

  testWidgets('idea multiline fields survive local draft echo', (tester) async {
    final node = _node(NodeType.idea);
    Object draft = const IdeaPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  if (value case final IdeaPayload idea) {
                    draft = IdeaPayload(
                      maturity: idea.maturity,
                      hypothesis: idea.hypothesis,
                      impact: idea.impact,
                      effort: idea.effort,
                      confidence: idea.confidence,
                      evidence: idea.evidence,
                      nextAction: idea.nextAction,
                    );
                  } else {
                    draft = value;
                  }
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> typeProgressively(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      for (var index = 1; index <= value.length; index++) {
        tester.testTextInput.enterText(value.substring(0, index));
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
      }
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: finder, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        value,
      );
    }

    await typeProgressively(
      'knowledge-idea-hypothesis-field',
      'Faster capture',
    );
    await typeProgressively('knowledge-idea-evidence-field', 'Five interviews');
    await typeProgressively(
      'knowledge-idea-next-action-field',
      'Build prototype',
    );

    final payload = draft as IdeaPayload;
    expect(payload.hypothesis, 'Faster capture');
    expect(payload.evidence, 'Five interviews');
    expect(payload.nextAction, 'Build prototype');
    expect(tester.takeException(), isNull);
  });

  testWidgets('idea confidence slider keeps one continuous drag', (
    tester,
  ) async {
    final node = _node(NodeType.idea);
    Object draft = const IdeaPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  if (value case final IdeaPayload idea) {
                    draft = IdeaPayload(
                      maturity: idea.maturity,
                      hypothesis: idea.hypothesis,
                      impact: idea.impact,
                      effort: idea.effort,
                      confidence: idea.confidence,
                      evidence: idea.evidence,
                      nextAction: idea.nextAction,
                    );
                  } else {
                    draft = value;
                  }
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('knowledge-idea-confidence-slider'),
    );
    await tester.ensureVisible(finder);
    await tester.pump();
    final rect = tester.getRect(finder);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.1, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * 0.4, rect.center.dy));
    await tester.pump();
    final firstValue = (draft as IdeaPayload).confidence;
    await gesture.moveTo(Offset(rect.left + rect.width * 0.8, rect.center.dy));
    await tester.pump();
    final secondValue = (draft as IdeaPayload).confidence;
    await gesture.up();

    expect(firstValue, greaterThan(0));
    expect(secondValue, greaterThan(firstValue));
    expect(tester.takeException(), isNull);
  });

  testWidgets('question editor manages structured research draft', (
    tester,
  ) async {
    final node = _node(NodeType.question);
    Object draft = const QuestionPayload(questionText: 'What should ship?');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  draft = value;
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Suggested status: Open'), findsNothing);
    expect(find.text('Research 1/4'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(
            find.byKey(
              const ValueKey<String>('knowledge-question-confidence-slider'),
            ),
          )
          .divisions,
      isNull,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('knowledge-question-possible-answer-add'),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('knowledge-question-possible-answer-field-0'),
      ),
      'Ship keyboard capture',
    );
    final sourceAdd = find.byKey(
      const ValueKey<String>('knowledge-question-source-add'),
    );
    await tester.ensureVisible(sourceAdd);
    await tester.pump();
    await tester.tap(sourceAdd);
    await tester.pump();
    final sourceField = find.byKey(
      const ValueKey<String>('knowledge-question-source-field-0'),
    );
    await tester.ensureVisible(sourceField);
    await tester.pump();
    await tester.enterText(sourceField, 'Usability study');
    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-question-answer-field')),
      'Ship keyboard capture',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('knowledge-question-evidence-field')),
      'Fastest median time',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('knowledge-question-next-action-field'),
      ),
      'Validate on mobile',
    );

    final payload = draft as QuestionPayload;
    expect(payload.possibleAnswers, <String>['Ship keyboard capture']);
    expect(payload.questionSources, <String>['Usability study']);
    expect(payload.answer, 'Ship keyboard capture');
    expect(payload.evidence, 'Fastest median time');
    expect(payload.nextResearchAction, 'Validate on mobile');
    expect(payload.suggestedInvestigationStatus, 'answered');

    await tester.tap(
      find.byKey(
        const ValueKey<String>('knowledge-question-possible-answer-delete-0'),
      ),
    );
    await tester.pump();
    final sourceDelete = find.byKey(
      const ValueKey<String>('knowledge-question-source-delete-0'),
    );
    await tester.ensureVisible(sourceDelete);
    await tester.pump();
    await tester.tap(sourceDelete);
    await tester.pump();
    expect((draft as QuestionPayload).possibleAnswers, isEmpty);
    expect((draft as QuestionPayload).questionSources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('question multiline fields survive local draft echo', (
    tester,
  ) async {
    final node = _node(NodeType.question);
    Object draft = const QuestionPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  if (value case final QuestionPayload question) {
                    draft = QuestionPayload(
                      investigationStatus: question.investigationStatus,
                      questionText: question.questionText,
                      questionContext: question.questionContext,
                      possibleAnswers: question.possibleAnswers,
                      answer: question.answer,
                      evidence: question.evidence,
                      questionSources: question.questionSources,
                      nextResearchAction: question.nextResearchAction,
                      questionConfidence: question.questionConfidence,
                    );
                  } else {
                    draft = value;
                  }
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> typeProgressively(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      for (var index = 1; index <= value.length; index++) {
        tester.testTextInput.enterText(value.substring(0, index));
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
      }
    }

    await typeProgressively('knowledge-question-text-field', 'Why now?');
    await typeProgressively(
      'knowledge-question-context-field',
      'Customer context',
    );
    await typeProgressively(
      'knowledge-question-answer-field',
      'Because demand increased',
    );
    await typeProgressively(
      'knowledge-question-evidence-field',
      'Usage doubled',
    );
    await typeProgressively(
      'knowledge-question-next-action-field',
      'Interview five users',
    );

    final payload = draft as QuestionPayload;
    expect(payload.questionText, 'Why now?');
    expect(payload.questionContext, 'Customer context');
    expect(payload.answer, 'Because demand increased');
    expect(payload.evidence, 'Usage doubled');
    expect(payload.nextResearchAction, 'Interview five users');
    expect(tester.takeException(), isNull);
  });

  testWidgets('question confidence slider keeps one continuous drag', (
    tester,
  ) async {
    final node = _node(NodeType.question);
    Object draft = const QuestionPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  draft = value;
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('knowledge-question-confidence-slider'),
    );
    await tester.ensureVisible(finder);
    await tester.pump();
    final rect = tester.getRect(finder);
    final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * 0.1, rect.center.dy),
    );
    await gesture.moveTo(Offset(rect.left + rect.width * 0.4, rect.center.dy));
    await tester.pump();
    final firstValue = (draft as QuestionPayload).questionConfidence;
    await gesture.moveTo(Offset(rect.left + rect.width * 0.8, rect.center.dy));
    await tester.pump();
    final secondValue = (draft as QuestionPayload).questionConfidence;
    await gesture.up();

    expect(firstValue, greaterThan(0));
    expect(secondValue, greaterThan(firstValue));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision editor manages matrix workflow', (tester) async {
    final node = _node(NodeType.decision);
    Object draft = const DecisionPayload(
      status: 'draft',
      question: 'Which option?',
      criteria: <DecisionCriterion>[
        DecisionCriterion(id: 'impact', name: 'Impact', weight: 2),
      ],
      options: <DecisionOption>[
        DecisionOption(
          id: 'a',
          title: 'Option A',
          scores: <String, int>{'impact': 5},
        ),
        DecisionOption(
          id: 'b',
          title: 'Option B',
          scores: <String, int>{'impact': 9},
        ),
      ],
      selectedOptionId: 'a',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  draft = value;
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Suggested status: Evaluating'), findsOneWidget);
    expect(find.text('Decision 4/5'), findsOneWidget);
    expect(find.text('Recommended: Option B'), findsOneWidget);
    expect(
      tester
          .widget<Slider>(
            find.byKey(
              const ValueKey<String>('knowledge-decision-confidence-slider'),
            ),
          )
          .divisions,
      isNull,
    );

    final apply = find.byKey(
      const ValueKey<String>('knowledge-decision-apply-outcome-suggestion'),
    );
    await tester.ensureVisible(apply);
    await tester.pump();
    await tester.tap(apply);
    await tester.pump();
    expect((draft as DecisionPayload).selectedOptionId, 'b');

    final addCriterion = find.byKey(
      const ValueKey<String>('knowledge-decision-criterion-add'),
    );
    await tester.ensureVisible(addCriterion);
    await tester.pump();
    await tester.tap(addCriterion);
    await tester.pump();
    expect((draft as DecisionPayload).criteria, hasLength(2));

    final addOption = find.byKey(
      const ValueKey<String>('knowledge-decision-option-add'),
    );
    await tester.ensureVisible(addOption);
    await tester.pump();
    await tester.tap(addOption);
    await tester.pump();
    expect((draft as DecisionPayload).options, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision multiline fields survive local draft echo', (
    tester,
  ) async {
    final node = _node(NodeType.decision);
    Object draft = const DecisionPayload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  if (value case final DecisionPayload decision) {
                    draft = DecisionPayload(
                      status: decision.status,
                      question: decision.question,
                      context: decision.context,
                      owner: decision.owner,
                      deadline: decision.deadline,
                      reviewDate: decision.reviewDate,
                      confidence: decision.confidence,
                      criteria: decision.criteria,
                      options: decision.options,
                      selectedOptionId: decision.selectedOptionId,
                      rationale: decision.rationale,
                      assumptions: decision.assumptions,
                      expectedOutcome: decision.expectedOutcome,
                      reviewNotes: decision.reviewNotes,
                    );
                  } else {
                    draft = value;
                  }
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    Future<void> typeProgressively(String key, String value) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      for (var index = 1; index <= value.length; index++) {
        tester.testTextInput.enterText(value.substring(0, index));
        await tester.pump();
        final editable = tester.widget<EditableText>(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
      }
    }

    await typeProgressively(
      'knowledge-decision-question-field',
      'Which option?',
    );
    await typeProgressively(
      'knowledge-decision-context-field',
      'Beta release context',
    );
    await typeProgressively(
      'knowledge-decision-rationale-field',
      'Best weighted value',
    );
    await typeProgressively(
      'knowledge-decision-assumptions-field',
      'Capacity remains stable',
    );
    await typeProgressively(
      'knowledge-decision-expected-outcome-field',
      'Faster activation',
    );
    await typeProgressively(
      'knowledge-decision-review-notes-field',
      'Review in one month',
    );

    final payload = draft as DecisionPayload;
    expect(payload.question, 'Which option?');
    expect(payload.context, 'Beta release context');
    expect(payload.rationale, 'Best weighted value');
    expect(payload.assumptions, 'Capacity remains stable');
    expect(payload.expectedOutcome, 'Faster activation');
    expect(payload.reviewNotes, 'Review in one month');
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision sliders keep one continuous drag', (tester) async {
    final node = _node(NodeType.decision);
    Object draft = const DecisionPayload(
      criteria: <DecisionCriterion>[
        DecisionCriterion(id: 'impact', name: 'Impact'),
      ],
      options: <DecisionOption>[DecisionOption(id: 'a', title: 'Option A')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => buildKnowledgeNodeInlineEditor(
              NodeEditContext(
                node: node,
                typedDraft: draft,
                effectivePreset: NodeSizePreset.standard,
                validationErrors: const <String>[],
                onTitleChanged: (_) {},
                onBodyChanged: (_) {},
                onDraftChanged: (value) {
                  draft = value;
                  setState(() {});
                },
                onNodeDraftChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    Future<List<int>> dragSlider(
      String key,
      int Function(DecisionPayload payload) read,
    ) async {
      final finder = find.byKey(ValueKey<String>(key));
      await tester.ensureVisible(finder);
      await tester.pump();
      final rect = tester.getRect(finder);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.1, rect.center.dy),
      );
      await gesture.moveTo(
        Offset(rect.left + rect.width * 0.4, rect.center.dy),
      );
      await tester.pump();
      final first = read(draft as DecisionPayload);
      await gesture.moveTo(
        Offset(rect.left + rect.width * 0.8, rect.center.dy),
      );
      await tester.pump();
      final second = read(draft as DecisionPayload);
      await gesture.up();
      return <int>[first, second];
    }

    final confidence = await dragSlider(
      'knowledge-decision-confidence-slider',
      (payload) => payload.confidence,
    );
    final score = await dragSlider(
      'knowledge-decision-score-a-impact',
      (payload) => payload.options.first.scores['impact'] ?? 0,
    );

    expect(confidence[0], greaterThan(0));
    expect(confidence[1], greaterThan(confidence[0]));
    expect(score[0], greaterThan(1));
    expect(score[1], greaterThan(score[0]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision options and quote attribution use production keys', (
    tester,
  ) async {
    final decisionDrafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            _node(NodeType.decision),
            const DecisionPayload(
              options: <DecisionOption>[
                DecisionOption(id: 'a', title: 'A'),
                DecisionOption(id: 'b', title: 'B'),
              ],
            ),
            decisionDrafts,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-decision-option-title-a')),
      'Ship',
    );
    expect(
      (decisionDrafts.last as DecisionPayload).options.first.title,
      'Ship',
    );
    final quoteDrafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            _node(NodeType.quote),
            const QuotePayload(author: 'Ada'),
            quoteDrafts,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-quote-author-field')),
      'Grace Hopper',
    );
    expect((quoteDrafts.last as QuotePayload).author, 'Grace Hopper');
  });

  testWidgets('quote editor manages collection tags favorite and copy', (
    tester,
  ) async {
    final drafts = <Object>[];
    ClipboardData? copiedData;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedData = ClipboardData(
            text:
                (call.arguments as Map<Object?, Object?>)['text']?.toString() ??
                '',
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final node = _node(NodeType.quote).copyWith(body: 'Stay curious.');

    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            node,
            const QuotePayload(author: 'Ada', tags: <String>['wisdom']),
            drafts,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-quote-collection-field')),
      'Computing',
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-quote-tag-input')),
      'history',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byKey(const ValueKey('knowledge-quote-tag-history')), findsOne);

    await tester.tap(find.byKey(const ValueKey('knowledge-quote-tag-wisdom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-quote-tag-edit-field')),
      'insight',
    );
    await tester.tap(
      find.byKey(const ValueKey('knowledge-quote-tag-edit-save')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('knowledge-quote-tag-insight')), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('knowledge-quote-favorite-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('knowledge-quote-copy-action')));
    await tester.pump();

    final payload = drafts.last as QuotePayload;
    expect(payload.collection, 'Computing');
    expect(payload.tags, <String>['insight', 'history']);
    expect(payload.isFavorite, isTrue);
    expect(copiedData?.text, '?Stay curious.? ? Ada');
    expect(tester.takeException(), isNull);
  });

  testWidgets('link and bookmark open through callback-only action', (
    tester,
  ) async {
    for (final type in const [NodeType.link, NodeType.bookmark]) {
      final actions = <Object>[];
      final node = _node(type);
      await tester.pumpWidget(
        _app(
          buildKnowledgeNodeInlineEditor(
            _editContext(
              node,
              LinkResourcePayload.fromNode(node),
              <Object>[],
              onKnowledgeAction: (action) async => actions.add(action),
            ),
          ),
        ),
      );
      final openAction = find.byKey(
        ValueKey<String>('knowledge-${type.name}-open-action'),
      );
      await tester.ensureVisible(openAction);
      await tester.pump();
      await tester.tap(openAction);
      await tester.pump();
      expect(actions.last, isA<OpenKnowledgeExternalAction>());
      expect(
        (actions.last as OpenKnowledgeExternalAction).target,
        startsWith('https://'),
      );
    }
  });

  testWidgets('audio and canvas actions emit callback-only action events', (
    tester,
  ) async {
    final actions = <Object>[];
    final audio = _node(NodeType.audio);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            audio,
            AudioPayload.fromNode(audio),
            <Object>[],
            onKnowledgeAction: (action) async {
              actions.add(action);
              if (action is PickAudioFileAction) action.result.complete(null);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('audio-choose-file-action')));
    await tester.pump();
    expect(actions.last, isA<PickAudioFileAction>());
    final canvas = _node(NodeType.canvas);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            canvas,
            CanvasPayload.fromNode(canvas),
            <Object>[],
            onKnowledgeAction: (action) async => actions.add(action),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('knowledge-canvas-open-action')),
    );
    await tester.pump();
    expect(actions.last, isA<OpenSubCanvasAction>());
    expect((actions.last as OpenSubCanvasAction).nodeId, canvas.id);
  });

  testWidgets('audio URL field keeps pasted URL with slash characters', (
    tester,
  ) async {
    final audio = _node(
      NodeType.audio,
    ).copyWith(data: const AudioPayload().toData(const <String, Object?>{}));
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(audio, AudioPayload.fromNode(audio), drafts),
        ),
      ),
    );
    const url = 'https://cdn.example.test/audio/voice-note.mp3';
    final field = find.byKey(const ValueKey('audio-online-url-field'));

    await tester.enterText(field, 'https:');
    await tester.pump();

    final partialEditable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(partialEditable.focusNode.hasFocus, isTrue);

    await tester.enterText(field, url);
    await tester.pump();

    expect(find.text(url), findsWidgets);
    expect((drafts.last as AudioPayload).remoteUrl, url);

    const transcript = 'First line / second line';
    final transcriptField = find.byKey(
      const ValueKey('audio-transcript-field'),
    );
    await tester.enterText(transcriptField, 'First');
    await tester.pump();
    final transcriptEditable = tester.widget<EditableText>(
      find.descendant(of: transcriptField, matching: find.byType(EditableText)),
    );
    expect(transcriptEditable.focusNode.hasFocus, isTrue);
    await tester.enterText(transcriptField, transcript);
    await tester.pump();
    expect((drafts.last as AudioPayload).transcriptText, transcript);
  });

  testWidgets('audio delete action clears voice note after confirmation', (
    tester,
  ) async {
    const payload = AudioPayload(
      sourceType: AudioSourceType.attachment,
      attachmentId: 'voice-1',
      fileName: 'voice.wav',
      mimeType: 'audio/wav',
      sizeBytes: 128,
      transcriptText: 'Keep transcript',
    );
    final audio = _node(
      NodeType.audio,
    ).copyWith(data: payload.toData(const <String, Object?>{}));
    final drafts = <Object>[];
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            audio,
            payload,
            drafts,
            onKnowledgeAction: (action) async {
              if (action is DeleteAudioVoiceNoteAction) {
                action.result.complete(
                  action.payload.copyWith(
                    sourceType: AudioSourceType.none,
                    attachmentId: '',
                    fileName: '',
                    mimeType: '',
                    sizeBytes: 0,
                  ),
                );
              }
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('audio-delete-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final result = drafts.last as AudioPayload;
    expect(result.sourceType, AudioSourceType.none);
    expect(result.attachmentId, isEmpty);
    expect(result.transcriptText, 'Keep transcript');
  });

  testWidgets('field state resets on node id change only', (tester) async {
    final nodeA = _node(NodeType.idea).copyWith(id: 'idea-a', title: 'Idea A');
    final nodeB = _node(NodeType.idea).copyWith(id: 'idea-b', title: 'Idea B');
    await tester.pumpWidget(_editorApp(nodeA, const <String, Object?>{}));
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-idea-a-title-field')),
      'Unsaved idea',
    );
    await tester.pumpWidget(
      _editorApp(
        nodeA.copyWith(body: 'Draft rebuild'),
        const <String, Object?>{},
      ),
    );
    expect(find.text('Unsaved idea'), findsOneWidget);
    await tester.pumpWidget(_editorApp(nodeB, const <String, Object?>{}));
    expect(find.text('Idea B'), findsOneWidget);
    expect(find.text('Unsaved idea'), findsNothing);
  });

  testWidgets('sequential field edits preserve latest local typed draft', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.decision);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(
            node,
            const DecisionPayload(
              options: <DecisionOption>[
                DecisionOption(id: 'a', title: 'A'),
                DecisionOption(id: 'b', title: 'B'),
              ],
            ),
            drafts,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('knowledge-decision-question-field')),
      'Which option?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-decision-rationale-field')),
      'Best value',
    );

    final latest = drafts.last as DecisionPayload;
    expect(latest.question, 'Which option?');
    expect(latest.rationale, 'Best value');
    expect(latest.options.map((option) => option.title), ['A', 'B']);
  });

  testWidgets('journal choice chips update mood and energy draft', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.journal);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(node, JournalPayload.fromNode(node), drafts),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('knowledge-journal-mood-9')));
    await tester.pump();

    expect((drafts.last as JournalPayload).mood, 9);

    await tester.tap(find.byKey(const ValueKey('knowledge-journal-energy-8')));
    await tester.pump();

    expect((drafts.last as JournalPayload).energy, 8);
  });

  testWidgets('journal text fields keep focus and accept sequential typing', (
    tester,
  ) async {
    final drafts = <Object>[];
    final node = _node(NodeType.journal);
    await tester.pumpWidget(
      _app(
        buildKnowledgeNodeInlineEditor(
          _editContext(node, JournalPayload.fromNode(node), drafts),
        ),
      ),
    );

    final highlight = find.byKey(
      const ValueKey('knowledge-journal-highlight-field'),
    );
    final prompt = find.byKey(const ValueKey('knowledge-journal-prompt-field'));
    final gratitude = find.byKey(
      const ValueKey('knowledge-journal-gratitude-field'),
    );

    await tester.enterText(highlight, 'Shipped journal fix');
    await tester.pump();
    await tester.enterText(prompt, 'What did I learn?');
    await tester.pump();
    await tester.enterText(gratitude, 'Family\nHealth');
    await tester.pump();

    final latest = drafts.last as JournalPayload;
    expect(latest.dailyHighlight, 'Shipped journal fix');
    expect(latest.prompt, 'What did I learn?');
    expect(latest.gratitude, <String>['Family', 'Health']);
    expect(
      tester.widget<TextFormField>(gratitude).controller?.text,
      'Family\nHealth',
    );
  });

  testWidgets('external typed draft update resets type field state', (
    tester,
  ) async {
    final node = _node(NodeType.decision);
    await tester.pumpWidget(
      _editorApp(node, const DecisionPayload(question: 'Initial')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('knowledge-decision-question-field')),
      'Local edit',
    );
    await tester.pumpWidget(
      _editorApp(node, const DecisionPayload(question: 'Remote update')),
    );
    await tester.pump();

    expect(find.text('Remote update'), findsOneWidget);
    expect(find.text('Local edit'), findsNothing);
  });
}

NodeEditContext _editContext(
  MindmapNode node,
  Object draft,
  List<Object> drafts, {
  List<String> validationErrors = const [],
  NodeAsyncPayloadAction? onKnowledgeAction,
}) => NodeEditContext(
  node: node,
  typedDraft: draft,
  effectivePreset: NodeSizePreset.standard,
  validationErrors: validationErrors,
  onTitleChanged: (_) {},
  onBodyChanged: (_) {},
  onDraftChanged: drafts.add,
  onNodeDraftChanged: (_) {},
  onKnowledgeAction: onKnowledgeAction,
);
Widget _editorApp(MindmapNode node, Object draft) =>
    _app(buildKnowledgeNodeInlineEditor(_editContext(node, draft, <Object>[])));
Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(colorSchemeSeed: const Color(0xFFD946EF)),
    home: Scaffold(body: Center(child: child)),
  ),
);
MindmapNode _node(NodeType type) {
  final now = DateTime(2026, 7, 13, 9);
  return MindmapNode.create(
    id: '${type.name}-node',
    type: type,
    title: '${type.label} title',
    body: 'Primary knowledge content with enough detail for a useful preview.',
    day: now,
    now: now,
    data: const {
      'journal': {'prompt': 'What changed today?'},
      'link': {'url': 'https://example.com/link'},
      'url': 'https://example.com/bookmark',
      'source': 'Research paper',
      'options': ['Option A', 'Option B'],
      'author': 'Ada Lovelace',
      'audioPath': '/voice-notes/memo.mp3',
      'audioDuration': '01:20',
      'audioTranscript': 'Voice memo transcript',
      'strokes': ['stroke-1'],
      'background': 'grid',
    },
  );
}
