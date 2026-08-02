import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../../../core/constants/app_constants.dart';
import 'canvas_position.dart';
import 'hybrid_timer.dart';
import 'kanban_board.dart';
import 'mindmap_node.dart';
import 'node_presentation.dart';
import 'node_type_payloads.dart';

final class InlineNodeWorkspaceSize {
  const InlineNodeWorkspaceSize(this.width, this.height);

  final double width;
  final double height;

  @override
  bool operator ==(Object other) {
    return other is InlineNodeWorkspaceSize &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);
}

abstract final class InlineNodeWorkspacePolicy {
  static const InlineNodeWorkspaceSize small = InlineNodeWorkspaceSize(
    280,
    180,
  );
  static const InlineNodeWorkspaceSize standard = InlineNodeWorkspaceSize(
    360,
    280,
  );
  static const InlineNodeWorkspaceSize large = InlineNodeWorkspaceSize(
    440,
    360,
  );
  static const InlineNodeWorkspaceSize wide = InlineNodeWorkspaceSize(560, 380);
  static const InlineNodeWorkspaceSize task = InlineNodeWorkspaceSize(620, 720);
  static const InlineNodeWorkspaceSize habit = InlineNodeWorkspaceSize(
    1040,
    560,
  );
  static const InlineNodeWorkspaceSize routine = InlineNodeWorkspaceSize(
    760,
    560,
  );
  static const InlineNodeWorkspaceSize goal = InlineNodeWorkspaceSize(760, 620);
  static const InlineNodeWorkspaceSize event = InlineNodeWorkspaceSize(
    680,
    540,
  );
  static const InlineNodeWorkspaceSize mood = InlineNodeWorkspaceSize(520, 500);
  static const InlineNodeWorkspaceSize weather = InlineNodeWorkspaceSize(
    680,
    1040,
  );
  static const InlineNodeWorkspaceSize fit = InlineNodeWorkspaceSize(760, 1120);
  static const InlineNodeWorkspaceSize contact = InlineNodeWorkspaceSize(
    680,
    480,
  );
  static const InlineNodeWorkspaceSize metric = InlineNodeWorkspaceSize(
    600,
    600,
  );
  static const InlineNodeWorkspaceSize expense = InlineNodeWorkspaceSize(
    760,
    600,
  );
  static const InlineNodeWorkspaceSize resource = InlineNodeWorkspaceSize(
    760,
    780,
  );
  static const InlineNodeWorkspaceSize bookmark = InlineNodeWorkspaceSize(
    680,
    840,
  );
  static const InlineNodeWorkspaceSize quote = InlineNodeWorkspaceSize(
    820,
    820,
  );
  static const InlineNodeWorkspaceSize audio = InlineNodeWorkspaceSize(
    680,
    760,
  );
  static const InlineNodeWorkspaceSize image = InlineNodeWorkspaceSize(
    900,
    820,
  );
  static const InlineNodeWorkspaceSize video = InlineNodeWorkspaceSize(
    900,
    820,
  );
  static const InlineNodeWorkspaceSize itinerary = InlineNodeWorkspaceSize(
    820,
    1660,
  );
  static const InlineNodeWorkspaceSize journal = InlineNodeWorkspaceSize(
    720,
    690,
  );
  static const InlineNodeWorkspaceSize canvas = InlineNodeWorkspaceSize(
    960,
    920,
  );

  static InlineNodeWorkspaceSize expandedSizeFor(NodeType type) =>
      switch (type) {
        NodeType.empty || NodeType.question || NodeType.idea => small,
        NodeType.audio => audio,
        NodeType.resource => resource,
        NodeType.bookmark => bookmark,
        NodeType.quote => quote,
        NodeType.task => task,
        NodeType.image => image,
        NodeType.canvas => canvas,
        NodeType.event => event,
        NodeType.journal => journal,
        NodeType.note || NodeType.decision => standard,
        NodeType.habit => habit,
        NodeType.routine => routine,
        NodeType.goal => goal,
        NodeType.contact => contact,
        NodeType.metric => metric,
        NodeType.expense => expense,
        NodeType.plan => large,
        NodeType.itinerary => itinerary,
        NodeType.video => video,
        NodeType.kanban => wide,
        NodeType.mood => mood,
        NodeType.weather => weather,
        NodeType.fit => fit,
        NodeType.link ||
        NodeType.timer ||
        NodeType.checklist => _clampedExistingDefault(type),
      };

