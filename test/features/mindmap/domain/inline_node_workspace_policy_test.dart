import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/constants/app_constants.dart';
import 'package:var_app/features/mindmap/domain/canvas_position.dart';
import 'package:var_app/features/mindmap/domain/hybrid_timer.dart';
import 'package:var_app/features/mindmap/domain/inline_node_workspace_policy.dart';
import 'package:var_app/features/mindmap/domain/kanban_board.dart';
import 'package:var_app/features/mindmap/domain/mindmap_node.dart';
import 'package:var_app/features/mindmap/domain/node_presentation.dart';
import 'package:var_app/features/mindmap/domain/node_type_payloads.dart';

void main() {
  test('expanded size policy covers every NodeType', () {
    for (final NodeType type in NodeType.values) {
      final InlineNodeWorkspaceSize size =
          InlineNodeWorkspacePolicy.expandedSizeFor(type);
      expect(size.width, greaterThanOrEqualTo(280), reason: type.name);
      expect(size.height, greaterThanOrEqualTo(180), reason: type.name);
    }
  });

  test('habit workspace fits full editor and heatmap', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.habit),
      const InlineNodeWorkspaceSize(1040, 560),
    );
  });

  test('mood workspace fits full editor without scroll', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.mood),
      const InlineNodeWorkspaceSize(520, 500),
    );
  });

  test('weather workspace fits enhanced editor', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.weather),
      const InlineNodeWorkspaceSize(680, 1040),
    );
  });

  test('fitness workspace supports full tracker', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.fit),
      const InlineNodeWorkspaceSize(760, 1120),
    );
  });

  test('event workspace fits full editor without scroll', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.event),
      const InlineNodeWorkspaceSize(680, 540),
    );
  });

  test('goal workspace fits full editor without scroll', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.goal),
      const InlineNodeWorkspaceSize(760, 620),
    );
  });

  test('routine workspace fits full editor without scroll', () {
    expect(
      InlineNodeWorkspacePolicy.expandedSizeFor(NodeType.routine),
      const InlineNodeWorkspaceSize(760, 560),
    );
  });

  test('design families resolve exact expanded sizes', () {
    const Map<NodeType, InlineNodeWorkspaceSize> expected =
        <NodeType, InlineNodeWorkspaceSize>{
          NodeType.empty: InlineNodeWorkspaceSize(280, 180),
          NodeType.bookmark: InlineNodeWorkspaceSize(680, 840),
          NodeType.resource: InlineNodeWorkspaceSize(760, 780),
          NodeType.question: InlineNodeWorkspaceSize(280, 180),
          NodeType.idea: InlineNodeWorkspaceSize(280, 180),
          NodeType.canvas: InlineNodeWorkspaceSize(960, 920),
          NodeType.task: InlineNodeWorkspaceSize(620, 720),
          NodeType.note: InlineNodeWorkspaceSize(360, 280),
          NodeType.journal: InlineNodeWorkspaceSize(720, 690),
          NodeType.event: InlineNodeWorkspaceSize(680, 540),
          NodeType.decision: InlineNodeWorkspaceSize(360, 280),
          NodeType.plan: InlineNodeWorkspaceSize(440, 360),
          NodeType.goal: InlineNodeWorkspaceSize(760, 620),
          NodeType.habit: InlineNodeWorkspaceSize(1040, 560),
          NodeType.metric: InlineNodeWorkspaceSize(600, 600),
          NodeType.expense: InlineNodeWorkspaceSize(760, 600),
          NodeType.contact: InlineNodeWorkspaceSize(680, 480),
          NodeType.kanban: InlineNodeWorkspaceSize(560, 380),
          NodeType.itinerary: InlineNodeWorkspaceSize(820, 1660),
          NodeType.image: InlineNodeWorkspaceSize(900, 820),
          NodeType.video: InlineNodeWorkspaceSize(900, 820),
        };
    for (final MapEntry<NodeType, InlineNodeWorkspaceSize> entry
        in expected.entries) {
      expect(
        InlineNodeWorkspacePolicy.expandedSizeFor(entry.key),
        entry.value,
        reason: entry.key.name,
      );
    }
  });

  test('bookmark expanded size follows editor content', () {
    final day = DateTime(2026, 7, 17);
    final base = MindmapNode.create(
      id: 'bookmark-size',
      type: NodeType.bookmark,
      title: 'Bookmark',
      body: 'Saved reference',
      day: day,
      now: day,
    );
    final detailed = const LinkResourcePayload(
      type: NodeType.bookmark,
      url: 'https://example.com/reference',
      description: 'Useful architecture reference with context.',
      tags: <String>['flutter', 'architecture', 'design', 'reference'],
    ).toNode(base);

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, InlineNodeWorkspacePolicy.bookmark.width);
    expect(detailedSize.width, compactSize.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
    expect(compactSize.height, greaterThanOrEqualTo(800));
  });

  test('resource expanded size follows structured content', () {
    final day = DateTime(2026, 7, 17);
    final compact = MindmapNode.create(
      id: 'resource-compact',
      type: NodeType.resource,
      title: 'Resource',
      day: day,
      now: day,
    );
    final detailed = compact.copyWith(
      data: const ResourcePayload(
        primaryAsset: ResourceAsset(
          id: 'primary',
          kind: 'file',
          attachmentId: 'attachment-1',
          fileName: 'manual.pdf',
          extension: 'pdf',
        ),
        relatedAssets: <ResourceAsset>[
          ResourceAsset(id: '1', kind: 'url', location: 'https://a.test'),
          ResourceAsset(id: '2', kind: 'url', location: 'https://b.test'),
          ResourceAsset(id: '3', kind: 'url', location: 'https://c.test'),
          ResourceAsset(id: '4', kind: 'url', location: 'https://d.test'),
          ResourceAsset(id: '5', kind: 'url', location: 'https://e.test'),
          ResourceAsset(id: '6', kind: 'url', location: 'https://f.test'),
        ],
        folderPath: <String>['Research', 'Flutter', 'Rendering'],
        description:
            'Long description that keeps enough content for deterministic sizing.',
        tags: <String>['flutter', 'rendering', 'reference'],
      ).toData(compact.data),
    );

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(compact);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, InlineNodeWorkspacePolicy.resource.width);
    expect(detailedSize.width, InlineNodeWorkspacePolicy.resource.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(detailed),
      detailedSize,
    );
  });

  test('itinerary expanded size grows with advanced trip content', () {
    final day = DateTime(2026, 7, 20);
    final base = MindmapNode.create(
      id: 'itinerary-size',
      type: NodeType.itinerary,
      title: 'Trip',
      day: day,
      now: day,
      data: ItineraryPayload(
        destination: 'Bandung',
        startDate: day,
        endDate: day.add(const Duration(days: 2)),
        timezone: 'Asia/Jakarta',
      ).toData(),
    );
    final detailed = base.copyWith(
      data: ItineraryPayload(
        destination: 'Bandung',
        startDate: day,
        endDate: day.add(const Duration(days: 2)),
        timezone: 'Asia/Jakarta',
        bookings: [
          ItineraryBooking(
            id: 'hotel',
            title: 'Hotel',
            type: 'hotel',
            startAt: day,
            endAt: day.add(const Duration(days: 2)),
          ),
        ],
        packing: const [ItineraryPackingItem(id: 'bag', title: 'Bag')],
        agenda: const [
          ItineraryAgendaItem(
            id: 'first',
            title: 'First stop',
            startMinutes: 540,
            durationMinutes: 60,
          ),
          ItineraryAgendaItem(
            id: 'second',
            title: 'Second stop',
            startMinutes: 660,
            durationMinutes: 60,
          ),
        ],
      ).toData(base.data),
    );

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, InlineNodeWorkspacePolicy.itinerary.width);
    expect(detailedSize.width, compactSize.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(detailed),
      detailedSize,
    );
  });

  test('canvas expanded size stays fixed across document complexity', () {
    final base = MindmapNode.create(
      id: 'canvas-fixed',
      type: NodeType.canvas,
      title: 'Canvas',
      day: DateTime(2026, 7, 17),
    );
    final detailed = base.copyWith(
      data: const CanvasPayload(
        elements: <CanvasElement>[
          CanvasStroke(
            id: 'stroke',
            color: 'blue',
            points: <CanvasPoint>[CanvasPoint(0.1, 0.1), CanvasPoint(0.9, 0.9)],
          ),
        ],
      ).toData(base.data),
    );

    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(base),
      InlineNodeWorkspacePolicy.canvas,
    );
    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(detailed),
      InlineNodeWorkspacePolicy.canvas,
    );
  });

  test('task expanded size grows with workspace content', () {
    final node = MindmapNode.create(
      id: 'task-grow',
      type: NodeType.task,
      title: 'Task',
      day: DateTime(2026, 7, 16),
      checklist: const <TaskChecklistItem>[
        TaskChecklistItem(id: '1', title: 'One'),
        TaskChecklistItem(id: '2', title: 'Two'),
        TaskChecklistItem(id: '3', title: 'Three'),
      ],
      data: const <String, Object?>{
        'task': <String, Object?>{
          'assignees': <String>['A', 'B', 'C', 'D'],
          'attachments': <Map<String, Object?>>[
            <String, Object?>{'id': 'attachment-1'},
          ],
        },
      },
    );

    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);

    expect(size.width, InlineNodeWorkspacePolicy.task.width);
    expect(size.height, greaterThan(InlineNodeWorkspacePolicy.task.height));
  });

  test('idea expanded size follows structured editor content', () {
    final base = MindmapNode.create(
      id: 'idea-grow',
      type: NodeType.idea,
      title: 'Idea',
      day: DateTime(2026, 7, 16),
    );
    final detailed = base.copyWith(
      body: 'Supporting context ' * 30,
      data: IdeaPayload(
        maturity: 'spark',
        hypothesis: 'A long hypothesis ' * 20,
        impact: 'high',
        effort: 'medium',
        confidence: 70,
        evidence: 'Interview evidence ' * 20,
        nextAction: 'Build a prototype ' * 20,
      ).toData(base.data),
    );

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, 640);
    expect(compactSize.height, greaterThanOrEqualTo(880));
    expect(detailedSize.width, compactSize.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
  });

  test('decision expanded size follows matrix content', () {
    final base = MindmapNode.create(
      id: 'decision-grow',
      type: NodeType.decision,
      title: 'Decision',
      day: DateTime(2026, 7, 16),
    );
    final detailed = base.copyWith(
      body: 'Supporting context ' * 30,
      data: const DecisionPayload(
        question: 'Which option should ship?',
        criteria: <DecisionCriterion>[
          DecisionCriterion(id: 'impact', name: 'Impact', weight: 2),
          DecisionCriterion(id: 'effort', name: 'Effort'),
        ],
        options: <DecisionOption>[
          DecisionOption(
            id: 'a',
            title: 'Option A',
            pros: <String>['Fast', 'Valuable'],
            cons: <String>['Cost'],
            scores: <String, int>{'impact': 9, 'effort': 6},
          ),
          DecisionOption(
            id: 'b',
            title: 'Option B',
            risks: <String>['Migration'],
            scores: <String, int>{'impact': 7, 'effort': 8},
          ),
        ],
      ).toData(base.data),
    );

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, 720);
    expect(detailedSize.width, compactSize.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
  });

  test('question expanded size follows structured editor content', () {
    final base = MindmapNode.create(
      id: 'question-grow',
      type: NodeType.question,
      title: 'Question',
      day: DateTime(2026, 7, 16),
    );
    final detailed = base.copyWith(
      body: 'Supporting context ' * 30,
      data: QuestionPayload(
        investigationStatus: 'open',
        questionText: 'A long research question ' * 20,
        questionContext: 'Decision context ' * 20,
        possibleAnswers: const <String>['Option A', 'Option B'],
        answer: 'Accepted answer ' * 20,
        evidence: 'Research evidence ' * 20,
        questionSources: const <String>['Paper A', 'Paper B'],
        nextResearchAction: 'Run another study ' * 20,
        questionConfidence: 75,
      ).toData(base.data),
    );

    final compactSize = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final detailedSize = InlineNodeWorkspacePolicy.expandedSizeForNode(
      detailed,
    );

    expect(compactSize.width, 680);
    expect(compactSize.height, greaterThanOrEqualTo(1000));
    expect(detailedSize.width, compactSize.width);
    expect(detailedSize.height, greaterThan(compactSize.height));
  });

  test('checklist expanded size grows with item count', () {
    final base = MindmapNode.create(
      id: 'checklist-grow',
      type: NodeType.checklist,
      title: 'Checklist',
      day: DateTime(2026, 7, 16),
    );
    final short = InlineNodeWorkspacePolicy.expandedSizeForNode(base);
    final tall = InlineNodeWorkspacePolicy.expandedSizeForNode(
      const ChecklistPayload(
        items: <ChecklistEntry>[
          ChecklistEntry(id: '1', title: 'One'),
          ChecklistEntry(id: '2', title: 'Two'),
          ChecklistEntry(id: '3', title: 'Three'),
        ],
      ).toNode(base),
    );

    expect(tall.width, short.width);
    expect(tall.height, short.height + 216);
  });
  test('timer expanded size grows with session content', () {
    final base = MindmapNode.create(
      id: 'timer-grow',
      type: NodeType.timer,
      title: 'Focus',
      day: DateTime(2026, 7, 16),
    );
    final timer = HybridTimerState(
      mode: TimerMode.stopwatch,
      laps: <TimerLap>[
        TimerLap(
          id: 'lap',
          elapsedSeconds: 60,
          createdAt: DateTime(2026, 7, 16, 9),
        ),
      ],
      distractions: <TimerDistraction>[
        TimerDistraction(
          id: 'distraction',
          text: 'Phone',
          createdAt: DateTime(2026, 7, 16, 9),
        ),
      ],
    );
    final node = base.copyWith(
      data: TimerPayload(timer: timer).toData(base.data),
    );

    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);

    expect(size.width, greaterThanOrEqualTo(620));
    expect(size.height, greaterThan(650));
  });

  test('kanban expanded size follows columns and rich card content', () {
    final node = MindmapNode.create(
      id: 'kanban-grow',
      type: NodeType.kanban,
      title: 'Roadmap',
      day: DateTime(2026, 7, 16),
      data: <String, Object?>{
        'kanban': KanbanBoard(
          columns: const <KanbanColumnDefinition>[
            KanbanColumnDefinition(id: 'ideas', title: 'Ideas', order: 0),
            KanbanColumnDefinition(id: 'ready', title: 'Ready', order: 1),
            KanbanColumnDefinition(id: 'doing', title: 'Doing', order: 2),
            KanbanColumnDefinition(
              id: 'done',
              title: 'Done',
              order: 3,
              isDoneColumn: true,
            ),
          ],
          cards: <KanbanCard>[
            KanbanCard(
              id: 'rich',
              title: 'Rich card',
              customColumnId: 'ideas',
              description: 'Detailed card context for dynamic height.',
              priority: KanbanPriority.high,
              dueDate: DateTime(2026, 7, 20),
              labels: const <String>['design', 'release'],
              checklist: const <KanbanChecklistItem>[
                KanbanChecklistItem(id: 'review', title: 'Review'),
              ],
              attachments: const <KanbanAttachmentReference>[
                KanbanAttachmentReference(
                  id: 'brief',
                  fileName: 'brief.pdf',
                  mimeType: 'application/pdf',
                  byteLength: 42,
                ),
              ],
            ),
          ],
        ).toJson(),
      },
    );

    final size = InlineNodeWorkspacePolicy.expandedSizeForNode(node);

    expect(size.width, greaterThan(InlineNodeWorkspacePolicy.wide.width));
    expect(size.height, greaterThanOrEqualTo(560));
  });
  test('unassigned types use clamped existing defaults', () {
    final Set<NodeType> assigned = <NodeType>{
      NodeType.empty,
      NodeType.bookmark,
      NodeType.resource,
      NodeType.question,
      NodeType.idea,
      NodeType.task,
      NodeType.note,
      NodeType.journal,
      NodeType.event,
      NodeType.decision,
      NodeType.plan,
      NodeType.goal,
      NodeType.habit,
      NodeType.metric,
      NodeType.expense,
      NodeType.contact,
      NodeType.kanban,
      NodeType.itinerary,
      NodeType.image,
      NodeType.video,
      NodeType.canvas,
      NodeType.quote,
      NodeType.audio,
      NodeType.routine,
      NodeType.mood,
      NodeType.weather,
      NodeType.fit,
    };
    for (final NodeType type in NodeType.values.where(
      (NodeType type) => !assigned.contains(type),
    )) {
      final NodePresentationState existing = NodePresentationSpec.forType(
        type,
      ).resolve();
      expect(
        InlineNodeWorkspacePolicy.expandedSizeFor(type),
        InlineNodeWorkspaceSize(
          existing.width.clamp(360, double.infinity),
          existing.height.clamp(280, double.infinity),
        ),
        reason: type.name,
      );
    }
  });

  test('draft patch merges into latest node without losing latest data', () {
    final DateTime now = DateTime(2026, 7, 15, 10, 30);
    final MindmapNode latest = MindmapNode.create(
      id: 'node-1',
      type: NodeType.note,
      title: 'Latest title',
      body: 'Latest body',
      day: DateTime(2026, 7, 15),
      priority: NodePriority.low,
      tags: const <String>['latest'],
      data: const <String, Object?>{
        'attachmentIds': <String>['attachment-1'],
        'unrelated': 'keep',
        'draftOwned': 'old',
      },
      now: DateTime(2026, 7, 15, 9),
    );
    final InlineNodeDraftPatch patch = InlineNodeDraftPatch(
      title: 'Draft title',
      priority: NodePriority.high,
      tags: const <String>['draft'],
      dataFields: const <String, Object?>{'draftOwned': 'new'},
    );
    final MindmapNode merged = patch.mergeInto(latest, now);
    expect(merged.title, 'Draft title');
    expect(merged.body, 'Latest body');
    expect(merged.priority, NodePriority.high);
    expect(merged.tags, <String>['draft']);
    expect(merged.data['draftOwned'], 'new');
    expect(merged.data['unrelated'], 'keep');
    expect(merged.data['attachmentIds'], <String>['attachment-1']);
    expect(merged.updatedAt, now);
  });

  test('draft patch data fields are deeply immutable', () {
    final Map<String, Object?> nestedMap = <String, Object?>{'value': 'first'};
    final List<Object?> nestedList = <Object?>[nestedMap];
    final Set<Object?> nestedSet = <Object?>{'first'};
    final Map<String, Object?> source = <String, Object?>{
      'map': nestedMap,
      'list': nestedList,
      'set': nestedSet,
    };
    final InlineNodeDraftPatch patch = InlineNodeDraftPatch(dataFields: source);

    nestedMap['value'] = 'second';
    nestedList.add('second');
    nestedSet.add('second');

    final Map<String, Object?> frozenMap =
        patch.dataFields['map']! as Map<String, Object?>;
    final List<Object?> frozenList = patch.dataFields['list']! as List<Object?>;
    final Set<Object?> frozenSet = patch.dataFields['set']! as Set<Object?>;
    expect(frozenMap['value'], 'first');
    expect(frozenList, hasLength(1));
    expect(frozenSet, <Object?>{'first'});
    expect(() => frozenMap['extra'] = true, throwsUnsupportedError);
    expect(() => frozenList.add('extra'), throwsUnsupportedError);
    expect(() => frozenSet.add('extra'), throwsUnsupportedError);
    expect(() => patch.dataFields['extra'] = true, throwsUnsupportedError);
  });

  test(
    'draft diff merges every changed editable field into concurrent latest',
    () {
      final DateTime day = DateTime(2026, 7, 15);
      final MindmapNode base = MindmapNode.create(
        id: 'node-all',
        type: NodeType.task,
        title: 'Base',
        body: 'Base body',
        day: day,
        position: const CanvasPosition(1, 2),
        status: NodeStatus.open,
        priority: NodePriority.low,
        effort: NodeEffort.fiveMinutes,
        reviewState: NodeReviewState.none,
        project: 'Base project',
        area: 'Base area',
        tags: const <String>['base'],
        contextTags: const <String>['desk'],
        dueDate: day.add(const Duration(days: 1)),
        progress: 0.1,
        checklist: const <TaskChecklistItem>[
          TaskChecklistItem(id: 'a', title: 'Base item'),
        ],
        relatedNodeIds: const <String>['related-base'],
        data: const <String, Object?>{
          'owned': 'base',
          'removed': true,
          'concurrent': 'base',
        },
      );
      final MindmapNode draft = base.copyWith(
        type: NodeType.checklist,
        title: 'Draft',
        body: 'Draft body',
        day: day.add(const Duration(days: 2)),
        position: const CanvasPosition(3, 4),
        isDone: true,
        status: NodeStatus.doing,
        priority: NodePriority.high,
        effort: NodeEffort.oneHourPlus,
        reviewState: NodeReviewState.needsReview,
        project: 'Draft project',
        area: 'Draft area',
        tags: const <String>['draft'],
        contextTags: const <String>['focus'],
        clearDueDate: true,
        progress: 0.75,
        isPinned: true,
        isArchived: true,
        checklist: const <TaskChecklistItem>[
          TaskChecklistItem(id: 'b', title: 'Draft item', isDone: true),
        ],
        relatedNodeIds: const <String>['related-draft'],
        data: const <String, Object?>{'owned': 'draft', 'concurrent': 'base'},
      );
      final MindmapNode latest = base.copyWith(
        area: 'Concurrent area must be replaced because draft changed area',
        data: const <String, Object?>{
          'owned': 'base',
          'removed': true,
          'concurrent': 'latest',
          'latestOnly': 42,
        },
      );

      final InlineNodeDraftPatch patch = InlineNodeDraftPatch.between(
        base,
        draft,
      );
      final MindmapNode merged = patch.mergeInto(
        latest,
        DateTime(2026, 7, 15, 12),
      );

      expect(merged.type, draft.type);
      expect(merged.title, draft.title);
      expect(merged.body, draft.body);
      expect(merged.day, draft.day);
      expect(merged.position, draft.position);
      expect(merged.isDone, draft.isDone);
      expect(merged.status, draft.status);
      expect(merged.priority, draft.priority);
      expect(merged.effort, draft.effort);
      expect(merged.reviewState, draft.reviewState);
      expect(merged.project, draft.project);
      expect(merged.area, draft.area);
      expect(merged.tags, draft.tags);
      expect(merged.contextTags, draft.contextTags);
      expect(merged.dueDate, isNull);
      expect(merged.progress, draft.progress);
      expect(merged.isPinned, isTrue);
      expect(merged.isArchived, isTrue);
      expect(merged.checklist, draft.checklist);
      expect(merged.relatedNodeIds, draft.relatedNodeIds);
      expect(merged.data['owned'], 'draft');
      expect(merged.data.containsKey('removed'), isFalse);
      expect(merged.data['concurrent'], 'latest');
      expect(merged.data['latestOnly'], 42);
    },
  );

  test('draft diff preserves concurrent fields untouched by draft', () {
    final MindmapNode base = MindmapNode.create(
      id: 'node-concurrent',
      type: NodeType.note,
      title: 'Base',
      day: DateTime(2026, 7, 15),
      project: 'Base project',
    );
    final MindmapNode draft = base.copyWith(title: 'Draft title');
    final MindmapNode latest = base.copyWith(
      project: 'Concurrent project',
      isPinned: true,
    );

    final MindmapNode merged = InlineNodeDraftPatch.between(
      base,
      draft,
    ).mergeInto(latest, DateTime(2026, 7, 15, 12));

    expect(merged.title, 'Draft title');
    expect(merged.project, 'Concurrent project');
    expect(merged.isPinned, isTrue);
  });

  test('note uses wide knowledge workspace size', () {
    final node = MindmapNode.create(
      id: 'note-wide',
      type: NodeType.note,
      title: 'Knowledge note',
      day: DateTime(2026, 7, 16),
    );

    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(node),
      const InlineNodeWorkspaceSize(780, 720),
    );
  });

  test('image editor uses fixed size tall enough for all controls', () {
    final node = MindmapNode.create(
      id: 'image-fixed',
      type: NodeType.image,
      title: 'Image',
      day: DateTime(2026, 7, 18),
      data: const ImagePayload(
        url: 'https://example.test/image.png',
        altText: 'Example image',
      ).toData(),
    );

    expect(
      InlineNodeWorkspacePolicy.expandedSizeForNode(node),
      const InlineNodeWorkspaceSize(900, 820),
    );
  });
}
