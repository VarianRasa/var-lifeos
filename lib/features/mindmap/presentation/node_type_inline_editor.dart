import 'package:flutter/widgets.dart';

import '../../../core/constants/app_constants.dart';

import '../domain/mindmap_node.dart';
import '../domain/node_type_payloads.dart';
import 'node_editors/media_travel_node_editors.dart';
import 'node_editors/productivity_node_editors.dart';

export 'node_editors/productivity_node_editors.dart'
    show
        NodeActionErrorCallback,
        NodeAsyncDraftAction,
        NodeAsyncPayloadAction,
        NodeEditContext;

Widget buildNodeTypeInlineEditor(NodeEditContext context) =>
    buildMediaTravelNodeInlineEditor(context);

Object nodeTypeInlineDraftFor(MindmapNode node) => switch (node.type) {
  NodeType.task => TaskChecklistPayload.fromNode(node),
  NodeType.checklist => ChecklistPayload.fromNode(node),
  NodeType.kanban => KanbanPayload.fromNode(node),
  NodeType.plan => PlanPayload.fromNode(node),
  NodeType.note => NotePayload.fromNode(node),
  NodeType.empty => const <String, Object?>{},
  NodeType.journal => JournalPayload.fromNode(node),
  NodeType.habit || NodeType.routine => HabitRoutinePayload.fromNode(node),
  NodeType.goal => GoalPayload.fromNode(node),
  NodeType.link || NodeType.bookmark => LinkResourcePayload.fromNode(node),
  NodeType.resource => ResourcePayload.fromNode(node),
  NodeType.event => EventCalendarPayload.fromNode(node),
  NodeType.decision => DecisionPayload.fromNode(node),
  NodeType.idea => IdeaPayload.fromNode(node),
  NodeType.question => QuestionPayload.fromNode(node),
  NodeType.contact => ContactPayload.fromNode(node),
  NodeType.metric => MetricPayload.fromNode(node),
  NodeType.expense => ExpensePayload.fromNode(node),
  NodeType.mood => MoodPayload.fromNode(node),
  NodeType.timer => TimerPayload.fromNode(node),
  NodeType.quote => QuotePayload.fromNode(node),
  NodeType.audio => AudioPayload.fromNode(node),
  NodeType.canvas => CanvasPayload.fromNode(node),
  NodeType.weather => WeatherPayload.fromNode(node),
  NodeType.fit => FitPayload.fromNode(node),
  NodeType.itinerary => ItineraryPayload.fromNode(node),
  NodeType.image => ImagePayload.fromNode(node),
  NodeType.video => VideoPayload.fromNode(node),
};

MindmapNode applyNodeTypeInlineDraft(MindmapNode node, Object draft) {
  final Map<String, Object?> data = switch ((node.type, draft)) {
    (NodeType.task, final TaskChecklistPayload value) =>
      value.toNode(node).data,
    (NodeType.checklist, final ChecklistPayload value) =>
      value.toNode(node).data,
    (NodeType.kanban, final KanbanPayload value) => value.toData(node.data),
    (NodeType.plan, final PlanPayload value) => value.toData(node.data),
    (NodeType.note, final NotePayload value) => value.toData(node.data),
    (NodeType.goal, final GoalPayload value) => value.toData(node.data),
    (NodeType.habit || NodeType.routine, final HabitRoutinePayload value) =>
      value.toData(node.data),
    (NodeType.journal, final JournalPayload value) => value.toData(node.data),
    (NodeType.idea, final IdeaPayload value) => value.toData(node.data),
    (NodeType.question, final QuestionPayload value) => value.toData(node.data),
    (NodeType.decision, final DecisionPayload value) => value.toData(node.data),
    (NodeType.quote, final QuotePayload value) => value.toData(node.data),
    (NodeType.event, final EventCalendarPayload value) => value.toData(
      node.data,
    ),
    (NodeType.contact, final ContactPayload value) => value.toData(node.data),
    (NodeType.metric, final MetricPayload value) => value.toData(node.data),
    (NodeType.expense, final ExpensePayload value) => value.toData(node.data),
    (NodeType.mood, final MoodPayload value) => value.toData(node.data),
    (NodeType.weather, final WeatherPayload value) => value.toData(node.data),
    (NodeType.fit, final FitPayload value) => value.toData(node.data),
    (NodeType.link || NodeType.bookmark, final LinkResourcePayload value) =>
      value.toData(node.data),
    (NodeType.resource, final ResourcePayload value) => value.toData(node.data),
    (NodeType.timer, final TimerPayload value) => value.toData(node.data),
    (NodeType.audio, final AudioPayload value) => value.toData(node.data),
    (NodeType.canvas, final CanvasPayload value) => value.toData(node.data),
    (NodeType.image, final ImagePayload value) => value.toData(node.data),
    (NodeType.video, final VideoPayload value) => value.toData(node.data),
    (NodeType.itinerary, final ItineraryPayload value) => value.toData(
      node.data,
    ),
    (NodeType.empty, final Map<String, Object?> value) => <String, Object?>{
      ...node.data,
      ...value,
    },
    _ => throw ArgumentError.value(
      draft,
      'draft',
      'Unsupported ${draft.runtimeType} draft for ${node.type.name}',
    ),
  };
  if (node.type == NodeType.task && draft is TaskChecklistPayload) {
    return draft.toNode(node);
  }
  if (node.type == NodeType.checklist && draft is ChecklistPayload) {
    return draft.toNode(node);
  }
  if (node.type == NodeType.resource && draft is ResourcePayload) {
    return draft.toNode(node);
  }
  return node.copyWith(data: data);
}