  static InlineNodeWorkspaceSize expandedSizeForNode(MindmapNode node) {
    if (node.type == NodeType.canvas) return canvas;
    if (node.type == NodeType.image) return image;
    if (node.type == NodeType.itinerary) {
      final payload = ItineraryPayload.fromNode(node);
      final insights = ItineraryInsights.fromPayload(payload);
      final validationCount = payload.validate(title: node.title).length;
      var height = itinerary.height + 120;
      height += math.min(3, insights.warnings.length) * 28.0;
      height += math.min(6, validationCount) * 24.0;
      if (payload.bookings.isNotEmpty) {
        height += 280 + (payload.bookings.length - 1) * 390.0;
      }
      if (payload.packing.isNotEmpty) {
        height += 50 + (payload.packing.length - 1) * 110.0;
      }
      if (payload.agenda.isNotEmpty) {
        height += 300 + (payload.agenda.length - 1) * 230.0;
      }
      return InlineNodeWorkspaceSize(itinerary.width, height);
    }
    if (node.type == NodeType.bookmark) {
      final payload = LinkResourcePayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 3, max: 7);
      final descriptionLines = _workspaceTextLines(
        payload.description,
        min: 2,
        max: 4,
      );
      final tagRows = math.max(1, ((payload.tags.length + 1) / 4).ceil());
      return InlineNodeWorkspaceSize(
        bookmark.width,
        680 + (bodyLines + descriptionLines) * 20 + tagRows * 48,
      );
    }
    if (node.type == NodeType.quote) {
      final payload = QuotePayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 3, max: 8);
      final tagRows = math.max(1, ((payload.tags.length + 1) / 4).ceil());
      return InlineNodeWorkspaceSize(
        quote.width,
        500 + bodyLines * 20 + tagRows * 48,
      );
    }
    if (node.type == NodeType.resource) {
      final payload = ResourcePayload.fromNode(node);
      final descriptionLines = _workspaceTextLines(
        payload.description,
        min: 2,
        max: 6,
      );
      final primaryHeight = payload.primaryAsset == null ? 120.0 : 280.0;
      final folderHeight = payload.folderPath.isEmpty ? 56.0 : 88.0;
      final tagHeight = payload.tags.isEmpty ? 56.0 : 96.0;
      final relatedHeight = payload.relatedAssets.length * 84.0;
      return InlineNodeWorkspaceSize(
        resource.width,
        520 +
            primaryHeight +
            folderHeight +
            tagHeight +
            descriptionLines * 20 +
            relatedHeight,
      );
    }
    if (node.type == NodeType.decision) {
      final payload = DecisionPayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 3, max: 7);
      final textLines =
          <String>[
            payload.question,
            payload.context,
            payload.rationale,
            payload.assumptions,
            payload.expectedOutcome,
            payload.reviewNotes,
          ].fold<int>(
            bodyLines,
            (total, value) =>
                total + _workspaceTextLines(value, min: 2, max: 6),
          );
      final criteriaHeight = payload.criteria.length * 76.0;
      var optionsHeight = 0.0;
      for (final option in payload.options) {
        optionsHeight += 230;
        optionsHeight +=
            (option.pros.length + option.cons.length + option.risks.length) *
            52.0;
        optionsHeight += payload.criteria.length * 72.0;
      }
      final statusSuggestionHeight =
          payload.suggestedStatus != payload.status &&
              payload.status != 'reviewing' &&
              payload.status != 'reversed'
          ? 72.0
          : 0.0;
      final outcomeSuggestionHeight =
          payload.recommendedOptionId.isNotEmpty &&
              payload.recommendedOptionId != payload.selectedOptionId
          ? 72.0
          : 0.0;
      return InlineNodeWorkspaceSize(
        720,
        760 +
            textLines * 20 +
            criteriaHeight +
            optionsHeight +
            statusSuggestionHeight +
            outcomeSuggestionHeight,
      );
    }
    if (node.type == NodeType.question) {
      final payload = QuestionPayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 3, max: 7);
      final questionLines = _workspaceTextLines(
        payload.questionText,
        min: 2,
        max: 6,
      );
      final contextLines = _workspaceTextLines(
        payload.questionContext,
        min: 2,
        max: 6,
      );
      final answerLines = _workspaceTextLines(payload.answer, min: 2, max: 6);
      final evidenceLines = _workspaceTextLines(
        payload.evidence,
        min: 2,
        max: 6,
      );
      final nextActionLines = _workspaceTextLines(
        payload.nextResearchAction,
        min: 2,
        max: 6,
      );
      final suggestionHeight =
          payload.suggestedInvestigationStatus != payload.investigationStatus &&
              payload.investigationStatus != 'blocked'
          ? 72.0
          : 0.0;
      final listHeight =
          (payload.possibleAnswers.length + payload.questionSources.length) *
          88.0;
      return InlineNodeWorkspaceSize(
        680,
        760 +
            (bodyLines +
                    questionLines +
                    contextLines +
                    answerLines +
                    evidenceLines +
                    nextActionLines) *
                20 +
            listHeight +
            suggestionHeight,
      );
    }
    if (node.type == NodeType.idea) {
      final payload = IdeaPayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 3, max: 7);
      final hypothesisLines = _workspaceTextLines(
        payload.hypothesis,
        min: 2,
        max: 6,
      );
      final evidenceLines = _workspaceTextLines(
        payload.evidence,
        min: 2,
        max: 6,
      );
      final experimentLines = _workspaceTextLines(
        payload.nextAction,
        min: 2,
        max: 6,
      );
      final suggestionHeight =
          payload.suggestedMaturity != payload.maturity &&
              payload.maturity != 'archived'
          ? 72.0
          : 0.0;
      return InlineNodeWorkspaceSize(
        640,
        720 +
            (bodyLines + hypothesisLines + evidenceLines + experimentLines) *
                20 +
            suggestionHeight,
      );
    }
    if (node.type == NodeType.journal) {
      final payload = JournalPayload.fromNode(node);
      final bodyLines = _workspaceTextLines(node.body, min: 2, max: 6);
      final promptLines = _workspaceTextLines(payload.prompt, min: 1, max: 3);
      final highlightLines = _workspaceTextLines(
        payload.dailyHighlight,
        min: 1,
        max: 2,
      );
      final gratitudeLines = _workspaceTextLines(
        payload.gratitude.join('\n'),
        min: 1,
        max: 4,
      );
      return InlineNodeWorkspaceSize(
        720,
        560 + (bodyLines + promptLines + highlightLines + gratitudeLines) * 20,
      );
    }
    if (node.type == NodeType.note) {
      return const InlineNodeWorkspaceSize(780, 720);
    }
    if (node.type == NodeType.audio) {
      final payload = AudioPayload.fromNode(node);
      final transcriptLines = _workspaceTextLines(
        payload.transcriptText.isNotEmpty
            ? payload.transcriptText
            : payload.audioTranscript,
        min: 3,
        max: 8,
      );
      final segmentHeight =
          math.min(8, payload.transcriptSegments.length) * 56.0;
      return InlineNodeWorkspaceSize(
        audio.width,
        610 + transcriptLines * 20 + segmentHeight,
      );
    }
    if (node.type == NodeType.task) {
      final taskData = node.data['task'];
      final attachments = taskData is Map ? taskData['attachments'] : null;
      final attachmentCount = attachments is List ? attachments.length : 0;
      final extraSubtaskHeight = node.checklist.length * 44.0;
      final extraAttachmentHeight = attachmentCount * 56.0;
      return InlineNodeWorkspaceSize(
        task.width,
        task.height + extraSubtaskHeight + extraAttachmentHeight,
      );
    }
    if (node.type == NodeType.plan) {
      final project = PlanPayload.fromNode(node).project;
      var height = 380.0;
      for (final phase in project.phases) {
        height += 88;
        for (final milestone in phase.milestones) {
          height += 82;
          for (final task in milestone.tasks) {
            height += 104;
            if (task.description.isNotEmpty) height += 42;
            if (task.labels.isNotEmpty) height += 30;
            if (task.dependencyTaskIds.isNotEmpty) height += 34;
            if (task.blockingReason.isNotEmpty) height += 42;
            height += task.checklist.length * 30;
            height += task.attachments.length * 48;
          }
        }
      }
      return InlineNodeWorkspaceSize(720, math.max(560, height));
    }
    if (node.type == NodeType.checklist) {
      final payload = ChecklistPayload.fromNode(node);
      return InlineNodeWorkspaceSize(640, 520 + payload.items.length * 72.0);
    }
    if (node.type == NodeType.timer) {
      final timer = TimerPayload.fromNode(node).timer;
      var height = switch (timer.mode) {
        TimerMode.focus => 860.0,
        TimerMode.countdown => 790.0,
        TimerMode.stopwatch => 800.0,
      };
      height += timer.distractions.length * 48;
      if (timer.mode == TimerMode.stopwatch) {
        height += timer.laps.length * 48;
      }
      height += math.min(5, timer.history.length) * 56;
      return InlineNodeWorkspaceSize(640, height);
    }
    if (node.type == NodeType.kanban) {
      final board = KanbanBoard.fromNodeData(node.data);
      final columnCount = board.columns.length.clamp(1, maxKanbanColumns);
      var tallestColumnHeight = 112.0;
      for (final column in board.columns) {
        var columnHeight = 78.0;
        for (final card in board.cardsFor(column.id)) {
          columnHeight += 82;
          if (card.description.trim().isNotEmpty) columnHeight += 42;
          if (card.labels.isNotEmpty) columnHeight += 30;
          if (card.priority != KanbanPriority.none || card.dueDate != null) {
            columnHeight += 28;
          }
          if (card.checklist.isNotEmpty) {
            columnHeight += 28 + card.checklist.length * 30;
          }
          if (card.attachments.isNotEmpty) {
            columnHeight += 28 + card.attachments.length * 32;
          }
        }
        if (columnHeight > tallestColumnHeight) {
          tallestColumnHeight = columnHeight;
        }
      }
      return InlineNodeWorkspaceSize(
        math.max(620, columnCount * 270 + 58),
        math.max(560, 286 + tallestColumnHeight),
      );
    }
    return expandedSizeFor(node.type);
  }

  static int _workspaceTextLines(
    String value, {
    required int min,
    required int max,
  }) {
    if (value.trim().isEmpty) return min;
    var lines = 0;
    for (final line in value.split('\n')) {
      lines += math.max(1, (line.length / 72).ceil());
    }
    return lines.clamp(min, max);
  }

  static InlineNodeWorkspaceSize _clampedExistingDefault(NodeType type) {
    final NodePresentationState existing = NodePresentationSpec.forType(
      type,
    ).resolve();
    return InlineNodeWorkspaceSize(
      math.max(existing.width, standard.width),
      math.max(existing.height, standard.height),
    );
  }
}

final class InlineNodeDraftPatch {
  InlineNodeDraftPatch({
    this.type,
    this.title,
    this.body,
    this.day,
    this.position,
    this.isDone,
    this.status,
    this.priority,
    this.effort,
    this.reviewState,
    this.project,
    this.area,
    List<String>? tags,
    List<String>? contextTags,
    this.dueDate,
    this.dueDateChanged = false,
    this.progress,
    this.isPinned,
    this.isArchived,
    List<TaskChecklistItem>? checklist,
    List<String>? relatedNodeIds,
    Map<String, Object?> dataFields = const <String, Object?>{},
    Set<String> removedDataFields = const <String>{},
  }) : tags = tags == null ? null : List<String>.unmodifiable(tags),
       contextTags = contextTags == null
           ? null
           : List<String>.unmodifiable(contextTags),
       checklist = checklist == null
           ? null
           : List<TaskChecklistItem>.unmodifiable(checklist),
       relatedNodeIds = relatedNodeIds == null
           ? null
           : List<String>.unmodifiable(relatedNodeIds),
       dataFields = _freezeDataFields(dataFields),
       removedDataFields = Set<String>.unmodifiable(removedDataFields);

  factory InlineNodeDraftPatch.between(MindmapNode base, MindmapNode draft) {
    const DeepCollectionEquality equality = DeepCollectionEquality();
    final Map<String, Object?> changedData = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in draft.data.entries) {
      if (!equality.equals(base.data[entry.key], entry.value)) {
        changedData[entry.key] = entry.value;
      }
    }
    final Set<String> removedData = base.data.keys
        .where((String key) => !draft.data.containsKey(key))
        .toSet();

    return InlineNodeDraftPatch(
      type: base.type == draft.type ? null : draft.type,
      title: base.title == draft.title ? null : draft.title,
      body: base.body == draft.body ? null : draft.body,
      day: base.day == draft.day ? null : draft.day,
      position: base.position == draft.position ? null : draft.position,
      isDone: base.isDone == draft.isDone ? null : draft.isDone,
      status: base.status == draft.status ? null : draft.status,
      priority: base.priority == draft.priority ? null : draft.priority,
      effort: base.effort == draft.effort ? null : draft.effort,
      reviewState: base.reviewState == draft.reviewState
          ? null
          : draft.reviewState,
      project: base.project == draft.project ? null : draft.project,
      area: base.area == draft.area ? null : draft.area,
      tags: equality.equals(base.tags, draft.tags) ? null : draft.tags,
      contextTags: equality.equals(base.contextTags, draft.contextTags)
          ? null
          : draft.contextTags,
      dueDate: draft.dueDate,
      dueDateChanged: base.dueDate != draft.dueDate,
      progress: base.progress == draft.progress ? null : draft.progress,
      isPinned: base.isPinned == draft.isPinned ? null : draft.isPinned,
      isArchived: base.isArchived == draft.isArchived ? null : draft.isArchived,
      checklist: equality.equals(base.checklist, draft.checklist)
          ? null
          : draft.checklist,
      relatedNodeIds: equality.equals(base.relatedNodeIds, draft.relatedNodeIds)
          ? null
          : draft.relatedNodeIds,
      dataFields: changedData,
      removedDataFields: removedData,
    );
  }

  final NodeType? type;
  final String? title;
  final String? body;
  final DateTime? day;
  final CanvasPosition? position;
  final bool? isDone;
  final NodeStatus? status;
  final NodePriority? priority;
  final NodeEffort? effort;
  final NodeReviewState? reviewState;
  final String? project;
  final String? area;
  final List<String>? tags;
  final List<String>? contextTags;
  final DateTime? dueDate;
  final bool dueDateChanged;
  final double? progress;
  final bool? isPinned;
  final bool? isArchived;
  final List<TaskChecklistItem>? checklist;
  final List<String>? relatedNodeIds;
  final Map<String, Object?> dataFields;
  final Set<String> removedDataFields;

  MindmapNode mergeInto(MindmapNode latest, DateTime now) {
    final Map<String, Object?> data = <String, Object?>{
      ...latest.data,
      ...dataFields,
    };
    for (final String key in removedDataFields) {
      data.remove(key);
    }
    return latest.copyWith(
      type: type,
      title: title,
      body: body,
      day: day,
      position: position,
      isDone: isDone,
      status: status,
      priority: priority,
      effort: effort,
      reviewState: reviewState,
      project: project,
      area: area,
      tags: tags,
      contextTags: contextTags,
      dueDate: dueDateChanged ? dueDate : null,
      clearDueDate: dueDateChanged && dueDate == null,
      progress: progress,
      isPinned: isPinned,
      isArchived: isArchived,
      checklist: checklist,
      relatedNodeIds: relatedNodeIds,
      data: data,
      updatedAt: now,
    );
  }
}

Map<String, Object?> _freezeDataFields(Map<String, Object?> source) {
  return UnmodifiableMapView<String, Object?>(<String, Object?>{
    for (final MapEntry<String, Object?> entry in source.entries)
      entry.key: _freezeDataFieldValue(entry.value),
  });
}

Object? _freezeDataFieldValue(Object? value) {
  if (value is Map) {
    if (value.keys.every((Object? key) => key is String)) {
      return UnmodifiableMapView<String, Object?>(<String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          entry.key! as String: _freezeDataFieldValue(entry.value),
      });
    }
    return UnmodifiableMapView<Object?, Object?>(<Object?, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        entry.key: _freezeDataFieldValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map<Object?>(_freezeDataFieldValue),
    );
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map<Object?>(_freezeDataFieldValue));
  }
  return value;
}
