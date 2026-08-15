/// Typed compatibility payloads for node-specific data.
library;

import 'dart:convert';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_utils.dart';
import 'canvas_block_document.dart';
import 'hybrid_timer.dart';
import 'kanban_board.dart';
import 'mindmap_node.dart';
import 'node_attachment.dart';
import 'node_validation.dart';
import 'project_plan.dart';

final class TaskAttachmentReference {
  const TaskAttachmentReference({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteLength,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int byteLength;

  factory TaskAttachmentReference.fromMap(Map<String, Object?> map) =>
      TaskAttachmentReference(
        id: map['id'] is String ? map['id'] as String : '',
        fileName: map['fileName'] is String ? map['fileName'] as String : '',
        mimeType: map['mimeType'] is String
            ? map['mimeType'] as String
            : 'application/octet-stream',
        byteLength: map['byteLength'] is num
            ? (map['byteLength'] as num).toInt()
            : 0,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'mimeType': mimeType,
    'byteLength': byteLength,
  };
}

final class TaskChecklistPayload {
  const TaskChecklistPayload({
    this.items = const [],
    this.assignees = const [],
    this.attachments = const [],
  });
  factory TaskChecklistPayload.fromNode(MindmapNode node) =>
      TaskChecklistPayload(
        items: node.checklist.isNotEmpty
            ? node.checklist
            : [
                for (final item in _maps(node.data['checklist']))
                  if (item['title'] is String &&
                      (item['title'] as String).trim().isNotEmpty)
                    TaskChecklistItem(
                      id: item['id'] is String ? item['id'] as String : '',
                      title: item['title'] as String,
                      isDone: item['isDone'] is bool
                          ? item['isDone'] as bool
                          : false,
                    ),
              ],
        assignees: _strings(_section(node.data, 'task')['assignees']),
        attachments: [
          for (final item in _maps(_section(node.data, 'task')['attachments']))
            if (item['id'] is String &&
                (item['id'] as String).trim().isNotEmpty)
              TaskAttachmentReference.fromMap(item),
        ],
      );
  final List<TaskChecklistItem> items;
  final List<String> assignees;
  final List<TaskAttachmentReference> attachments;
  TaskChecklistPayload copyWith({
    List<TaskChecklistItem>? items,
    List<String>? assignees,
    List<TaskAttachmentReference>? attachments,
  }) => TaskChecklistPayload(
    items: items ?? this.items,
    assignees: assignees ?? this.assignees,
    attachments: attachments ?? this.attachments,
  );
  Map<String, Object?> toData(Map<String, Object?> existingData) {
    final data = Map<String, Object?>.from(existingData)..remove('checklist');
    final existingTask = _section(existingData, 'task');
    if (existingTask.isNotEmpty ||
        assignees.isNotEmpty ||
        attachments.isNotEmpty) {
      final task = Map<String, Object?>.from(existingTask)
        ..['assignees'] = assignees
        ..['attachments'] = [for (final item in attachments) item.toJson()];
      data['task'] = task;
    }
    return data;
  }

  MindmapNode toNode(MindmapNode existingNode) =>
      existingNode.copyWith(checklist: items, data: toData(existingNode.data));
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    for (final item in items)
      if (item.title.trim().isEmpty) 'Checklist item title is required.',
  ];
}

const Set<String> noteColorTokens = <String>{
  'neutral',
  'violet',
  'blue',
  'green',
  'amber',
  'rose',
};

final class NoteSourceLink {
  const NoteSourceLink({
    required this.id,
    required this.label,
    required this.url,
  });

  factory NoteSourceLink.fromMap(Map<String, Object?> map) => NoteSourceLink(
    id: map['id'] is String ? map['id'] as String : '',
    label: map['label'] is String ? (map['label'] as String).trim() : '',
    url: map['url'] is String ? (map['url'] as String).trim() : '',
  );

  final String id;
  final String label;
  final String url;

  NoteSourceLink copyWith({String? id, String? label, String? url}) =>
      NoteSourceLink(
        id: id ?? this.id,
        label: label ?? this.label,
        url: url ?? this.url,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'url': url,
  };
}

final class NotePayload {
  const NotePayload({
    this.color = 'neutral',
    this.sourceLinks = const <NoteSourceLink>[],
    this.attachments = const <TaskAttachmentReference>[],
  });

  factory NotePayload.fromNode(MindmapNode node) {
    final note = _section(node.data, 'note');
    final color = note['color'] is String ? note['color'] as String : 'neutral';
    return NotePayload(
      color: noteColorTokens.contains(color) ? color : 'neutral',
      sourceLinks: <NoteSourceLink>[
        for (final item in _maps(note['sourceLinks']))
          if (NoteSourceLink.fromMap(item).url.isNotEmpty)
            NoteSourceLink.fromMap(item),
      ],
      attachments: <TaskAttachmentReference>[
        for (final item in _maps(note['attachments']))
          if (item['id'] is String && (item['id'] as String).isNotEmpty)
            TaskAttachmentReference.fromMap(item),
      ],
    );
  }

  final String color;
  final List<NoteSourceLink> sourceLinks;
  final List<TaskAttachmentReference> attachments;

  NotePayload copyWith({
    String? color,
    List<NoteSourceLink>? sourceLinks,
    List<TaskAttachmentReference>? attachments,
  }) => NotePayload(
    color: color ?? this.color,
    sourceLinks: sourceLinks ?? this.sourceLinks,
    attachments: attachments ?? this.attachments,
  );

  Map<String, Object?> toData(Map<String, Object?> existingData) =>
      Map<String, Object?>.from(existingData)
        ..['note'] = <String, Object?>{
          'version': 1,
          'color': noteColorTokens.contains(color) ? color : 'neutral',
          'sourceLinks': <Map<String, Object?>>[
            for (final source in sourceLinks) source.toJson(),
          ],
          'attachments': <Map<String, Object?>>[
            for (final attachment in attachments) attachment.toJson(),
          ],
        };

  List<String> validate({required String title}) => <String>[
    ...NodeValidation.requiredTitle(title),
    for (final source in sourceLinks)
      if (!_isHttpUrl(source.url)) 'Source URL must use http or https.',
  ];
}

enum ChecklistPriority { none, low, medium, high }

final class ChecklistEntry {
  const ChecklistEntry({
    required this.id,
    required this.title,
    this.isDone = false,
    this.priority = ChecklistPriority.none,
    this.dueDate,
  });

  factory ChecklistEntry.fromMap(Map<String, Object?> map) {
    final priorityName = map['priority'] is String
        ? map['priority'] as String
        : '';
    final dueDateValue = map['dueDate'] is String
        ? DateTime.tryParse(map['dueDate'] as String)?.dateOnly
        : null;
    return ChecklistEntry(
      id: map['id'] is String ? map['id'] as String : '',
      title: map['title'] is String ? (map['title'] as String).trim() : '',
      isDone: map['isDone'] is bool ? map['isDone'] as bool : false,
      priority: ChecklistPriority.values.firstWhere(
        (value) => value.name == priorityName,
        orElse: () => ChecklistPriority.none,
      ),
      dueDate: dueDateValue,
    );
  }

  final String id;
  final String title;
  final bool isDone;
  final ChecklistPriority priority;
  final DateTime? dueDate;

  ChecklistEntry copyWith({
    String? id,
    String? title,
    bool? isDone,
    ChecklistPriority? priority,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) => ChecklistEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    isDone: isDone ?? this.isDone,
    priority: priority ?? this.priority,
    dueDate: clearDueDate ? null : dueDate ?? this.dueDate,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title.trim(),
    'isDone': isDone,
    'priority': priority.name,
    if (dueDate != null) 'dueDate': dayKey(dueDate!),
  };
}

final class ChecklistPayload {
  const ChecklistPayload({this.items = const <ChecklistEntry>[]});

  factory ChecklistPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'checklist');
    if (section.isNotEmpty) {
      return ChecklistPayload(
        items: <ChecklistEntry>[
          for (final item in _maps(section['items']))
            if (ChecklistEntry.fromMap(item).title.isNotEmpty)
              ChecklistEntry.fromMap(item),
        ],
      );
    }
    return ChecklistPayload(
      items: <ChecklistEntry>[
        for (final item in node.checklist)
          if (item.title.trim().isNotEmpty)
            ChecklistEntry(
              id: item.id,
              title: item.title.trim(),
              isDone: item.isDone,
            ),
      ],
    );
  }

  final List<ChecklistEntry> items;

  int get completedCount => items.where((item) => item.isDone).length;
  double get progress => items.isEmpty ? 0 : completedCount / items.length;

  ChecklistPayload copyWith({List<ChecklistEntry>? items}) =>
      ChecklistPayload(items: items ?? this.items);

  Map<String, Object?> toData(Map<String, Object?> existingData) =>
      Map<String, Object?>.from(existingData)
        ..['checklist'] = <String, Object?>{
          'version': 1,
          'items': <Map<String, Object?>>[
            for (final item in items) item.toJson(),
          ],
        };

  MindmapNode toNode(MindmapNode existingNode) => existingNode.copyWith(
    checklist: <TaskChecklistItem>[
      for (final item in items)
        TaskChecklistItem(
          id: item.id,
          title: item.title.trim(),
          isDone: item.isDone,
        ),
    ],
    data: toData(existingNode.data),
  );

  List<String> validate({required String title}) => <String>[
    ...NodeValidation.requiredTitle(title),
    for (final item in items)
      if (item.title.trim().isEmpty) 'Checklist item title is required.',
  ];
}

final class KanbanPayload {
  const KanbanPayload({
    this.columns = defaultKanbanColumns,
    this.cards = const [],
  });

  factory KanbanPayload.fromNode(MindmapNode node) {
    final board = KanbanBoard.fromNodeData(node.data);
    return KanbanPayload(columns: board.columns, cards: board.cards);
  }

  final List<KanbanColumnDefinition> columns;
  final List<KanbanCard> cards;

  KanbanBoard get board => KanbanBoard(columns: columns, cards: cards);

  Map<String, Object?> toData(Map<String, Object?> existingData) =>
      _mergeSection(existingData, 'kanban', board.toJson());

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (columns.isEmpty) 'Kanban requires at least one column.',
    if (columns.length > maxKanbanColumns)
      'Kanban supports up to $maxKanbanColumns columns.',
    for (final column in columns)
      if (column.title.trim().isEmpty) 'Kanban column title is required.',
    for (final card in cards) ...[
      if (card.title.trim().isEmpty) 'Kanban card title is required.',
      if (card.title.length > 120)
        'Kanban card title must be 120 characters or fewer.',
      if (card.description.length > 500)
        'Kanban card description must be 500 characters or fewer.',
    ],
  ];
}

final class PlanPayload {
  const PlanPayload({this.project = const ProjectPlan()});

  factory PlanPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'plan');
    final rawProject = section['project'];
    if (rawProject is Map) {
      return PlanPayload(
        project: ProjectPlan.fromJson(rawProject.cast<String, Object?>()),
      );
    }
    final steps = _strings(section['steps']);
    final completed = _strings(section['completedSteps']).toSet();
    if (steps.isEmpty) return const PlanPayload();
    return PlanPayload(
      project: ProjectPlan(
        status: completed.length == steps.length
            ? ProjectPlanStatus.completed
            : ProjectPlanStatus.planning,
        phases: <ProjectPhase>[
          ProjectPhase(
            id: 'legacy-phase',
            title: 'Project',
            order: 0,
            milestones: <ProjectMilestone>[
              ProjectMilestone(
                id: 'legacy-milestone',
                title: 'Plan',
                order: 0,
                tasks: <ProjectTask>[
                  for (var index = 0; index < steps.length; index++)
                    ProjectTask(
                      id: 'legacy-task-$index',
                      title: steps[index],
                      order: index,
                      status: completed.contains(steps[index])
                          ? ProjectTaskStatus.done
                          : ProjectTaskStatus.planned,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  final ProjectPlan project;

  List<String> get steps =>
      project.tasks.map((task) => task.title).toList(growable: false);
  List<String> get completedSteps => project.tasks
      .where((task) => task.status == ProjectTaskStatus.done)
      .map((task) => task.title)
      .toList(growable: false);

  PlanPayload copyWith({ProjectPlan? project}) =>
      PlanPayload(project: project ?? this.project);

  Map<String, Object?> toData(Map<String, Object?> data) {
    final section = _section(data, 'plan');
    final existingProject = section['project'];
    final mergedProject = <String, Object?>{
      if (existingProject is Map) ...existingProject.cast<String, Object?>(),
      ...project.toJson(),
    };
    return _mergeSection(data, 'plan', <String, Object?>{
      'project': mergedProject,
      'steps': steps,
      'completedSteps': completedSteps,
    });
  }

  List<String> validate({required String title}) => <String>[
    ...NodeValidation.requiredTitle(title),
    if (project.startDate != null &&
        project.targetDate != null &&
        project.targetDate!.isBefore(project.startDate!))
      'Plan target date cannot be before its start date.',
    for (final phase in project.phases) ...<String>[
      if (phase.title.trim().isEmpty) 'Plan phase title is required.',
      for (final milestone in phase.milestones) ...<String>[
        if (milestone.title.trim().isEmpty) 'Plan milestone title is required.',
        for (final task in milestone.tasks) ...<String>[
          if (task.title.trim().isEmpty) 'Plan task title is required.',
          if (task.estimatedMinutes != null && task.estimatedMinutes! < 0)
            'Plan task estimate cannot be negative.',
          if (task.actualMinutes != null && task.actualMinutes! < 0)
            'Plan task actual time cannot be negative.',
        ],
      ],
    ],
  ];
}

final class GoalPayload {
  const GoalPayload({
    this.milestones = const [],
    this.completedMilestones = const [],
  });
  factory GoalPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'goal');
    return GoalPayload(
      milestones: _strings(section['milestones']),
      completedMilestones: _strings(section['completedMilestones']),
    );
  }
  final List<String> milestones;
  final List<String> completedMilestones;
  Map<String, Object?> toData(Map<String, Object?> data) => _mergeSection(
    data,
    'goal',
    {'milestones': milestones, 'completedMilestones': completedMilestones},
  );
  List<String> validate({required String title}) =>
      NodeValidation.requiredTitle(title);
}

final class HabitRoutinePayload {
  const HabitRoutinePayload({
    this.target = '',
    this.recurrence = 'daily',
    this.completions = const [],
  });
  factory HabitRoutinePayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'habit');
    return HabitRoutinePayload(
      target: _text(section['target']),
      recurrence: _text(section['recurrence'], fallback: 'daily'),
      completions: _strings(section['completions']),
    );
  }
  final String target;
  final String recurrence;
  final List<String> completions;
  Map<String, Object?> toData(Map<String, Object?> data) => _mergeSection(
    data,
    'habit',
    {'target': target, 'recurrence': recurrence, 'completions': completions},
  );
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (!{'daily', 'weekdays', 'weekly', 'monthly'}.contains(recurrence))
      'Recurrence is invalid.',
    for (final completion in completions) ...NodeValidation.date(completion),
  ];
}

final class JournalPayload {
  const JournalPayload({
    required this.date,
    this.mood,
    this.energy,
    this.prompt = '',
    this.gratitude = const [],
    this.weather = '',
    this.dailyHighlight = '',
    this.isWeeklyReview = false,
    this.isMonthlyReview = false,
  });

  factory JournalPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'journal');
    return JournalPayload(
      date: node.day,
      mood: _integer(section['mood']),
      energy: _integer(section['energy']),
      prompt: _text(section['prompt']),
      gratitude: _strings(section['gratitude']),
      weather: _text(section['weather']),
      dailyHighlight: _text(section['dailyHighlight']),
      isWeeklyReview: section['isWeeklyReview'] is bool
          ? section['isWeeklyReview'] as bool
          : false,
      isMonthlyReview: section['isMonthlyReview'] is bool
          ? section['isMonthlyReview'] as bool
          : false,
    );
  }

  static const List<String> promptTemplates = <String>[
    'What went well today?',
    'What challenged me today and what did I learn?',
    '3 Things I am grateful for today',
    'Evening Reflection & Tomorrow Setup',
    'Weekly Review & Wins Synthesis',
  ];

  static const List<String> weatherOptions = <String>[
    'sunny',
    'cloudy',
    'rainy',
    'stormy',
    'snowy',
  ];

  final DateTime date;
  final int? mood;
  final int? energy;
  final String prompt;
  final List<String> gratitude;
  final String weather;
  final String dailyHighlight;
  final bool isWeeklyReview;
  final bool isMonthlyReview;

  JournalPayload copyWith({
    int? mood,
    bool clearMood = false,
    int? energy,
    bool clearEnergy = false,
    String? prompt,
    List<String>? gratitude,
    String? weather,
    String? dailyHighlight,
    bool? isWeeklyReview,
    bool? isMonthlyReview,
  }) => JournalPayload(
    date: date,
    mood: clearMood ? null : mood ?? this.mood,
    energy: clearEnergy ? null : energy ?? this.energy,
    prompt: prompt ?? this.prompt,
    gratitude: gratitude ?? this.gratitude,
    weather: weather ?? this.weather,
    dailyHighlight: dailyHighlight ?? this.dailyHighlight,
    isWeeklyReview: isWeeklyReview ?? this.isWeeklyReview,
    isMonthlyReview: isMonthlyReview ?? this.isMonthlyReview,
  );

  Map<String, Object?> toData(Map<String, Object?> data) =>
      _mergeSection(data, 'journal', {
        'mood': mood,
        'energy': energy,
        'prompt': prompt,
        'gratitude': gratitude,
        'weather': weather,
        'dailyHighlight': dailyHighlight,
        'isWeeklyReview': isWeeklyReview,
        'isMonthlyReview': isMonthlyReview,
      });

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (mood != null) ...NodeValidation.number(mood, min: 1, max: 10),
    if (energy != null) ...NodeValidation.number(energy, min: 1, max: 10),
  ];
}

final class IdeaPayload {
  const IdeaPayload({
    this.maturity = 'spark',
    this.hypothesis = '',
    this.impact = '',
    this.effort = '',
    this.confidence = 0,
    this.evidence = '',
    this.nextAction = '',
  });

  factory IdeaPayload.fromNode(MindmapNode node) => IdeaPayload(
    maturity: _text(node.data['maturity']).isEmpty
        ? 'spark'
        : _text(node.data['maturity']),
    hypothesis: _text(node.data['hypothesis']),
    impact: _text(node.data['impact']),
    effort: _text(node.data['ideaEffort']),
    confidence: _integer(node.data['confidence']) ?? 0,
    evidence: _text(node.data['evidence']),
    nextAction: _text(node.data['nextAction']),
  );

  static const List<String> maturities = <String>[
    'spark',
    'exploring',
    'validated',
    'executed',
    'archived',
  ];
  static const List<String> levels = <String>['low', 'medium', 'high'];

  final String maturity;
  final String hypothesis;
  final String impact;
  final String effort;
  final int confidence;
  final String evidence;
  final String nextAction;

  int get validationCompleted => <String>[
    hypothesis,
    evidence,
    nextAction,
  ].where((value) => value.trim().isNotEmpty).length;

  String get suggestedMaturity {
    if (hypothesis.trim().isEmpty) return 'spark';
    if (evidence.trim().isEmpty) return 'exploring';
    return 'validated';
  }

  IdeaPayload copyWith({
    String? maturity,
    String? hypothesis,
    String? impact,
    String? effort,
    int? confidence,
    String? evidence,
    String? nextAction,
  }) => IdeaPayload(
    maturity: maturity ?? this.maturity,
    hypothesis: hypothesis ?? this.hypothesis,
    impact: impact ?? this.impact,
    effort: effort ?? this.effort,
    confidence: confidence ?? this.confidence,
    evidence: evidence ?? this.evidence,
    nextAction: nextAction ?? this.nextAction,
  );

  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'maturity': maturity,
    'hypothesis': hypothesis,
    'impact': impact,
    'ideaEffort': effort,
    'confidence': confidence,
    'evidence': evidence,
    'nextAction': nextAction,
  };

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (!maturities.contains(maturity)) 'Idea maturity is invalid.',
    if (impact.isNotEmpty && !levels.contains(impact))
      'Idea impact is invalid.',
    if (effort.isNotEmpty && !levels.contains(effort))
      'Idea effort is invalid.',
    ...NodeValidation.number(confidence, min: 0, max: 100),
  ];
}

final class QuestionPayload {
  const QuestionPayload({
    this.investigationStatus = 'open',
    this.questionText = '',
    this.questionContext = '',
    this.possibleAnswers = const <String>[],
    this.answer = '',
    this.evidence = '',
    this.questionSources = const <String>[],
    this.nextResearchAction = '',
    this.questionConfidence = 0,
  });

  factory QuestionPayload.fromNode(MindmapNode node) => QuestionPayload(
    investigationStatus: _text(
      node.data['investigationStatus'],
      fallback: 'open',
    ),
    questionText: _text(node.data['questionText']),
    questionContext: _text(node.data['questionContext']),
    possibleAnswers: _strings(node.data['possibleAnswers']),
    answer: _text(node.data['answer']),
    evidence: _text(node.data['evidence']),
    questionSources: _strings(node.data['questionSources']),
    nextResearchAction: _text(node.data['nextResearchAction']),
    questionConfidence: _integer(node.data['questionConfidence']) ?? 0,
  );

  static const List<String> statuses = <String>[
    'open',
    'researching',
    'answered',
    'blocked',
  ];

  final String investigationStatus;
  final String questionText;
  final String questionContext;
  final List<String> possibleAnswers;
  final String answer;
  final String evidence;
  final List<String> questionSources;
  final String nextResearchAction;
  final int questionConfidence;

  int get researchCompleted => <bool>[
    questionText.trim().isNotEmpty,
    possibleAnswers.any((value) => value.trim().isNotEmpty),
    evidence.trim().isNotEmpty ||
        questionSources.any((value) => value.trim().isNotEmpty),
    answer.trim().isNotEmpty,
  ].where((completed) => completed).length;

  String get suggestedInvestigationStatus {
    if (answer.trim().isNotEmpty) return 'answered';
    if (possibleAnswers.any((value) => value.trim().isNotEmpty) ||
        evidence.trim().isNotEmpty ||
        questionSources.any((value) => value.trim().isNotEmpty) ||
        nextResearchAction.trim().isNotEmpty) {
      return 'researching';
    }
    return 'open';
  }

  QuestionPayload copyWith({
    String? investigationStatus,
    String? questionText,
    String? questionContext,
    List<String>? possibleAnswers,
    String? answer,
    String? evidence,
    List<String>? questionSources,
    String? nextResearchAction,
    int? questionConfidence,
  }) => QuestionPayload(
    investigationStatus: investigationStatus ?? this.investigationStatus,
    questionText: questionText ?? this.questionText,
    questionContext: questionContext ?? this.questionContext,
    possibleAnswers: possibleAnswers ?? this.possibleAnswers,
    answer: answer ?? this.answer,
    evidence: evidence ?? this.evidence,
    questionSources: questionSources ?? this.questionSources,
    nextResearchAction: nextResearchAction ?? this.nextResearchAction,
    questionConfidence: questionConfidence ?? this.questionConfidence,
  );

  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'investigationStatus': investigationStatus,
    'questionText': questionText,
    'questionContext': questionContext,
    'possibleAnswers': possibleAnswers,
    'answer': answer,
    'evidence': evidence,
    'questionSources': questionSources,
    'nextResearchAction': nextResearchAction,
    'questionConfidence': questionConfidence,
  };

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (!statuses.contains(investigationStatus))
      'Question investigation status is invalid.',
    if (possibleAnswers.any((value) => value.trim().isEmpty))
      'Possible answer cannot be empty.',
    if (questionSources.any((value) => value.trim().isEmpty))
      'Question source cannot be empty.',
    ...NodeValidation.number(questionConfidence, min: 0, max: 100),
  ];
}

final class DecisionCriterion {
  const DecisionCriterion({
    required this.id,
    required this.name,
    this.weight = 1,
  });

  factory DecisionCriterion.fromMap(Map<String, Object?> map) =>
      DecisionCriterion(
        id: _text(map['id']),
        name: _text(map['name']),
        weight: _number(map['weight']) ?? 1,
      );

  final String id;
  final String name;
  final double weight;

  DecisionCriterion copyWith({String? id, String? name, double? weight}) =>
      DecisionCriterion(
        id: id ?? this.id,
        name: name ?? this.name,
        weight: weight ?? this.weight,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'weight': weight,
  };
}

final class DecisionRisk {
  const DecisionRisk({
    required this.id,
    required this.title,
    this.probability = 1,
    this.impact = 1,
  });

  factory DecisionRisk.fromMap(Map<String, Object?> map) => DecisionRisk(
    id: _text(map['id']),
    title: _text(map['title']),
    probability: _integer(map['probability']) ?? 1,
    impact: _integer(map['impact']) ?? 1,
  );

  final String id;
  final String title;
  final int probability;
  final int impact;

  int get exposure => probability * impact;

  DecisionRisk copyWith({String? title, int? probability, int? impact}) =>
      DecisionRisk(
        id: id,
        title: title ?? this.title,
        probability: probability ?? this.probability,
        impact: impact ?? this.impact,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'probability': probability,
    'impact': impact,
  };
}

final class DecisionOption {
  const DecisionOption({
    required this.id,
    required this.title,
    this.description = '',
    this.pros = const <String>[],
    this.cons = const <String>[],
    this.risks = const <String>[],
    this.riskAssessments = const <DecisionRisk>[],
    this.scores = const <String, int>{},
  });

  factory DecisionOption.fromMap(Map<String, Object?> map) => DecisionOption(
    id: _text(map['id']),
    title: _text(map['title']),
    description: _text(map['description']),
    pros: _strings(map['pros']),
    cons: _strings(map['cons']),
    risks: _strings(map['risks']),
    riskAssessments: <DecisionRisk>[
      for (final risk in _maps(map['riskAssessments']))
        DecisionRisk.fromMap(risk),
    ],
    scores: <String, int>{
      for (final entry in _section(map, 'scores').entries)
        entry.key: ?_integer(entry.value),
    },
  );

  final String id;
  final String title;
  final String description;
  final List<String> pros;
  final List<String> cons;
  final List<String> risks;
  final List<DecisionRisk> riskAssessments;
  final Map<String, int> scores;

  int get riskExposure =>
      riskAssessments.fold<int>(0, (total, risk) => total + risk.exposure);

  DecisionOption copyWith({
    String? id,
    String? title,
    String? description,
    List<String>? pros,
    List<String>? cons,
    List<String>? risks,
    List<DecisionRisk>? riskAssessments,
    Map<String, int>? scores,
  }) => DecisionOption(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    pros: pros ?? this.pros,
    cons: cons ?? this.cons,
    risks: risks ?? this.risks,
    riskAssessments: riskAssessments ?? this.riskAssessments,
    scores: scores ?? this.scores,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'pros': pros,
    'cons': cons,
    'risks': risks,
    'riskAssessments': <Map<String, Object?>>[
      for (final risk in riskAssessments) risk.toJson(),
    ],
    'scores': scores,
  };
}

final class DecisionReviewEntry {
  const DecisionReviewEntry({
    required this.id,
    required this.date,
    required this.notes,
    this.rating,
  });

  factory DecisionReviewEntry.fromMap(Map<String, Object?> map) =>
      DecisionReviewEntry(
        id: _text(map['id']),
        date: _text(map['date']),
        notes: _text(map['notes']),
        rating: _integer(map['rating']),
      );

  final String id;
  final String date;
  final String notes;
  final int? rating;

  DecisionReviewEntry copyWith({
    String? date,
    String? notes,
    int? rating,
    bool clearRating = false,
  }) => DecisionReviewEntry(
    id: id,
    date: date ?? this.date,
    notes: notes ?? this.notes,
    rating: clearRating ? null : rating ?? this.rating,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'date': date,
    'notes': notes,
    if (rating != null) 'rating': rating,
  };
}

final class DecisionPayload {
  const DecisionPayload({
    this.status = 'draft',
    this.question = '',
    this.context = '',
    this.owner = '',
    this.deadline = '',
    this.reviewDate = '',
    this.confidence = 0,
    this.criteria = const <DecisionCriterion>[],
    this.options = const <DecisionOption>[],
    this.selectedOptionId = '',
    this.rationale = '',
    this.assumptions = '',
    this.expectedOutcome = '',
    this.reviewNotes = '',
    this.reviewEntries = const <DecisionReviewEntry>[],
  });

  factory DecisionPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'decision');
    final structuredCriteria = <DecisionCriterion>[
      for (final item in _maps(section['criteria']))
        DecisionCriterion.fromMap(item),
    ];
    final structuredOptions = <DecisionOption>[
      for (final item in _maps(section['options']))
        DecisionOption.fromMap(item),
    ];
    final criteria = structuredCriteria.isNotEmpty
        ? structuredCriteria
        : <DecisionCriterion>[
            for (final entry in _strings(node.data['criteria']).indexed)
              DecisionCriterion(
                id: 'criterion-${entry.$1 + 1}',
                name: entry.$2,
              ),
          ];
    final options = structuredOptions.isNotEmpty
        ? structuredOptions
        : <DecisionOption>[
            for (final entry in _strings(node.data['options']).indexed)
              DecisionOption(id: 'option-${entry.$1 + 1}', title: entry.$2),
          ];
    final selectedTitle = _text(node.data['selectedOption']);
    final nestedSelectedId = _text(section['selectedOptionId']);
    final selectedOptionId = nestedSelectedId.isNotEmpty
        ? nestedSelectedId
        : options
                  .where((option) => option.title == selectedTitle)
                  .map((option) => option.id)
                  .firstOrNull ??
              '';
    return DecisionPayload(
      status: _text(section['status'], fallback: 'draft'),
      question: _text(section['question']),
      context: _text(section['context']),
      owner: _text(section['owner']),
      deadline: _text(section['deadline']),
      reviewDate: _text(section['reviewDate']),
      confidence: _integer(section['confidence']) ?? 0,
      criteria: criteria,
      options: options,
      selectedOptionId: selectedOptionId,
      rationale: _text(section['rationale'] ?? node.data['reason']),
      assumptions: _text(section['assumptions']),
      expectedOutcome: _text(section['expectedOutcome']),
      reviewNotes: _text(section['reviewNotes']),
      reviewEntries: <DecisionReviewEntry>[
        for (final entry in _maps(section['reviewEntries']))
          DecisionReviewEntry.fromMap(entry),
      ],
    );
  }

  static const List<String> statuses = <String>[
    'draft',
    'evaluating',
    'decided',
    'reviewing',
    'reversed',
  ];

  final String status;
  final String question;
  final String context;
  final String owner;
  final String deadline;
  final String reviewDate;
  final int confidence;
  final List<DecisionCriterion> criteria;
  final List<DecisionOption> options;
  final String selectedOptionId;
  final String rationale;
  final String assumptions;
  final String expectedOutcome;
  final String reviewNotes;
  final List<DecisionReviewEntry> reviewEntries;

  DecisionOption? get selectedOption =>
      options.where((option) => option.id == selectedOptionId).firstOrNull;

  String get outcome => selectedOption?.title ?? '';

  Map<String, double> get weightedScores {
    final result = <String, double>{};
    for (final option in options) {
      var weightedTotal = 0.0;
      var participatingWeight = 0.0;
      for (final criterion in criteria) {
        final score = option.scores[criterion.id];
        if (criterion.weight <= 0 || score == null || score < 1 || score > 10) {
          continue;
        }
        weightedTotal += score * criterion.weight;
        participatingWeight += criterion.weight;
      }
      if (participatingWeight > 0) {
        result[option.id] = weightedTotal / participatingWeight;
      }
    }
    return result;
  }

  List<DecisionOption> get rankedOptions {
    final scores = weightedScores;
    final indexed = options.indexed.toList(growable: false)
      ..sort((left, right) {
        final scoreCompare = (scores[right.$2.id] ?? -1).compareTo(
          scores[left.$2.id] ?? -1,
        );
        return scoreCompare != 0 ? scoreCompare : left.$1.compareTo(right.$1);
      });
    return <DecisionOption>[for (final entry in indexed) entry.$2];
  }

  String get recommendedOptionId =>
      rankedOptions
          .where((option) => weightedScores.containsKey(option.id))
          .firstOrNull
          ?.id ??
      '';

  int get decisionCompleted => <bool>[
    question.trim().isNotEmpty,
    criteria.any((criterion) => criterion.name.trim().isNotEmpty),
    options.where((option) => option.title.trim().isNotEmpty).length >= 2,
    selectedOption != null,
    rationale.trim().isNotEmpty,
  ].where((completed) => completed).length;

  String get suggestedStatus {
    if (selectedOption != null && rationale.trim().isNotEmpty) return 'decided';
    if (criteria.isNotEmpty || options.isNotEmpty) return 'evaluating';
    return 'draft';
  }

  DecisionPayload copyWith({
    String? status,
    String? question,
    String? context,
    String? owner,
    String? deadline,
    String? reviewDate,
    int? confidence,
    List<DecisionCriterion>? criteria,
    List<DecisionOption>? options,
    String? selectedOptionId,
    bool clearSelectedOption = false,
    String? rationale,
    String? assumptions,
    String? expectedOutcome,
    String? reviewNotes,
    List<DecisionReviewEntry>? reviewEntries,
  }) => DecisionPayload(
    status: status ?? this.status,
    question: question ?? this.question,
    context: context ?? this.context,
    owner: owner ?? this.owner,
    deadline: deadline ?? this.deadline,
    reviewDate: reviewDate ?? this.reviewDate,
    confidence: confidence ?? this.confidence,
    criteria: criteria ?? this.criteria,
    options: options ?? this.options,
    selectedOptionId: clearSelectedOption
        ? ''
        : selectedOptionId ?? this.selectedOptionId,
    rationale: rationale ?? this.rationale,
    assumptions: assumptions ?? this.assumptions,
    expectedOutcome: expectedOutcome ?? this.expectedOutcome,
    reviewNotes: reviewNotes ?? this.reviewNotes,
    reviewEntries: reviewEntries ?? this.reviewEntries,
  );

  DecisionPayload removeCriterion(String criterionId) => copyWith(
    criteria: criteria
        .where((criterion) => criterion.id != criterionId)
        .toList(growable: false),
    options: <DecisionOption>[
      for (final option in options)
        option.copyWith(
          scores: Map<String, int>.from(option.scores)..remove(criterionId),
        ),
    ],
  );

  DecisionPayload removeOption(String optionId) => copyWith(
    options: options
        .where((option) => option.id != optionId)
        .toList(growable: false),
    clearSelectedOption: selectedOptionId == optionId,
  );

  Map<String, Object?> toData(Map<String, Object?> data) {
    final selectedTitle = selectedOption?.title ?? '';
    return <String, Object?>{
      ..._mergeSection(data, 'decision', <String, Object?>{
        'status': status,
        'question': question,
        'context': context,
        'owner': owner,
        'deadline': deadline,
        'reviewDate': reviewDate,
        'confidence': confidence,
        'criteria': <Map<String, Object?>>[
          for (final criterion in criteria) criterion.toJson(),
        ],
        'options': <Map<String, Object?>>[
          for (final option in options) option.toJson(),
        ],
        'selectedOptionId': selectedOptionId,
        'rationale': rationale,
        'assumptions': assumptions,
        'expectedOutcome': expectedOutcome,
        'reviewNotes': reviewNotes,
        'reviewEntries': <Map<String, Object?>>[
          for (final entry in reviewEntries) entry.toJson(),
        ],
      }),
      'options': options.map((option) => option.title).join('\n'),
      'criteria': criteria.map((criterion) => criterion.name).join('\n'),
      'selectedOption': selectedTitle,
      'reason': rationale,
    };
  }

  List<String> validate({required String title}) {
    final errors = <String>[
      ...NodeValidation.requiredTitle(title),
      if (!statuses.contains(status)) 'Decision status is invalid.',
      ...NodeValidation.number(confidence, min: 0, max: 100),
      if (deadline.isNotEmpty && !_isIsoDate(deadline))
        'Decision deadline must use YYYY-MM-DD.',
      if (reviewDate.isNotEmpty && !_isIsoDate(reviewDate))
        'Decision review date must use YYYY-MM-DD.',
    ];
    final criterionIds = <String>{};
    for (final criterion in criteria) {
      if (criterion.id.trim().isEmpty) errors.add('Criterion ID is required.');
      if (!criterionIds.add(criterion.id)) {
        errors.add('Criterion IDs must be unique.');
      }
      if (criterion.name.trim().isEmpty) {
        errors.add('Criterion name is required.');
      }
      if (!criterion.weight.isFinite || criterion.weight <= 0) {
        errors.add('Criterion weight must be positive.');
      }
    }
    final optionIds = <String>{};
    for (final option in options) {
      if (option.id.trim().isEmpty) errors.add('Option ID is required.');
      if (!optionIds.add(option.id)) errors.add('Option IDs must be unique.');
      if (option.title.trim().isEmpty) errors.add('Option title is required.');
      for (final entry in option.scores.entries) {
        if (!criterionIds.contains(entry.key)) {
          errors.add('Option score references an unknown criterion.');
        }
        if (entry.value < 1 || entry.value > 10) {
          errors.add('Option score must be from 1 to 10.');
        }
      }
      for (final risk in option.riskAssessments) {
        if (risk.id.trim().isEmpty || risk.title.trim().isEmpty) {
          errors.add('Decision risk ID and title are required.');
        }
        if (risk.probability < 1 ||
            risk.probability > 5 ||
            risk.impact < 1 ||
            risk.impact > 5) {
          errors.add('Decision risk probability and impact must be 1 to 5.');
        }
      }
    }
    for (final entry in reviewEntries) {
      if (entry.id.trim().isEmpty ||
          !_isIsoDate(entry.date) ||
          entry.notes.trim().isEmpty) {
        errors.add('Decision review entry is invalid.');
      }
      if (entry.rating != null && (entry.rating! < 1 || entry.rating! > 5)) {
        errors.add('Decision review rating must be 1 to 5.');
      }
    }
    if (selectedOptionId.isNotEmpty && !optionIds.contains(selectedOptionId)) {
      errors.add('Selected option does not exist.');
    }
    return List<String>.unmodifiable(errors);
  }
}

bool _isIsoDate(String value) {
  final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(value);
  if (match == null) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && _dateKey(parsed) == value;
}

final class QuotePayload {
  const QuotePayload({
    this.author = '',
    this.source = '',
    this.collection = '',
    this.tags = const <String>[],
    this.isFavorite = false,
    this.remoteQuoteId = '',
    this.quoteProvider = '',
    this.sourceUrl = '',
  });

  factory QuotePayload.fromNode(MindmapNode node) => QuotePayload(
    author: _text(node.data['author']),
    source: _text(node.data['quoteSource']),
    collection: _text(node.data['collection']),
    tags: _normalizeQuoteTags(_strings(node.data['tags'])),
    isFavorite: node.data['isFavorite'] == true,
    remoteQuoteId: _text(node.data['remoteQuoteId']),
    quoteProvider: _text(node.data['quoteProvider']),
    sourceUrl: _text(node.data['sourceUrl']),
  );

  final String author;
  final String source;
  final String collection;
  final List<String> tags;
  final bool isFavorite;
  final String remoteQuoteId;
  final String quoteProvider;
  final String sourceUrl;

  QuotePayload copyWith({
    String? author,
    String? source,
    String? collection,
    List<String>? tags,
    bool? isFavorite,
    String? remoteQuoteId,
    String? quoteProvider,
    String? sourceUrl,
  }) => QuotePayload(
    author: author ?? this.author,
    source: source ?? this.source,
    collection: collection ?? this.collection,
    tags: tags ?? this.tags,
    isFavorite: isFavorite ?? this.isFavorite,
    remoteQuoteId: remoteQuoteId ?? this.remoteQuoteId,
    quoteProvider: quoteProvider ?? this.quoteProvider,
    sourceUrl: sourceUrl ?? this.sourceUrl,
  );

  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'author': author,
    'quoteSource': source,
    'collection': collection,
    'tags': _normalizeQuoteTags(tags),
    'isFavorite': isFavorite,
    'remoteQuoteId': remoteQuoteId,
    'quoteProvider': quoteProvider,
    'sourceUrl': sourceUrl,
  };

  List<String> validate({required String title}) =>
      NodeValidation.requiredTitle(title);
}

List<String> _normalizeQuoteTags(Iterable<String> values) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final tag = value.trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
    normalized.add(tag);
  }
  return List<String>.unmodifiable(normalized);
}

final class EventCalendarPayload {
  const EventCalendarPayload({
    this.kind = 'event',
    this.location = '',
    this.startDate = '',
    this.endDate = '',
    this.startTime = '',
    this.endTime = '',
  });
  factory EventCalendarPayload.fromNode(MindmapNode node) =>
      EventCalendarPayload(
        kind: _text(
          node.data['calendar_kind'] ?? node.data['calendarKind'],
          fallback: 'event',
        ),
        location: _text(node.data['location']),
        startDate: _text(node.data['startDate']),
        endDate: _text(node.data['endDate']),
        startTime: _text(node.data['startTime']),
        endTime: _text(node.data['endTime']),
      );
  final String kind;
  final String location;
  final String startDate;
  final String endDate;
  final String startTime;
  final String endTime;
  EventCalendarPayload copyWith({
    String? kind,
    String? location,
    String? startDate,
    String? endDate,
    String? startTime,
    String? endTime,
  }) => EventCalendarPayload(
    kind: kind ?? this.kind,
    location: location ?? this.location,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
  );
  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'calendar_kind': kind,
    'location': location,
    'startDate': startDate,
    'endDate': endDate,
    'startTime': startTime,
    'endTime': endTime,
  };
  EventRangeValidation get rangeValidation => EventRangeValidation.from(this);
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    ...rangeValidation.errors,
  ];
}

final class EventRangeValidation {
  const EventRangeValidation({
    this.startDateError,
    this.endDateError,
    this.startTimeError,
    this.endTimeError,
  });

  factory EventRangeValidation.from(EventCalendarPayload payload) {
    String? startDateError;
    String? endDateError;
    String? startTimeError;
    String? endTimeError;
    DateTime? startDay;
    DateTime? endDay;
    final hasDate = payload.startDate.isNotEmpty || payload.endDate.isNotEmpty;
    if (hasDate) {
      final startErrors = NodeValidation.date(payload.startDate);
      final endErrors = NodeValidation.date(payload.endDate);
      startDateError = startErrors.isEmpty ? null : startErrors.first;
      endDateError = endErrors.isEmpty ? null : endErrors.first;
      if (startDateError == null && endDateError == null) {
        startDay = DateTime.parse(payload.startDate).dateOnly;
        endDay = DateTime.parse(payload.endDate).dateOnly;
        if (endDay.isBefore(startDay)) {
          const error = 'End date must not precede start date.';
          startDateError = error;
          endDateError = error;
        }
      }
    }

    final hasTime = payload.startTime.isNotEmpty || payload.endTime.isNotEmpty;
    int? startMinutes;
    int? endMinutes;
    if (hasTime) {
      startMinutes = _eventTimeMinutes(payload.startTime);
      endMinutes = _eventTimeMinutes(payload.endTime);
      if (startMinutes == null) startTimeError = 'Time is invalid.';
      if (endMinutes == null) endTimeError = 'Time is invalid.';
      final datesComparable =
          !hasDate ||
          (startDay != null &&
              endDay != null &&
              startDateError == null &&
              endDateError == null);
      if (startMinutes != null && endMinutes != null && datesComparable) {
        final start = (startDay ?? DateTime(2000)).add(
          Duration(minutes: startMinutes),
        );
        final end = (endDay ?? DateTime(2000)).add(
          Duration(minutes: endMinutes),
        );
        if (end.isBefore(start)) {
          const error = 'End time must not precede start time.';
          startTimeError = error;
          endTimeError = error;
        }
      }
    }
    return EventRangeValidation(
      startDateError: startDateError,
      endDateError: endDateError,
      startTimeError: startTimeError,
      endTimeError: endTimeError,
    );
  }

  final String? startDateError;
  final String? endDateError;
  final String? startTimeError;
  final String? endTimeError;

  List<String> get errors => <String>{
    ?startDateError,
    ?endDateError,
    ?startTimeError,
    ?endTimeError,
  }.toList(growable: false);
}

int? _eventTimeMinutes(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  return hour <= 23 && minute <= 59 ? hour * 60 + minute : null;
}

final class ContactRecord {
  const ContactRecord({
    required this.id,
    this.name = '',
    this.role = '',
    this.company = '',
    this.email = '',
    this.dialCode = '+62',
    this.phone = '',
  });

  factory ContactRecord.fromMap(Map<String, Object?> map) => ContactRecord(
    id: _text(map['id']),
    name: _text(map['name']),
    role: _text(map['role']),
    company: _text(map['company']),
    email: _text(map['email']),
    dialCode: _text(map['dialCode'], fallback: '+62'),
    phone: _text(map['phone']),
  );

  final String id;
  final String name;
  final String role;
  final String company;
  final String email;
  final String dialCode;
  final String phone;

  ContactRecord copyWith({
    String? name,
    String? role,
    String? company,
    String? email,
    String? dialCode,
    String? phone,
  }) => ContactRecord(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    company: company ?? this.company,
    email: email ?? this.email,
    dialCode: dialCode ?? this.dialCode,
    phone: phone ?? this.phone,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'role': role,
    'company': company,
    'email': email,
    'dialCode': dialCode,
    'phone': phone,
  };
}

final class ContactPayload {
  const ContactPayload({
    this.role = '',
    this.company = '',
    this.email = '',
    this.phone = '',
    this.dialCode = '+62',
    this.additionalContacts = const [],
    this.collapsedContactIds = const ['primary'],
  });
  factory ContactPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'contact');
    return ContactPayload(
      role: _text(node.data['role']),
      company: _text(node.data['company']),
      email: _text(node.data['email']),
      phone: _text(node.data['phone']),
      dialCode: _text(section['dialCode'], fallback: '+62'),
      additionalContacts: _maps(section['additionalContacts'])
          .map(ContactRecord.fromMap)
          .where((record) => record.id.isNotEmpty)
          .toList(),
      collapsedContactIds: section.containsKey('collapsedContactIds')
          ? _strings(section['collapsedContactIds'])
          : const ['primary'],
    );
  }
  final String role;
  final String company;
  final String email;
  final String phone;
  final String dialCode;
  final List<ContactRecord> additionalContacts;
  final List<String> collapsedContactIds;
  ContactPayload copyWith({
    String? role,
    String? company,
    String? email,
    String? phone,
    String? dialCode,
    List<ContactRecord>? additionalContacts,
    List<String>? collapsedContactIds,
  }) => ContactPayload(
    role: role ?? this.role,
    company: company ?? this.company,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    dialCode: dialCode ?? this.dialCode,
    additionalContacts: additionalContacts ?? this.additionalContacts,
    collapsedContactIds: collapsedContactIds ?? this.collapsedContactIds,
  );
  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'role': role,
    'company': company,
    'email': email,
    'phone': phone,
    'contact': {
      ..._section(data, 'contact'),
      'version': 1,
      'dialCode': dialCode,
      'additionalContacts': additionalContacts
          .map((record) => record.toMap())
          .toList(),
      'collapsedContactIds': collapsedContactIds,
    },
  };
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (!_validContactEmail(email)) 'Email format is invalid.',
    for (final record in additionalContacts)
      if (!_validContactEmail(record.email))
        'Email format is invalid for ${record.name.isEmpty ? 'additional contact' : record.name}.',
  ];
}

bool _validContactEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return true;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

final class MetricPayload {
  const MetricPayload({
    this.value,
    this.unit = '',
    this.target,
    this.direction = 'atLeast',
  });
  factory MetricPayload.fromNode(MindmapNode node) {
    final direction = _text(node.data['direction'], fallback: 'atLeast');
    return MetricPayload(
      value: _number(node.data['value']),
      unit: _text(node.data['unit']),
      target: _number(node.data['target']),
      direction: {'atLeast', 'atMost'}.contains(direction)
          ? direction
          : 'atLeast',
    );
  }
  final double? value;
  final String unit;
  final double? target;
  final String direction;
  MetricPayload copyWith({
    double? value,
    String? unit,
    double? target,
    String? direction,
    bool clearValue = false,
    bool clearTarget = false,
  }) => MetricPayload(
    value: clearValue ? null : value ?? this.value,
    unit: unit ?? this.unit,
    target: clearTarget ? null : target ?? this.target,
    direction: direction ?? this.direction,
  );
  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'value': value,
    'unit': unit.trim(),
    'target': target,
    'direction': direction,
  };
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    ...NodeValidation.number(value),
    if (target != null) ...NodeValidation.number(target),
  ];
}

enum ExpenseTransactionType { expense, income }

final class ExpensePayload {
  const ExpensePayload({
    this.amount,
    this.category = '',
    this.merchant = '',
    this.payment = '',
    this.currency = '',
    this.transactionType = ExpenseTransactionType.expense,
    this.receipts = const [],
  });
  factory ExpensePayload.fromNode(MindmapNode node) => ExpensePayload(
    amount: _number(node.data['amount']),
    category: _text(node.data['category']),
    merchant: _text(node.data['merchant']),
    payment: _text(node.data['payment']),
    currency: _text(node.data['currency']),
    transactionType:
        ExpenseTransactionType.values
            .where((value) => value.name == _text(node.data['transactionType']))
            .firstOrNull ??
        ExpenseTransactionType.expense,
    receipts: _maps(_section(node.data, 'expense')['receipts'])
        .map(ResourceAsset.fromJson)
        .where((asset) => asset.attachmentId.isNotEmpty)
        .toList(),
  );
  final double? amount;
  final String category;
  final String merchant;
  final String payment;
  final String currency;
  final ExpenseTransactionType transactionType;
  final List<ResourceAsset> receipts;
  ExpensePayload copyWith({
    double? amount,
    String? category,
    String? merchant,
    String? payment,
    String? currency,
    ExpenseTransactionType? transactionType,
    List<ResourceAsset>? receipts,
    bool clearAmount = false,
  }) => ExpensePayload(
    amount: clearAmount ? null : amount ?? this.amount,
    category: category ?? this.category,
    merchant: merchant ?? this.merchant,
    payment: payment ?? this.payment,
    currency: currency ?? this.currency,
    transactionType: transactionType ?? this.transactionType,
    receipts: receipts ?? this.receipts,
  );
  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'amount': amount,
    'category': category,
    'merchant': merchant,
    'payment': payment,
    'currency': currency.trim().toUpperCase(),
    'transactionType': transactionType.name,
    'expense': {
      ..._section(data, 'expense'),
      'version': 1,
      'receipts': receipts.map((asset) => asset.toJson()).toList(),
    },
  };
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    ...NodeValidation.number(amount, min: 0),
  ];
}

final class MoodPayload {
  const MoodPayload({this.mood, this.energy});
  factory MoodPayload.fromNode(MindmapNode node) => MoodPayload(
    mood: node.data['mood'] is String ? node.data['mood'] as String : null,
    energy: _number(node.data['energy']),
  );
  final String? mood;
  final double? energy;
  MoodPayload copyWith({
    String? mood,
    double? energy,
    bool clearMood = false,
    bool clearEnergy = false,
  }) => MoodPayload(
    mood: clearMood ? null : mood ?? this.mood,
    energy: clearEnergy ? null : energy ?? this.energy,
  );
  Map<String, Object?> toData(Map<String, Object?> data) => {
    ...data,
    'mood': mood,
    'energy': energy,
  };
  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    ...NodeValidation.number(energy, min: 1, max: 5),
  ];
}

final class WeatherPayload {
  const WeatherPayload({
    this.temp = '',
    this.apparentTemp = '',
    this.humidity,
    this.windSpeed,
    this.weather = '',
    this.unit = '°C',
    this.weatherCode = '',
    this.weatherDate = '',
    this.latitude,
    this.longitude,
    this.location = '',
    this.fetchedAt = '',
    this.timezone = '',
    this.isDay,
  });
  factory WeatherPayload.fromNode(MindmapNode node) {
    final rawTemp = _text(
      node.data['temp'],
      fallback: _text(node.data['temperature']),
    );
    final normalizedTemp = rawTemp.replaceAll(RegExp(r'[^0-9+\-.]'), '');
    return WeatherPayload(
      temp: normalizedTemp,
      apparentTemp: _text(
        node.data['weatherApparentTemp'],
      ).replaceAll(RegExp(r'[^0-9+\-.]'), ''),
      humidity: _number(node.data['weatherHumidity']),
      windSpeed: _number(node.data['weatherWindSpeed']),
      weather: _text(
        node.data['weather'],
        fallback: _text(node.data['condition']),
      ),
      unit: _normalizeWeatherUnit(
        _text(node.data['weatherUnit'], fallback: '°C'),
      ),
      weatherCode: _text(node.data['weatherCode']),
      weatherDate: _text(node.data['weatherDate']),
      latitude: _number(node.data['weatherLatitude']),
      longitude: _number(node.data['weatherLongitude']),
      location: _text(node.data['weatherLocation']),
      fetchedAt: _text(node.data['weatherFetchedAt']),
      timezone: _text(node.data['weatherTimezone']),
      isDay: switch (node.data['weatherIsDay']) {
        final bool value => value,
        final num value => value != 0,
        _ => null,
      },
    );
  }
  final String temp;
  final String apparentTemp;
  final double? humidity;
  final double? windSpeed;
  final String weather;
  final String unit;
  final String weatherCode;
  final String weatherDate;
  final double? latitude;
  final double? longitude;
  final String location;
  final String fetchedAt;
  final String timezone;
  final bool? isDay;
  WeatherPayload copyWith({
    String? temp,
    String? apparentTemp,
    double? humidity,
    double? windSpeed,
    String? weather,
    String? unit,
    String? weatherCode,
    String? weatherDate,
    double? latitude,
    double? longitude,
    String? location,
    String? fetchedAt,
    String? timezone,
    bool? isDay,
    bool clearCoordinates = false,
  }) => WeatherPayload(
    temp: temp ?? this.temp,
    apparentTemp: apparentTemp ?? this.apparentTemp,
    humidity: humidity ?? this.humidity,
    windSpeed: windSpeed ?? this.windSpeed,
    weather: weather ?? this.weather,
    unit: unit ?? this.unit,
    weatherCode: weatherCode ?? this.weatherCode,
    weatherDate: weatherDate ?? this.weatherDate,
    latitude: clearCoordinates ? null : latitude ?? this.latitude,
    longitude: clearCoordinates ? null : longitude ?? this.longitude,
    location: location ?? this.location,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    timezone: timezone ?? this.timezone,
    isDay: isDay ?? this.isDay,
  );
  Map<String, Object?> toData(Map<String, Object?> data) {
    final result = Map<String, Object?>.from(data)
      ..remove('temperature')
      ..remove('condition')
      ..['temp'] = temp.trim()
      ..['weatherApparentTemp'] = apparentTemp.trim()
      ..['weatherHumidity'] = humidity
      ..['weatherWindSpeed'] = windSpeed
      ..['weather'] = weather.trim()
      ..['weatherUnit'] = _normalizeWeatherUnit(unit)
      ..['weatherCode'] = weatherCode.trim()
      ..['weatherDate'] = weatherDate.trim()
      ..['weatherLatitude'] = latitude
      ..['weatherLongitude'] = longitude
      ..['weatherLocation'] = location.trim()
      ..['weatherFetchedAt'] = fetchedAt.trim()
      ..['weatherTimezone'] = timezone.trim()
      ..['weatherIsDay'] = isDay;
    return result;
  }

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (temp.trim().isNotEmpty)
      ...NodeValidation.number(double.tryParse(temp.trim())),
    if (apparentTemp.trim().isNotEmpty)
      ...NodeValidation.number(double.tryParse(apparentTemp.trim())),
    if (humidity != null) ...NodeValidation.number(humidity, min: 0, max: 100),
    if (windSpeed != null) ...NodeValidation.number(windSpeed, min: 0),
    if (!{'°C', '°F'}.contains(_normalizeWeatherUnit(unit)))
      'Weather unit is invalid.',
    if (weatherDate.trim().isNotEmpty)
      ...NodeValidation.date(weatherDate, required: false),
    if (latitude != null) ...NodeValidation.number(latitude, min: -90, max: 90),
    if (longitude != null)
      ...NodeValidation.number(longitude, min: -180, max: 180),
  ];
}

String normalizeLegacyWeatherBody(String value) => value
    .replaceAll('Ãƒâ€šÃ‚Â°C', '°C')
    .replaceAll('Ã‚Â°C', '°C')
    .replaceAll('Â°C', '°C')
    .replaceAll('Ãƒâ€šÃ‚Â°F', '°F')
    .replaceAll('Ã‚Â°F', '°F')
    .replaceAll('Â°F', '°F');

String _normalizeWeatherUnit(String value) {
  final normalized = value.trim().toUpperCase();
  return normalized.contains('F') ? '°F' : '°C';
}

final class FitnessWorkoutSet {
  const FitnessWorkoutSet({
    required this.id,
    required this.reps,
    this.weight,
    this.completed = false,
  });

  factory FitnessWorkoutSet.fromMap(Map<String, Object?> map) =>
      FitnessWorkoutSet(
        id: _text(map['id']),
        reps: _integer(map['reps']) ?? 0,
        weight: _number(map['weight']),
        completed: map['completed'] == true,
      );

  final String id;
  final int reps;
  final double? weight;
  final bool completed;

  FitnessWorkoutSet copyWith({
    int? reps,
    double? weight,
    bool clearWeight = false,
    bool? completed,
  }) => FitnessWorkoutSet(
    id: id,
    reps: reps ?? this.reps,
    weight: clearWeight ? null : weight ?? this.weight,
    completed: completed ?? this.completed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'reps': reps,
    if (weight != null) 'weight': weight,
    'completed': completed,
  };
}

final class FitnessExercise {
  const FitnessExercise({
    required this.id,
    required this.name,
    this.sets = const <FitnessWorkoutSet>[],
  });

  factory FitnessExercise.fromMap(Map<String, Object?> map) => FitnessExercise(
    id: _text(map['id']),
    name: _text(map['name']),
    sets: <FitnessWorkoutSet>[
      for (final item in _maps(map['sets'])) FitnessWorkoutSet.fromMap(item),
    ],
  );

  final String id;
  final String name;
  final List<FitnessWorkoutSet> sets;

  FitnessExercise copyWith({String? name, List<FitnessWorkoutSet>? sets}) =>
      FitnessExercise(id: id, name: name ?? this.name, sets: sets ?? this.sets);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'sets': <Map<String, Object?>>[for (final set in sets) set.toJson()],
  };
}

final class FitPayload {
  const FitPayload({
    this.steps,
    this.stepGoal = 10000,
    this.water,
    this.waterGoal = 2,
    this.distance,
    this.durationMinutes,
    this.durationGoalMinutes = 30,
    this.calories,
    this.calorieGoal = 500,
    this.sleepHours,
    this.restingHeartRate,
    this.workout = '',
    this.intensity = 'moderate',
    this.completed = false,
    this.syncEnabled = false,
    this.syncSource = '',
    this.syncedAt = '',
    this.waterUnit = 'L',
    this.distanceUnit = 'km',
    this.exercises = const <FitnessExercise>[],
  });
  factory FitPayload.fromNode(MindmapNode node) => FitPayload(
    steps: _number(node.data['steps']),
    stepGoal:
        _number(node.data['stepGoal']) ??
        _number(node.data['stepTarget']) ??
        10000,
    water: _number(node.data['water']),
    waterGoal:
        _number(node.data['waterGoal']) ??
        _number(node.data['waterTarget']) ??
        2,
    distance: _number(node.data['fitDistance']),
    durationMinutes: _number(node.data['fitDurationMinutes']),
    durationGoalMinutes:
        _number(node.data['fitDurationGoalMinutes']) ??
        _number(node.data['activeMinutesGoal']) ??
        30,
    calories: _number(node.data['fitCalories']),
    calorieGoal:
        _number(node.data['fitCalorieGoal']) ??
        _number(node.data['calorieGoal']) ??
        500,
    sleepHours:
        _number(node.data['fitSleepHours']) ?? _number(node.data['sleepHours']),
    restingHeartRate:
        _number(node.data['fitRestingHeartRate']) ??
        _number(node.data['restingHeartRate']),
    workout: _text(
      node.data['workout'],
      fallback: _text(node.data['fitActivity']),
    ),
    intensity: _normalizeFitIntensity(_text(node.data['fitIntensity'])),
    completed: node.data['fitCompleted'] == true,
    syncEnabled: node.data['fitSyncEnabled'] == true,
    syncSource: _text(node.data['fitSyncSource']),
    syncedAt: _text(node.data['fitSyncedAt']),
    waterUnit: _text(node.data['waterUnit'], fallback: 'L'),
    distanceUnit: _text(node.data['distanceUnit'], fallback: 'km'),
    exercises: <FitnessExercise>[
      for (final item in _maps(_section(node.data, 'fitness')['exercises']))
        FitnessExercise.fromMap(item),
    ],
  );
  final double? steps;
  final double stepGoal;
  final double? water;
  final double waterGoal;
  final double? distance;
  final double? durationMinutes;
  final double durationGoalMinutes;
  final double? calories;
  final double calorieGoal;
  final double? sleepHours;
  final double? restingHeartRate;
  final String workout;
  final String intensity;
  final bool completed;
  final bool syncEnabled;
  final String syncSource;
  final String syncedAt;
  final String waterUnit;
  final String distanceUnit;
  final List<FitnessExercise> exercises;
  FitPayload copyWith({
    double? steps,
    double? stepGoal,
    double? water,
    double? waterGoal,
    double? distance,
    double? durationMinutes,
    double? durationGoalMinutes,
    double? calories,
    double? calorieGoal,
    double? sleepHours,
    double? restingHeartRate,
    String? workout,
    String? intensity,
    bool? completed,
    bool? syncEnabled,
    String? syncSource,
    String? syncedAt,
    String? waterUnit,
    String? distanceUnit,
    List<FitnessExercise>? exercises,
    bool clearSteps = false,
    bool clearWater = false,
    bool clearDistance = false,
    bool clearDuration = false,
    bool clearCalories = false,
    bool clearSleep = false,
    bool clearRestingHeartRate = false,
  }) => FitPayload(
    steps: clearSteps ? null : steps ?? this.steps,
    stepGoal: stepGoal ?? this.stepGoal,
    water: clearWater ? null : water ?? this.water,
    waterGoal: waterGoal ?? this.waterGoal,
    distance: clearDistance ? null : distance ?? this.distance,
    durationMinutes: clearDuration
        ? null
        : durationMinutes ?? this.durationMinutes,
    durationGoalMinutes: durationGoalMinutes ?? this.durationGoalMinutes,
    calories: clearCalories ? null : calories ?? this.calories,
    calorieGoal: calorieGoal ?? this.calorieGoal,
    sleepHours: clearSleep ? null : sleepHours ?? this.sleepHours,
    restingHeartRate: clearRestingHeartRate
        ? null
        : restingHeartRate ?? this.restingHeartRate,
    workout: workout ?? this.workout,
    intensity: intensity ?? this.intensity,
    completed: completed ?? this.completed,
    syncEnabled: syncEnabled ?? this.syncEnabled,
    syncSource: syncSource ?? this.syncSource,
    syncedAt: syncedAt ?? this.syncedAt,
    waterUnit: waterUnit ?? this.waterUnit,
    distanceUnit: distanceUnit ?? this.distanceUnit,
    exercises: exercises ?? this.exercises,
  );
  Map<String, Object?> toData(Map<String, Object?> data) {
    final result = Map<String, Object?>.from(data)
      ..remove('stepTarget')
      ..remove('waterTarget')
      ..remove('fitActivity')
      ..remove('activeMinutesGoal')
      ..remove('calorieGoal')
      ..remove('sleepHours')
      ..remove('restingHeartRate')
      ..['steps'] = steps
      ..['stepGoal'] = stepGoal
      ..['water'] = water
      ..['waterGoal'] = waterGoal
      ..['fitDistance'] = distance
      ..['fitDurationMinutes'] = durationMinutes
      ..['fitDurationGoalMinutes'] = durationGoalMinutes
      ..['fitCalories'] = calories
      ..['fitCalorieGoal'] = calorieGoal
      ..['fitSleepHours'] = sleepHours
      ..['fitRestingHeartRate'] = restingHeartRate
      ..['workout'] = workout.trim()
      ..['fitIntensity'] = _normalizeFitIntensity(intensity)
      ..['fitCompleted'] = completed
      ..['fitSyncEnabled'] = syncEnabled
      ..['fitSyncSource'] = syncSource.trim()
      ..['fitSyncedAt'] = syncedAt.trim()
      ..['waterUnit'] = waterUnit.trim().isEmpty ? 'L' : waterUnit.trim()
      ..['distanceUnit'] = distanceUnit.trim().isEmpty
          ? 'km'
          : distanceUnit.trim()
      ..['fitness'] = <String, Object?>{
        ..._section(data, 'fitness'),
        'version': 1,
        'exercises': <Map<String, Object?>>[
          for (final exercise in exercises) exercise.toJson(),
        ],
      };
    return result;
  }

  List<String> validate({required String title}) {
    final errors = <String>[
      ...NodeValidation.requiredTitle(title),
      if (steps != null) ...NodeValidation.number(steps, min: 0),
      ...NodeValidation.number(stepGoal, min: 1),
      if (water != null) ...NodeValidation.number(water, min: 0),
      ...NodeValidation.number(waterGoal, min: 0.01),
      if (distance != null) ...NodeValidation.number(distance, min: 0),
      if (durationMinutes != null)
        ...NodeValidation.number(durationMinutes, min: 0),
      ...NodeValidation.number(durationGoalMinutes, min: 1),
      if (calories != null) ...NodeValidation.number(calories, min: 0),
      ...NodeValidation.number(calorieGoal, min: 1),
      if (sleepHours != null)
        ...NodeValidation.number(sleepHours, min: 0, max: 24),
      if (restingHeartRate != null)
        ...NodeValidation.number(restingHeartRate, min: 20, max: 250),
      if (!{'low', 'moderate', 'high'}.contains(intensity.trim().toLowerCase()))
        'Fitness intensity is invalid.',
    ];
    final exerciseIds = <String>{};
    for (final exercise in exercises) {
      if (exercise.id.trim().isEmpty || exercise.name.trim().isEmpty) {
        errors.add('Fitness exercise is invalid.');
      }
      if (!exerciseIds.add(exercise.id)) {
        errors.add('Fitness exercise IDs must be unique.');
      }
      final setIds = <String>{};
      for (final set in exercise.sets) {
        if (set.id.trim().isEmpty || set.reps < 1 || set.reps > 1000) {
          errors.add('Fitness workout set is invalid.');
        }
        if (!setIds.add(set.id)) {
          errors.add('Fitness workout set IDs must be unique per exercise.');
        }
        if (set.weight != null && (!set.weight!.isFinite || set.weight! < 0)) {
          errors.add('Fitness workout weight is invalid.');
        }
      }
    }
    return errors;
  }
}

String _normalizeFitIntensity(String value) =>
    switch (value.trim().toLowerCase()) {
      'low' => 'low',
      'high' => 'high',
      _ => 'moderate',
    };

final class LinkResourcePayload {
  const LinkResourcePayload({
    required this.type,
    this.url = '',
    this.collection = '',
    this.tags = const [],
    this.category = '',
    this.description = '',
    this.links = const [],
    this.bookmarkStatus = 'inbox',
    this.isFavorite = false,
  });
  factory LinkResourcePayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'link');
    return LinkResourcePayload(
      type: node.type,
      url: node.type == NodeType.link
          ? _text(section['url'] ?? node.data['url'])
          : _text(node.data[node.type == NodeType.resource ? 'source' : 'url']),
      collection: _text(node.data['collection']),
      tags: node.tags,
      category: _text(node.data['category']),
      description: _text(node.data['description']),
      links: _strings(node.data['links']),
      bookmarkStatus: _text(node.data['bookmarkStatus'], fallback: 'inbox'),
      isFavorite: node.data['bookmarkFavorite'] == true,
    );
  }
  final NodeType type;
  final String url;
  final String collection;
  final List<String> tags;
  final String category;
  final String description;
  final List<String> links;
  final String bookmarkStatus;
  final bool isFavorite;
  LinkResourcePayload copyWith({
    String? url,
    String? collection,
    List<String>? tags,
    String? category,
    String? description,
    List<String>? links,
    String? bookmarkStatus,
    bool? isFavorite,
  }) => LinkResourcePayload(
    type: type,
    url: url ?? this.url,
    collection: collection ?? this.collection,
    tags: tags ?? this.tags,
    category: category ?? this.category,
    description: description ?? this.description,
    links: links ?? this.links,
    bookmarkStatus: bookmarkStatus ?? this.bookmarkStatus,
    isFavorite: isFavorite ?? this.isFavorite,
  );
  Map<String, Object?> toData(Map<String, Object?> data) {
    if (type == NodeType.link) return _mergeSection(data, 'link', {'url': url});
    final result = Map<String, Object?>.from(data);
    if (type == NodeType.resource) {
      _removeSectionField(result, 'note', 'source');
      result
        ..['source'] = url
        ..['category'] = category
        ..['description'] = description
        ..['links'] = links;
    } else {
      _removeSectionField(result, 'link', 'url');
      result
        ..['url'] = url
        ..['collection'] = collection
        ..['description'] = description
        ..['bookmarkStatus'] = bookmarkStatus
        ..['bookmarkFavorite'] = isFavorite;
    }
    return result;
  }

  MindmapNode toNode(MindmapNode node) => node.copyWith(
    tags: type == NodeType.bookmark ? tags : node.tags,
    data: toData(node.data),
  );

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (type == NodeType.resource)
      if (url.trim().isEmpty) 'Source is required.' else ...const <String>[]
    else ...[
      ...NodeValidation.url(url),
      if (type == NodeType.bookmark &&
          !const <String>{'inbox', 'reading', 'read'}.contains(bookmarkStatus))
        'Bookmark status is invalid.',
    ],
  ];
}

final class ResourceFolder {
  const ResourceFolder({
    required this.id,
    required this.name,
    this.parentId = '',
    this.extra = const <String, Object?>{},
  });

  factory ResourceFolder.fromJson(Object? value) {
    if (value is! Map) {
      return const ResourceFolder(id: '', name: '');
    }
    final map = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final extra = Map<String, Object?>.from(map)
      ..remove('id')
      ..remove('name')
      ..remove('parentId');
    return ResourceFolder(
      id: _text(map['id']).trim(),
      name: _text(map['name']).trim(),
      parentId: _text(map['parentId']).trim(),
      extra: extra,
    );
  }

  final String id;
  final String name;
  final String parentId;
  final Map<String, Object?> extra;

  ResourceFolder copyWith({String? name, String? parentId}) => ResourceFolder(
    id: id,
    name: name ?? this.name,
    parentId: parentId ?? this.parentId,
    extra: extra,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    ...extra,
    'id': id,
    'name': name,
    'parentId': parentId,
  };
}

final class ResourceAsset {
  const ResourceAsset({
    required this.id,
    required this.kind,
    this.label = '',
    this.location = '',
    this.attachmentId = '',
    this.mimeType = '',
    this.sizeBytes,
    this.fileName = '',
    this.extension = '',
    this.folderId = '',
    this.extra = const <String, Object?>{},
  });

  factory ResourceAsset.fromJson(Object? value) {
    if (value is! Map) {
      return const ResourceAsset(id: '', kind: '');
    }
    final map = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    final extra = Map<String, Object?>.from(map)
      ..remove('id')
      ..remove('kind')
      ..remove('label')
      ..remove('location')
      ..remove('attachmentId')
      ..remove('mimeType')
      ..remove('sizeBytes')
      ..remove('fileName')
      ..remove('extension')
      ..remove('folderId');
    return ResourceAsset(
      id: _text(map['id']).trim(),
      kind: _text(map['kind']).trim().toLowerCase(),
      label: _text(map['label']).trim(),
      location: _text(map['location']).trim(),
      attachmentId: _text(map['attachmentId']).trim(),
      mimeType: _text(map['mimeType']).trim().toLowerCase(),
      sizeBytes: _integer(map['sizeBytes']),
      fileName: _text(map['fileName']).trim(),
      extension: _normalizeResourceExtension(_text(map['extension'])),
      folderId: _text(map['folderId']).trim(),
      extra: extra,
    );
  }

  final String id;
  final String kind;
  final String label;
  final String location;
  final String attachmentId;
  final String mimeType;
  final int? sizeBytes;
  final String fileName;
  final String extension;
  final String folderId;
  final Map<String, Object?> extra;

  bool get isFile => kind == 'file';
  bool get isUrl => kind == 'url';
  bool get isImage =>
      mimeType.startsWith('image/') ||
      const <String>{'gif', 'jpg', 'jpeg', 'png', 'webp'}.contains(extension);

  String get displayName {
    if (label.trim().isNotEmpty) return label.trim();
    if (fileName.trim().isNotEmpty) return fileName.trim();
    if (isUrl) {
      final uri = Uri.tryParse(location);
      if (uri != null && uri.host.isNotEmpty) return uri.host;
    }
    if (location.trim().isNotEmpty) return _resourceBasename(location);
    return 'Untitled asset';
  }

  ResourceAsset copyWith({
    String? label,
    String? location,
    String? attachmentId,
    String? mimeType,
    int? sizeBytes,
    String? fileName,
    String? extension,
    String? folderId,
  }) => ResourceAsset(
    id: id,
    kind: kind,
    label: label ?? this.label,
    location: location ?? this.location,
    attachmentId: attachmentId ?? this.attachmentId,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    fileName: fileName ?? this.fileName,
    extension: extension ?? this.extension,
    folderId: folderId ?? this.folderId,
    extra: extra,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    ...extra,
    'id': id,
    'kind': kind,
    'label': label,
    'location': location,
    'attachmentId': attachmentId,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'fileName': fileName,
    'extension': _normalizeResourceExtension(extension),
    'folderId': folderId,
  };
}

final class ResourcePayload {
  const ResourcePayload({
    this.schemaVersion = 1,
    this.primaryAsset,
    this.relatedAssets = const <ResourceAsset>[],
    this.folders = const <ResourceFolder>[],
    this.folderPath = const <String>[],
    this.description = '',
    this.tags = const <String>[],
    this.extra = const <String, Object?>{},
  });

  factory ResourcePayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'resource');
    if (section.isNotEmpty) {
      final extra = Map<String, Object?>.from(section)
        ..remove('schemaVersion')
        ..remove('primaryAsset')
        ..remove('relatedAssets')
        ..remove('folders')
        ..remove('folderPath')
        ..remove('description')
        ..remove('tags');
      final primaryValue = section['primaryAsset'];
      var primary = primaryValue == null
          ? null
          : ResourceAsset.fromJson(primaryValue);
      var related = <ResourceAsset>[
        for (final item
            in section['relatedAssets'] is List
                ? section['relatedAssets'] as List
                : const <Object?>[])
          ResourceAsset.fromJson(item),
      ];
      final legacyPath = _strings(section['folderPath']);
      var folders = <ResourceFolder>[
        for (final item
            in section['folders'] is List
                ? section['folders'] as List
                : const <Object?>[])
          ResourceFolder.fromJson(item),
      ];
      if (folders.isEmpty && legacyPath.isNotEmpty) {
        folders = _resourceFoldersFromPath(legacyPath);
        final folderId = folders.last.id;
        primary = primary?.copyWith(folderId: folderId);
        related = <ResourceAsset>[
          for (final asset in related) asset.copyWith(folderId: folderId),
        ];
      }
      final primaryPath = primary == null
          ? const <String>[]
          : _resourceFolderPath(folders, primary.folderId);
      return ResourcePayload(
        schemaVersion: _integer(section['schemaVersion']) ?? 1,
        primaryAsset: primary,
        relatedAssets: related,
        folders: folders,
        folderPath: primaryPath.isEmpty ? legacyPath : primaryPath,
        description: _text(section['description'] ?? node.data['description']),
        tags: _strings(section['tags']).isEmpty
            ? node.tags
            : _strings(section['tags']),
        extra: extra,
      );
    }

    final source = _text(node.data['source']).trim();
    final category = _text(node.data['category']).trim();
    final folders = category.isEmpty
        ? const <ResourceFolder>[]
        : _resourceFoldersFromPath(<String>[category]);
    final folderId = folders.isEmpty ? '' : folders.last.id;
    final primary = source.isEmpty
        ? null
        : ResourceAsset(
            id: 'legacy-primary',
            kind: _isHttpUrl(source) ? 'url' : 'file',
            label: _resourceBasename(source),
            location: source,
            fileName: _isHttpUrl(source) ? '' : _resourceBasename(source),
            extension: _resourceExtension(source),
            folderId: folderId,
          );
    var relatedIndex = 0;
    final related = <ResourceAsset>[];
    for (final link in _strings(node.data['links'])) {
      final normalized = link.trim();
      if (!_isHttpUrl(normalized)) continue;
      relatedIndex += 1;
      related.add(
        ResourceAsset(
          id: 'legacy-related-$relatedIndex',
          kind: 'url',
          label: Uri.parse(normalized).host,
          location: normalized,
          folderId: folderId,
        ),
      );
    }
    return ResourcePayload(
      primaryAsset: primary,
      relatedAssets: related,
      folders: folders,
      folderPath: category.isEmpty ? const <String>[] : <String>[category],
      description: _text(node.data['description']),
      tags: node.tags,
    );
  }

  final int schemaVersion;
  final ResourceAsset? primaryAsset;
  final List<ResourceAsset> relatedAssets;
  final List<ResourceFolder> folders;
  final List<String> folderPath;
  final String description;
  final List<String> tags;
  final Map<String, Object?> extra;

  ResourcePayload copyWith({
    ResourceAsset? primaryAsset,
    bool clearPrimaryAsset = false,
    List<ResourceAsset>? relatedAssets,
    List<ResourceFolder>? folders,
    List<String>? folderPath,
    String? description,
    List<String>? tags,
  }) => ResourcePayload(
    schemaVersion: schemaVersion,
    primaryAsset: clearPrimaryAsset ? null : primaryAsset ?? this.primaryAsset,
    relatedAssets: relatedAssets ?? this.relatedAssets,
    folders: folders ?? this.folders,
    folderPath: folderPath ?? this.folderPath,
    description: description ?? this.description,
    tags: tags ?? this.tags,
    extra: extra,
  );

  ResourceFolder? folderById(String folderId) {
    for (final folder in folders) {
      if (folder.id == folderId) return folder;
    }
    return null;
  }

  List<String> folderPathFor(String folderId) =>
      _resourceFolderPath(folders, folderId);

  int folderDepth(String folderId) => folderPathFor(folderId).length;

  Map<String, Object?> toData(Map<String, Object?> data) {
    final primary = primaryAsset;
    final source = primary == null
        ? ''
        : primary.location.isNotEmpty
        ? primary.location
        : primary.fileName;
    final primaryFolderPath = primary == null
        ? const <String>[]
        : folderPathFor(primary.folderId);
    final compatibilityPath = primaryFolderPath.isEmpty
        ? folderPath
        : primaryFolderPath;
    return <String, Object?>{
      ...data,
      'resource': <String, Object?>{
        ..._section(data, 'resource'),
        ...extra,
        'schemaVersion': schemaVersion,
        'primaryAsset': primary?.toJson(),
        'relatedAssets': <Map<String, Object?>>[
          for (final asset in relatedAssets) asset.toJson(),
        ],
        'folders': <Map<String, Object?>>[
          for (final folder in folders) folder.toJson(),
        ],
        'folderPath': List<String>.from(compatibilityPath),
        'description': description,
        'tags': List<String>.from(tags),
      },
      'source': source,
      'category': compatibilityPath.isEmpty ? '' : compatibilityPath.first,
      'description': description,
      'links': <String>[
        for (final asset in relatedAssets)
          if (asset.isUrl) asset.location,
      ],
    };
  }

  MindmapNode toNode(MindmapNode node) => node.copyWith(
    tags: List<String>.unmodifiable(tags),
    data: toData(node.data),
  );

  List<String> validate({required String title}) {
    final errors = <String>[...NodeValidation.requiredTitle(title)];
    if (schemaVersion != 1) {
      errors.add('Resource schema version is not supported.');
    }
    final folderIds = <String>{};
    final folderById = <String, ResourceFolder>{};
    final siblingNames = <String>{};
    for (final folder in folders) {
      if (folder.id.isEmpty) {
        errors.add('Resource folder ID is required.');
      } else if (!folderIds.add(folder.id)) {
        errors.add('Resource folder IDs must be unique.');
      } else {
        folderById[folder.id] = folder;
      }
      if (folder.name.isEmpty) {
        errors.add('Resource folder name is required.');
      }
      if (folder.name.contains('/') || folder.name.contains('\\')) {
        errors.add('Resource folder name must not contain path separators.');
      }
      final siblingKey = '${folder.parentId}\u0000${folder.name.toLowerCase()}';
      if (!siblingNames.add(siblingKey)) {
        errors.add('Resource sibling folder names must be unique.');
      }
    }
    for (final folder in folders) {
      if (folder.parentId.isNotEmpty &&
          !folderById.containsKey(folder.parentId)) {
        errors.add('Resource folder parent is unavailable.');
        continue;
      }
      final seen = <String>{};
      var current = folder;
      var depth = 0;
      while (true) {
        if (!seen.add(current.id)) {
          errors.add('Resource folder hierarchy must not contain cycles.');
          break;
        }
        depth += 1;
        if (current.parentId.isEmpty) break;
        final parent = folderById[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      if (depth > 3) {
        errors.add('Resource folder supports at most three levels.');
      }
    }
    final primary = primaryAsset;
    final assets = <ResourceAsset>[?primary, ...relatedAssets];
    final ids = <String>{};
    for (final asset in assets) {
      if (asset.id.trim().isEmpty) {
        errors.add('Resource asset ID is required.');
      } else if (!ids.add(asset.id)) {
        errors.add('Resource asset IDs must be unique.');
      }
      if (asset.kind != 'file' && asset.kind != 'url') {
        errors.add('Resource asset kind is not supported.');
      }
      if (asset.isUrl && !_isHttpUrl(asset.location)) {
        errors.add('Resource URL must use HTTP or HTTPS.');
      }
      if (asset.isFile &&
          asset.attachmentId.trim().isEmpty &&
          asset.location.trim().isEmpty) {
        errors.add('Resource file is unavailable.');
      }
      if (asset.sizeBytes != null && asset.sizeBytes! < 0) {
        errors.add('Resource file size must not be negative.');
      }
      if (asset.mimeType.isNotEmpty && !asset.mimeType.contains('/')) {
        errors.add('Resource MIME type is invalid.');
      }
      if (asset.displayName == 'Untitled asset') {
        errors.add('Resource asset label is required.');
      }
      if (asset.folderId.isNotEmpty &&
          !folderById.containsKey(asset.folderId)) {
        errors.add('Resource asset folder is unavailable.');
      }
    }
    if (folderPath.length > 3) {
      errors.add('Resource folder supports at most three levels.');
    }
    String? previous;
    for (final segment in folderPath) {
      final normalized = segment.trim();
      if (normalized.isEmpty) {
        errors.add('Resource folder name is required.');
      }
      if (normalized.contains('/') || normalized.contains('\\')) {
        errors.add('Resource folder name must not contain path separators.');
      }
      if (previous != null &&
          previous.toLowerCase() == normalized.toLowerCase()) {
        errors.add('Adjacent Resource folder names must be different.');
      }
      previous = normalized;
    }
    for (final tag in tags) {
      if (tag.trim().isEmpty) errors.add('Resource tag must not be empty.');
    }
    return List<String>.unmodifiable(errors);
  }
}

List<ResourceFolder> _resourceFoldersFromPath(List<String> path) {
  final folders = <ResourceFolder>[];
  var parentId = '';
  for (var index = 0; index < path.length && index < 3; index++) {
    final name = path[index].trim();
    if (name.isEmpty) continue;
    final id = 'legacy-folder-${index + 1}';
    folders.add(ResourceFolder(id: id, name: name, parentId: parentId));
    parentId = id;
  }
  return folders;
}

List<String> _resourceFolderPath(
  List<ResourceFolder> folders,
  String folderId,
) {
  if (folderId.isEmpty) return const <String>[];
  final folderById = <String, ResourceFolder>{
    for (final folder in folders) folder.id: folder,
  };
  final reversed = <String>[];
  final seen = <String>{};
  var currentId = folderId;
  while (currentId.isNotEmpty && seen.add(currentId)) {
    final folder = folderById[currentId];
    if (folder == null) return const <String>[];
    reversed.add(folder.name);
    currentId = folder.parentId;
  }
  if (currentId.isNotEmpty) return const <String>[];
  return reversed.reversed.toList(growable: false);
}

String _normalizeResourceExtension(String value) =>
    value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

String _resourceExtension(String value) {
  final clean = value.split(RegExp(r'[?#]')).first;
  final name = _resourceBasename(clean);
  final index = name.lastIndexOf('.');
  return index <= 0 || index == name.length - 1
      ? ''
      : _normalizeResourceExtension(name.substring(index + 1));
}

String _resourceBasename(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  final uri = Uri.tryParse(normalized);
  final path = uri != null && uri.path.isNotEmpty ? uri.path : normalized;
  final segments = path.split('/').where((item) => item.isNotEmpty).toList();
  return segments.isEmpty ? normalized : segments.last;
}

final class TimerPayload {
  const TimerPayload({this.timer = const HybridTimerState()});

  factory TimerPayload.fromNode(MindmapNode node) {
    final nested = node.data['timer'];
    if (nested is Map && nested['mode'] is String) {
      return TimerPayload(
        timer: HybridTimerState.fromJson(nested.cast<String, Object?>()),
      );
    }
    final remaining = _integer(node.data['timerSeconds']);
    final initial = _integer(node.data['timerInitialSeconds']);
    final planned = initial ?? remaining ?? 1500;
    final elapsed = remaining == null
        ? 0
        : (planned - remaining).clamp(0, planned);
    return TimerPayload(
      timer: HybridTimerState(
        mode: TimerMode.countdown,
        status: elapsed > 0 ? TimerRunStatus.paused : TimerRunStatus.idle,
        plannedSeconds: planned,
        accumulatedSeconds: elapsed,
      ),
    );
  }

  final HybridTimerState timer;

  int? get timerSeconds => timer.mode == TimerMode.stopwatch
      ? timer.elapsedSecondsAt(DateTime.now())
      : timer.remainingSecondsAt(DateTime.now());
  int? get timerInitialSeconds =>
      timer.mode == TimerMode.stopwatch ? null : timer.activePlannedSeconds;

  Map<String, Object?> toData(Map<String, Object?> data) {
    final existing = data['timer'];
    final nested = existing is Map
        ? Map<String, Object?>.from(existing.cast<String, Object?>())
        : <String, Object?>{};
    nested.addAll(timer.toJson());
    return Map<String, Object?>.from(data)
      ..remove('durationMinutes')
      ..remove('elapsedSeconds')
      ..['timer'] = nested
      ..['timerSeconds'] = timerSeconds
      ..['timerInitialSeconds'] = timerInitialSeconds;
  }

  List<String> validate({required String title}) => [
    ...NodeValidation.requiredTitle(title),
    if (timer.label.length > 80) 'Timer label must be 80 characters or less.',
    if (timer.isBounded &&
        (timer.activePlannedSeconds < 1 || timer.activePlannedSeconds > 86400))
      'Timer duration must be between 1 second and 24 hours.',
    if (timer.cycleTarget < 1 || timer.cycleTarget > 12)
      'Focus cycle target must be between 1 and 12.',
    if (timer.accumulatedSeconds < 0)
      'Elapsed timer duration cannot be negative.',
    for (final item in timer.distractions)
      if (item.text.length > 160)
        'Distraction notes must be 160 characters or less.',
  ];
}

enum AudioSourceType { none, attachment, url, legacy }

final class AudioTranscriptSegment {
  const AudioTranscriptSegment({
    required this.id,
    required this.startMilliseconds,
    required this.endMilliseconds,
    required this.text,
  });
  factory AudioTranscriptSegment.fromMap(Map<String, Object?> map) =>
      AudioTranscriptSegment(
        id: _text(map['id']),
        startMilliseconds: _integer(map['startMilliseconds']) ?? 0,
        endMilliseconds: _integer(map['endMilliseconds']) ?? 0,
        text: _text(map['text']),
      );
  final String id;
  final int startMilliseconds;
  final int endMilliseconds;
  final String text;
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'startMilliseconds': startMilliseconds,
    'endMilliseconds': endMilliseconds,
    'text': text,
  };
}

final class AudioPayload {
  const AudioPayload({
    this.audioPath = '',
    this.audioDuration = '',
    this.audioTranscript = '',
    this.sourceType = AudioSourceType.none,
    this.attachmentId = '',
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.remoteUrl = '',
    this.durationMilliseconds = 0,
    this.transcriptText = '',
    this.transcriptSegments = const <AudioTranscriptSegment>[],
    this.transcriptionStatus = 'idle',
    this.transcriptionError = '',
  });
  factory AudioPayload.fromNode(MindmapNode node) {
    final legacyPath = _text(node.data['audioPath']);
    final attachmentId = _text(node.data['audioAttachmentId']);
    final remoteUrl = _text(node.data['audioRemoteUrl']);
    final storedType = _text(node.data['audioSourceType']);
    final sourceType = switch (storedType) {
      'attachment' => AudioSourceType.attachment,
      'url' => AudioSourceType.url,
      'legacy' => AudioSourceType.legacy,
      _ when attachmentId.isNotEmpty => AudioSourceType.attachment,
      _ when remoteUrl.isNotEmpty || _isHttpsAudioUrl(legacyPath) =>
        AudioSourceType.url,
      _ when legacyPath.isNotEmpty => AudioSourceType.legacy,
      _ => AudioSourceType.none,
    };
    final legacyDuration = _text(node.data['audioDuration']);
    final legacyTranscript = _text(node.data['audioTranscript']);
    return AudioPayload(
      audioPath: legacyPath,
      audioDuration: legacyDuration,
      audioTranscript: legacyTranscript,
      sourceType: sourceType,
      attachmentId: attachmentId,
      fileName: _text(node.data['audioFileName']),
      mimeType: _text(node.data['audioMimeType']),
      sizeBytes: _integer(node.data['audioSizeBytes']) ?? 0,
      remoteUrl: remoteUrl.isNotEmpty
          ? remoteUrl
          : sourceType == AudioSourceType.url
          ? legacyPath
          : '',
      durationMilliseconds:
          _integer(node.data['audioDurationMilliseconds']) ??
          _parseAudioDuration(legacyDuration),
      transcriptText: _text(
        node.data['audioTranscriptText'],
        fallback: legacyTranscript,
      ),
      transcriptSegments: <AudioTranscriptSegment>[
        for (final item in _maps(node.data['audioTranscriptSegments']))
          AudioTranscriptSegment.fromMap(item),
      ],
      transcriptionStatus: _text(
        node.data['audioTranscriptionStatus'],
        fallback: 'idle',
      ),
      transcriptionError: _text(node.data['audioTranscriptionError']),
    );
  }
  final String audioPath;
  final String audioDuration;
  final String audioTranscript;
  final AudioSourceType sourceType;
  final String attachmentId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String remoteUrl;
  final int durationMilliseconds;
  final String transcriptText;
  final List<AudioTranscriptSegment> transcriptSegments;
  final String transcriptionStatus;
  final String transcriptionError;

  AudioPayload copyWith({
    AudioSourceType? sourceType,
    String? attachmentId,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? remoteUrl,
    int? durationMilliseconds,
    String? transcriptText,
    List<AudioTranscriptSegment>? transcriptSegments,
    String? transcriptionStatus,
    String? transcriptionError,
  }) {
    final nextDuration = durationMilliseconds ?? this.durationMilliseconds;
    final nextTranscript = transcriptText ?? this.transcriptText;
    final nextType = sourceType ?? this.sourceType;
    final nextFileName = fileName ?? this.fileName;
    final nextRemoteUrl = remoteUrl ?? this.remoteUrl;
    return AudioPayload(
      audioPath: nextType == AudioSourceType.url ? nextRemoteUrl : nextFileName,
      audioDuration: _formatAudioDuration(nextDuration),
      audioTranscript: nextTranscript,
      sourceType: nextType,
      attachmentId: attachmentId ?? this.attachmentId,
      fileName: nextFileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      remoteUrl: nextRemoteUrl,
      durationMilliseconds: nextDuration,
      transcriptText: nextTranscript,
      transcriptSegments: transcriptSegments ?? this.transcriptSegments,
      transcriptionStatus: transcriptionStatus ?? this.transcriptionStatus,
      transcriptionError: transcriptionError ?? this.transcriptionError,
    );
  }

  Map<String, Object?> toData(Map<String, Object?> data) {
    final result = Map<String, Object?>.from(data)
      ..remove('source')
      ..remove('transcript')
      ..['audioPath'] = sourceType == AudioSourceType.url
          ? remoteUrl
          : fileName.isNotEmpty
          ? fileName
          : audioPath
      ..['audioDuration'] = durationMilliseconds > 0
          ? _formatAudioDuration(durationMilliseconds)
          : audioDuration
      ..['audioTranscript'] = transcriptText.isNotEmpty
          ? transcriptText
          : audioTranscript
      ..['audioSourceType'] = sourceType.name
      ..['audioAttachmentId'] = attachmentId
      ..['audioFileName'] = fileName
      ..['audioMimeType'] = mimeType
      ..['audioSizeBytes'] = sizeBytes
      ..['audioRemoteUrl'] = remoteUrl
      ..['audioDurationMilliseconds'] = durationMilliseconds
      ..['audioTranscriptText'] = transcriptText
      ..['audioTranscriptSegments'] = <Map<String, Object?>>[
        for (final segment in transcriptSegments) segment.toJson(),
      ]
      ..['audioTranscriptionStatus'] = transcriptionStatus
      ..['audioTranscriptionError'] = transcriptionError;
    return result;
  }

  List<String> validate({required String title}) {
    final errors = <String>[...NodeValidation.requiredTitle(title)];
    if (sourceType == AudioSourceType.none) {
      errors.add('Audio source is required.');
    }
    if (sourceType == AudioSourceType.attachment && attachmentId.isEmpty) {
      errors.add('Audio attachment is required.');
    }
    if (sourceType == AudioSourceType.url && !_isHttpsAudioUrl(remoteUrl)) {
      errors.add('Audio URL must use HTTPS.');
    }
    if (sizeBytes > 25 * 1024 * 1024) {
      errors.add('Audio files must be 25 MB or less.');
    }
    var previousStart = -1;
    for (final segment in transcriptSegments) {
      if (segment.startMilliseconds < previousStart) {
        errors.add('Transcript segments must be ordered by start time.');
        break;
      }
      if (segment.startMilliseconds < 0 ||
          segment.endMilliseconds < segment.startMilliseconds) {
        errors.add('Transcript segment timestamps are invalid.');
        break;
      }
      previousStart = segment.startMilliseconds;
    }
    return errors;
  }
}

bool _isHttpsAudioUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

int _parseAudioDuration(String value) {
  final parts = value.trim().split(':');
  if (parts.length != 2) return 0;
  final minutes = int.tryParse(parts.first);
  final seconds = int.tryParse(parts.last);
  if (minutes == null || seconds == null || seconds < 0 || seconds > 59) {
    return 0;
  }
  return (minutes * 60 + seconds) * 1000;
}

String _formatAudioDuration(int milliseconds) {
  final totalSeconds = milliseconds <= 0 ? 0 : milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

const int maxDrawingElements = 1000;
const int maxDrawingStrokes = 1000;
const int maxDrawingPointsPerItem = 10000;
const int maxDrawingPointsTotal = 100000;
const int maxImageAnnotations = 500;
const int maxDrawingTextUtf8BytesPerItem = 64 * 1024;
const int maxDrawingTextUtf8BytesTotal = 1024 * 1024;
const int maxDrawingSerializedPayloadBytes = 8 * 1024 * 1024;

const Set<String> canvasBackgrounds = <String>{'plain', 'grid', 'dots'};
const Set<String> canvasTools = <String>{
  'select',
  'pen',
  'eraser',
  'text',
  'sticky',
  'rectangle',
  'ellipse',
  'arrow',
};
const Set<String> canvasColorTokens = <String>{
  'violet',
  'blue',
  'green',
  'amber',
  'rose',
  'neutral',
};

final class CanvasPoint {
  const CanvasPoint(this.x, this.y);

  factory CanvasPoint.fromMap(Map<String, Object?> map) => CanvasPoint(
    _number(map['x']) ?? double.nan,
    _number(map['y']) ?? double.nan,
  );

  final double x;
  final double y;

  CanvasPoint copyWith({double? x, double? y}) =>
      CanvasPoint(x ?? this.x, y ?? this.y);

  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};
}

sealed class CanvasElement {
  const CanvasElement({required this.id, required this.color});

  factory CanvasElement.fromMap(Map<String, Object?> map) {
    final id = _text(map['id']);
    final color = _text(map['color'], fallback: 'violet');
    return switch (_text(map['type'])) {
      'stroke' => CanvasStroke(
        id: id,
        color: color,
        width: _number(map['width']) ?? 2,
        points: <CanvasPoint>[
          for (final point in _maps(map['points'])) CanvasPoint.fromMap(point),
        ],
      ),
      'text' => CanvasTextElement(
        id: id,
        color: color,
        position: CanvasPoint.fromMap(_section(map, 'position')),
        text: _text(map['text']),
        fontSize: _number(map['fontSize']) ?? 16,
      ),
      'sticky' => CanvasStickyElement(
        id: id,
        color: color,
        position: CanvasPoint.fromMap(_section(map, 'position')),
        width: _number(map['width']) ?? 0.24,
        height: _number(map['height']) ?? 0.18,
        text: _text(map['text']),
        backgroundColor: _text(map['backgroundColor'], fallback: 'amber'),
      ),
      'shape' => CanvasShapeElement(
        id: id,
        color: color,
        shape: _text(map['shape']),
        start: CanvasPoint.fromMap(_section(map, 'start')),
        end: CanvasPoint.fromMap(_section(map, 'end')),
        width: _number(map['width']) ?? 2,
        fillColor: _text(map['fillColor']),
      ),
      'arrow' => CanvasArrowElement(
        id: id,
        color: color,
        start: CanvasPoint.fromMap(_section(map, 'start')),
        end: CanvasPoint.fromMap(_section(map, 'end')),
        width: _number(map['width']) ?? 2,
      ),
      _ => CanvasUnknownElement(
        id: id,
        color: color,
        raw: Map<String, Object?>.unmodifiable(map),
      ),
    };
  }

  final String id;
  final String color;
  String get type;
  Map<String, Object?> toJson();
}

final class CanvasStroke extends CanvasElement {
  const CanvasStroke({
    required super.id,
    required super.color,
    required this.points,
    this.width = 2,
  });

  final List<CanvasPoint> points;
  final double width;

  @override
  String get type => 'stroke';

  CanvasStroke copyWith({
    String? id,
    String? color,
    List<CanvasPoint>? points,
    double? width,
  }) => CanvasStroke(
    id: id ?? this.id,
    color: color ?? this.color,
    points: points ?? this.points,
    width: width ?? this.width,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'color': color,
    'width': width,
    'points': <Map<String, Object?>>[
      for (final point in points) point.toJson(),
    ],
  };
}

final class CanvasTextElement extends CanvasElement {
  const CanvasTextElement({
    required super.id,
    required super.color,
    required this.position,
    required this.text,
    this.fontSize = 16,
  });

  final CanvasPoint position;
  final String text;
  final double fontSize;

  @override
  String get type => 'text';

  CanvasTextElement copyWith({
    String? id,
    String? color,
    CanvasPoint? position,
    String? text,
    double? fontSize,
  }) => CanvasTextElement(
    id: id ?? this.id,
    color: color ?? this.color,
    position: position ?? this.position,
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'color': color,
    'position': position.toJson(),
    'text': text,
    'fontSize': fontSize,
  };
}

final class CanvasStickyElement extends CanvasElement {
  const CanvasStickyElement({
    required super.id,
    required super.color,
    required this.position,
    required this.text,
    this.width = 0.24,
    this.height = 0.18,
    this.backgroundColor = 'amber',
  });

  final CanvasPoint position;
  final String text;
  final double width;
  final double height;
  final String backgroundColor;

  @override
  String get type => 'sticky';

  CanvasStickyElement copyWith({
    String? id,
    String? color,
    CanvasPoint? position,
    String? text,
    double? width,
    double? height,
    String? backgroundColor,
  }) => CanvasStickyElement(
    id: id ?? this.id,
    color: color ?? this.color,
    position: position ?? this.position,
    text: text ?? this.text,
    width: width ?? this.width,
    height: height ?? this.height,
    backgroundColor: backgroundColor ?? this.backgroundColor,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'color': color,
    'position': position.toJson(),
    'text': text,
    'width': width,
    'height': height,
    'backgroundColor': backgroundColor,
  };
}

final class CanvasShapeElement extends CanvasElement {
  const CanvasShapeElement({
    required super.id,
    required super.color,
    required this.shape,
    required this.start,
    required this.end,
    this.width = 2,
    this.fillColor = '',
  });

  final String shape;
  final CanvasPoint start;
  final CanvasPoint end;
  final double width;
  final String fillColor;

  @override
  String get type => 'shape';

  CanvasShapeElement copyWith({
    String? id,
    String? color,
    String? shape,
    CanvasPoint? start,
    CanvasPoint? end,
    double? width,
    String? fillColor,
  }) => CanvasShapeElement(
    id: id ?? this.id,
    color: color ?? this.color,
    shape: shape ?? this.shape,
    start: start ?? this.start,
    end: end ?? this.end,
    width: width ?? this.width,
    fillColor: fillColor ?? this.fillColor,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'color': color,
    'shape': shape,
    'start': start.toJson(),
    'end': end.toJson(),
    'width': width,
    'fillColor': fillColor,
  };
}

final class CanvasArrowElement extends CanvasElement {
  const CanvasArrowElement({
    required super.id,
    required super.color,
    required this.start,
    required this.end,
    this.width = 2,
  });

  final CanvasPoint start;
  final CanvasPoint end;
  final double width;

  @override
  String get type => 'arrow';

  CanvasArrowElement copyWith({
    String? id,
    String? color,
    CanvasPoint? start,
    CanvasPoint? end,
    double? width,
  }) => CanvasArrowElement(
    id: id ?? this.id,
    color: color ?? this.color,
    start: start ?? this.start,
    end: end ?? this.end,
    width: width ?? this.width,
  );

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'type': type,
    'color': color,
    'start': start.toJson(),
    'end': end.toJson(),
    'width': width,
  };
}

final class CanvasUnknownElement extends CanvasElement {
  const CanvasUnknownElement({
    required super.id,
    required super.color,
    this.raw = const <String, Object?>{},
  });

  final Map<String, Object?> raw;

  @override
  String get type => 'unknown';

  @override
  Map<String, Object?> toJson() => raw.isEmpty
      ? <String, Object?>{'id': id, 'type': type, 'color': color}
      : Map<String, Object?>.from(raw);
}

final class CanvasPayload {
  const CanvasPayload({
    this.schemaVersion = 1,
    this.background = 'plain',
    this.elements = const <CanvasElement>[],
    this.elementGroups = const <String, String>{},
    this.activeTool = 'select',
    this.penColor = 'violet',
    this.penWidth = 3,
    this.strokes = const <String>[],
    this.blocks = const CanvasBlockDocument(),
    this.viewMode = 'visual',
  });

  factory CanvasPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'canvas');
    final structured = <CanvasElement>[
      for (final item in _maps(section['elements']))
        CanvasElement.fromMap(item),
    ];
    final legacyStrokes = _strings(node.data['strokes']);
    final migrated = structured.isNotEmpty
        ? structured
        : <CanvasElement>[
            for (final entry in legacyStrokes.indexed)
              ?_legacyCanvasStroke(entry.$2, entry.$1),
          ];
    return CanvasPayload(
      schemaVersion: _integer(section['schemaVersion']) ?? 1,
      background: _text(
        section['background'] ?? node.data['background'],
        fallback: 'plain',
      ),
      elements: migrated,
      elementGroups: <String, String>{
        for (final entry in _section(section, 'elementGroups').entries)
          if (_text(entry.value).trim().isNotEmpty)
            entry.key: _text(entry.value).trim(),
      },
      activeTool: _text(section['activeTool'], fallback: 'select'),
      penColor: _text(section['penColor'], fallback: 'violet'),
      penWidth: _number(section['penWidth']) ?? 3,
      strokes: legacyStrokes,
      blocks: CanvasBlockDocument.fromJson(section['blocks']),
      viewMode: _text(section['viewMode'], fallback: 'visual'),
    );
  }

  final int schemaVersion;
  final String background;
  final List<CanvasElement> elements;
  final Map<String, String> elementGroups;
  final String activeTool;
  final String penColor;
  final double penWidth;
  final List<String> strokes;
  final CanvasBlockDocument blocks;
  final String viewMode;

  int get drawingCount => elements.whereType<CanvasStroke>().length;
  int get textCount =>
      elements.whereType<CanvasTextElement>().length +
      elements.whereType<CanvasStickyElement>().length;
  int get shapeCount =>
      elements.whereType<CanvasShapeElement>().length +
      elements.whereType<CanvasArrowElement>().length;

  CanvasPayload copyWith({
    int? schemaVersion,
    String? background,
    List<CanvasElement>? elements,
    Map<String, String>? elementGroups,
    String? activeTool,
    String? penColor,
    double? penWidth,
    List<String>? strokes,
    CanvasBlockDocument? blocks,
    String? viewMode,
  }) {
    final nextElements = elements ?? this.elements;
    final ids = nextElements.map((element) => element.id).toSet();
    final groups = elementGroups ?? this.elementGroups;
    return CanvasPayload(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      background: background ?? this.background,
      elements: nextElements,
      elementGroups: <String, String>{
        for (final entry in groups.entries)
          if (ids.contains(entry.key) && entry.value.trim().isNotEmpty)
            entry.key: entry.value.trim(),
      },
      activeTool: activeTool ?? this.activeTool,
      penColor: penColor ?? this.penColor,
      penWidth: penWidth ?? this.penWidth,
      strokes: elements != null && nextElements.isEmpty
          ? const <String>[]
          : strokes ?? this.strokes,
      blocks: blocks ?? this.blocks,
      viewMode: viewMode ?? this.viewMode,
    );
  }

  Map<String, Object?> toData(Map<String, Object?> data) {
    final legacy = <String>[
      for (final stroke in elements.whereType<CanvasStroke>())
        _encodeLegacyCanvasStroke(stroke),
    ];
    return <String, Object?>{
      ..._mergeSection(data, 'canvas', <String, Object?>{
        'schemaVersion': schemaVersion,
        'background': background,
        'elements': <Map<String, Object?>>[
          for (final element in elements) element.toJson(),
        ],
        'elementGroups': elementGroups,
        'activeTool': activeTool,
        'penColor': penColor,
        'penWidth': penWidth,
        'blocks': blocks.toJson(),
        'viewMode': viewMode,
      }),
      'strokes': elements.isEmpty ? strokes : legacy,
      'background': background,
    };
  }

  List<String> validate({required String title}) {
    final serializedBytes = _serializedPayloadBytes(
      toData(const <String, Object?>{}),
    );
    final strokeCount = elements.whereType<CanvasStroke>().length;
    final pointCount = elements.whereType<CanvasStroke>().fold<int>(
      0,
      (total, stroke) => total + stroke.points.length,
    );
    final textBytes = elements.fold<int>(0, (total, element) {
      return total +
          switch (element) {
            CanvasTextElement() => utf8.encode(element.text).length,
            CanvasStickyElement() => utf8.encode(element.text).length,
            _ => 0,
          };
    });
    final errors = <String>[
      ...NodeValidation.requiredTitle(title),
      if (elements.length > maxDrawingElements)
        'Canvas contains too many elements.',
      if (strokeCount > maxDrawingStrokes) 'Canvas contains too many strokes.',
      if (pointCount > maxDrawingPointsTotal)
        'Canvas contains too many points.',
      if (textBytes > maxDrawingTextUtf8BytesTotal)
        'Canvas text exceeds size limit.',
      if (serializedBytes > maxDrawingSerializedPayloadBytes)
        'Canvas payload exceeds size limit.',
      if (schemaVersion != 1) 'Canvas schema version is unsupported.',
      if (!canvasBackgrounds.contains(background))
        'Canvas background is invalid.',
      if (!canvasTools.contains(activeTool)) 'Canvas tool is invalid.',
      if (!canvasColorTokens.contains(penColor)) 'Canvas color is invalid.',
      if (!penWidth.isFinite || penWidth <= 0) 'Canvas pen width is invalid.',
      if (!const <String>{'visual', 'blocks', 'split'}.contains(viewMode))
        'Canvas view mode is invalid.',
      ...blocks.validate(),
    ];
    final ids = <String>{};
    for (final element in elements) {
      if (element.id.trim().isEmpty) {
        errors.add('Canvas element ID is required.');
      }
      if (!ids.add(element.id)) {
        errors.add('Canvas element IDs must be unique.');
      }
      if (!canvasColorTokens.contains(element.color)) {
        errors.add('Canvas element color is invalid.');
      }
      switch (element) {
        case CanvasStroke():
          if (element.points.length < 2) {
            errors.add('Canvas stroke needs at least two points.');
          }
          if (element.points.length > maxDrawingPointsPerItem) {
            errors.add('Canvas stroke contains too many points.');
          }
          if (!element.width.isFinite || element.width <= 0) {
            errors.add('Canvas stroke width is invalid.');
          }
          for (final point in element.points) {
            if (!_validCanvasPoint(point)) {
              errors.add('Canvas point must be normalized.');
            }
          }
        case CanvasTextElement():
          if (!_validCanvasPoint(element.position)) {
            errors.add('Canvas point must be normalized.');
          }
          if (element.text.trim().isEmpty) {
            errors.add('Canvas text is required.');
          }
          if (utf8.encode(element.text).length >
              maxDrawingTextUtf8BytesPerItem) {
            errors.add('Canvas text exceeds item size limit.');
          }
          if (!element.fontSize.isFinite || element.fontSize <= 0) {
            errors.add('Canvas text size is invalid.');
          }
        case CanvasStickyElement():
          if (!_validCanvasPoint(element.position)) {
            errors.add('Canvas point must be normalized.');
          }
          if (element.text.trim().isEmpty) {
            errors.add('Canvas sticky text is required.');
          }
          if (utf8.encode(element.text).length >
              maxDrawingTextUtf8BytesPerItem) {
            errors.add('Canvas sticky text exceeds item size limit.');
          }
          if (!element.width.isFinite ||
              !element.height.isFinite ||
              element.width <= 0 ||
              element.height <= 0) {
            errors.add('Canvas sticky size is invalid.');
          }
          if (!canvasColorTokens.contains(element.backgroundColor)) {
            errors.add('Canvas sticky color is invalid.');
          }
        case CanvasShapeElement():
          if (element.shape != 'rectangle' && element.shape != 'ellipse') {
            errors.add('Canvas shape is invalid.');
          }
          if (!_validCanvasPoint(element.start) ||
              !_validCanvasPoint(element.end)) {
            errors.add('Canvas point must be normalized.');
          }
        case CanvasArrowElement():
          if (!_validCanvasPoint(element.start) ||
              !_validCanvasPoint(element.end)) {
            errors.add('Canvas point must be normalized.');
          }
        case CanvasUnknownElement():
          errors.add('Canvas element type is unsupported.');
      }
    }
    if (elementGroups.keys.any((id) => !ids.contains(id)) ||
        elementGroups.values.any((group) => group.trim().isEmpty)) {
      errors.add('Canvas element group is invalid.');
    }
    return List<String>.unmodifiable(errors);
  }
}

int _serializedPayloadBytes(Object? payload) {
  try {
    return utf8.encode(jsonEncode(payload)).length;
  } on JsonUnsupportedObjectError {
    return maxDrawingSerializedPayloadBytes + 1;
  }
}

bool _validCanvasPoint(CanvasPoint point) =>
    point.x.isFinite &&
    point.y.isFinite &&
    point.x >= 0 &&
    point.x <= 1 &&
    point.y >= 0 &&
    point.y <= 1;

CanvasStroke? _legacyCanvasStroke(String value, int index) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      final points = <CanvasPoint>[
        for (final item in decoded)
          if (item is Map)
            CanvasPoint.fromMap(<String, Object?>{
              for (final entry in item.entries)
                if (entry.key is String) entry.key as String: entry.value,
            }),
      ];
      if (points.length >= 2 && points.every(_validCanvasPoint)) {
        return CanvasStroke(
          id: 'legacy-stroke-${index + 1}',
          color: 'violet',
          points: points,
        );
      }
    }
  } on FormatException {
    final points = <CanvasPoint>[];
    for (final pair in value.split(';')) {
      final coordinates = pair.split(',');
      if (coordinates.length != 2) return null;
      final x = double.tryParse(coordinates[0]);
      final y = double.tryParse(coordinates[1]);
      if (x == null || y == null) return null;
      points.add(CanvasPoint(x, y));
    }
    if (points.length >= 2 && points.every(_validCanvasPoint)) {
      return CanvasStroke(
        id: 'legacy-stroke-${index + 1}',
        color: 'violet',
        points: points,
      );
    }
  }
  return null;
}

String _encodeLegacyCanvasStroke(CanvasStroke stroke) => jsonEncode(
  <Map<String, Object?>>[for (final point in stroke.points) point.toJson()],
);

enum ImageFitMode { contain, cover, fill, fitWidth, fitHeight }

enum ImageFilterPreset { none, vivid, mono, warm, cool }

enum ImageAnnotationType { text, arrow, rectangle, freehand }

final class ImageAnnotation {
  const ImageAnnotation({
    required this.id,
    required this.type,
    this.text = '',
    this.color = 0xFFFF3BCE,
    this.strokeWidth = 3,
    this.positionX = 0.1,
    this.positionY = 0.1,
    this.width = 0.24,
    this.height = 0.14,
    this.rotationDegrees = 0,
    this.points = const <CanvasPoint>[],
  });

  factory ImageAnnotation.fromMap(Map<String, Object?> map) => ImageAnnotation(
    id: _text(map['id']),
    type:
        ImageAnnotationType.values
            .where((value) => value.name == _text(map['type']))
            .firstOrNull ??
        ImageAnnotationType.text,
    text: _text(map['text']),
    color: _integer(map['color']) ?? 0xFFFF3BCE,
    strokeWidth: (_number(map['strokeWidth']) ?? 3).clamp(1, 24),
    positionX: (_number(map['positionX']) ?? 0.1).clamp(0, 1),
    positionY: (_number(map['positionY']) ?? 0.1).clamp(0, 1),
    width: (_number(map['width']) ?? 0.24).clamp(0.05, 1),
    height: (_number(map['height']) ?? 0.14).clamp(0.05, 1),
    rotationDegrees: (_number(map['rotationDegrees']) ?? 0).clamp(-180, 180),
    points: <CanvasPoint>[
      for (final point in _maps(map['points'])) CanvasPoint.fromMap(point),
    ].where(_validCanvasPoint).toList(growable: false),
  );

  final String id;
  final ImageAnnotationType type;
  final String text;
  final int color;
  final double strokeWidth;
  final double positionX;
  final double positionY;
  final double width;
  final double height;
  final double rotationDegrees;
  final List<CanvasPoint> points;

  ImageAnnotation copyWith({
    ImageAnnotationType? type,
    String? text,
    int? color,
    double? strokeWidth,
    double? positionX,
    double? positionY,
    double? width,
    double? height,
    double? rotationDegrees,
    List<CanvasPoint>? points,
  }) => ImageAnnotation(
    id: id,
    type: type ?? this.type,
    text: text ?? this.text,
    color: color ?? this.color,
    strokeWidth: (strokeWidth ?? this.strokeWidth).clamp(1, 24),
    positionX: (positionX ?? this.positionX).clamp(0, 1),
    positionY: (positionY ?? this.positionY).clamp(0, 1),
    width: (width ?? this.width).clamp(0.05, 1),
    height: (height ?? this.height).clamp(0.05, 1),
    rotationDegrees: (rotationDegrees ?? this.rotationDegrees).clamp(-180, 180),
    points: points ?? this.points,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.name,
    'text': text,
    'color': color,
    'strokeWidth': strokeWidth,
    'positionX': positionX,
    'positionY': positionY,
    'width': width,
    'height': height,
    'rotationDegrees': rotationDegrees,
    if (points.isNotEmpty)
      'points': <Map<String, Object?>>[
        for (final point in points) point.toJson(),
      ],
  };
}

final class ImagePayload {
  const ImagePayload({
    this.attachmentId = '',
    this.url = '',
    this.mimeType = '',
    this.fileName = '',
    this.caption = '',
    this.altText = '',
    this.fitMode = ImageFitMode.contain,
    this.width,
    this.height,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.byteLength,
    this.originalAttachmentId = '',
    this.sourceUrl = '',
    this.tags = const <String>[],
    this.rotationQuarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.filter = ImageFilterPreset.none,
    this.annotations = const <ImageAnnotation>[],
  });
  factory ImagePayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'image');
    return ImagePayload(
      attachmentId: _text(section['attachmentId']),
      url: _text(section['url']),
      mimeType: _text(section['mimeType']),
      fileName: _text(section['fileName']),
      caption: _text(section['caption']),
      altText: _text(section['altText']),
      fitMode:
          ImageFitMode.values
              .where((value) => value.name == _text(section['fitMode']))
              .firstOrNull ??
          ImageFitMode.contain,
      width: _positiveInteger(section['width']),
      height: _positiveInteger(section['height']),
      thumbnailWidth: _positiveInteger(section['thumbnailWidth']),
      thumbnailHeight: _positiveInteger(section['thumbnailHeight']),
      byteLength: _positiveInteger(section['byteLength']),
      originalAttachmentId: _text(section['originalAttachmentId']),
      sourceUrl: _text(section['sourceUrl']),
      tags: _strings(section['tags']),
      rotationQuarterTurns:
          (_integer(section['rotationQuarterTurns']) ?? 0) % 4,
      flipHorizontal: section['flipHorizontal'] == true,
      flipVertical: section['flipVertical'] == true,
      brightness: (_number(section['brightness']) ?? 0).clamp(-1, 1),
      contrast: (_number(section['contrast']) ?? 0).clamp(-1, 1),
      saturation: (_number(section['saturation']) ?? 0).clamp(-1, 1),
      filter:
          ImageFilterPreset.values
              .where((value) => value.name == _text(section['filter']))
              .firstOrNull ??
          ImageFilterPreset.none,
      annotations: <ImageAnnotation>[
        for (final item in _maps(section['annotations']))
          ImageAnnotation.fromMap(item),
      ].where((item) => item.id.isNotEmpty).toList(growable: false),
    );
  }
  final String attachmentId;
  final String url;
  final String mimeType;
  final String fileName;
  final String caption;
  final String altText;
  final ImageFitMode fitMode;
  final int? width;
  final int? height;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final int? byteLength;
  final String originalAttachmentId;
  final String sourceUrl;
  final List<String> tags;
  final int rotationQuarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final double brightness;
  final double contrast;
  final double saturation;
  final ImageFilterPreset filter;
  final List<ImageAnnotation> annotations;
  bool get hasLocalAttachment => attachmentId.trim().isNotEmpty;
  bool get hasRemoteUrl => url.trim().isNotEmpty;
  ImagePayload copyWith({
    String? attachmentId,
    String? url,
    String? mimeType,
    String? fileName,
    String? caption,
    String? altText,
    ImageFitMode? fitMode,
    int? width,
    int? height,
    int? thumbnailWidth,
    int? thumbnailHeight,
    int? byteLength,
    bool clearAttachment = false,
    bool clearUrl = false,
    bool clearMediaMetadata = false,
    String? originalAttachmentId,
    String? sourceUrl,
    List<String>? tags,
    int? rotationQuarterTurns,
    bool? flipHorizontal,
    bool? flipVertical,
    double? brightness,
    double? contrast,
    double? saturation,
    ImageFilterPreset? filter,
    List<ImageAnnotation>? annotations,
  }) => ImagePayload(
    attachmentId: clearAttachment ? '' : attachmentId ?? this.attachmentId,
    url: clearUrl ? '' : url ?? this.url,
    mimeType: clearMediaMetadata ? '' : mimeType ?? this.mimeType,
    fileName: clearMediaMetadata ? '' : fileName ?? this.fileName,
    caption: caption ?? this.caption,
    altText: altText ?? this.altText,
    fitMode: fitMode ?? this.fitMode,
    width: clearMediaMetadata ? null : width ?? this.width,
    height: clearMediaMetadata ? null : height ?? this.height,
    thumbnailWidth: clearMediaMetadata
        ? null
        : thumbnailWidth ?? this.thumbnailWidth,
    thumbnailHeight: clearMediaMetadata
        ? null
        : thumbnailHeight ?? this.thumbnailHeight,
    byteLength: clearMediaMetadata ? null : byteLength ?? this.byteLength,
    originalAttachmentId: clearMediaMetadata
        ? ''
        : originalAttachmentId ?? this.originalAttachmentId,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    tags: tags ?? this.tags,
    rotationQuarterTurns:
        (rotationQuarterTurns ?? this.rotationQuarterTurns) % 4,
    flipHorizontal: flipHorizontal ?? this.flipHorizontal,
    flipVertical: flipVertical ?? this.flipVertical,
    brightness: (brightness ?? this.brightness).clamp(-1, 1),
    contrast: (contrast ?? this.contrast).clamp(-1, 1),
    saturation: (saturation ?? this.saturation).clamp(-1, 1),
    filter: filter ?? this.filter,
    annotations: annotations ?? this.annotations,
  );
  Map<String, Object?> toData([Map<String, Object?> existingData = const {}]) {
    final sanitized = Map<String, Object?>.of(existingData)
      ..remove('bytes')
      ..remove('base64')
      ..remove('imageBytes')
      ..remove('imageBase64');
    return _mergeSection(sanitized, 'image', {
      'attachmentId': attachmentId,
      'url': url,
      'mimeType': mimeType,
      'fileName': fileName,
      'caption': caption,
      'altText': altText,
      'fitMode': fitMode.name,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (thumbnailWidth != null) 'thumbnailWidth': thumbnailWidth,
      if (thumbnailHeight != null) 'thumbnailHeight': thumbnailHeight,
      if (byteLength != null) 'byteLength': byteLength,
      'originalAttachmentId': originalAttachmentId,
      'sourceUrl': sourceUrl,
      'tags': tags,
      'rotationQuarterTurns': rotationQuarterTurns,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'filter': filter.name,
      'annotations': annotations.map((item) => item.toMap()).toList(),
    });
  }

  List<String> validate({required String title}) {
    final serializedBytes = _serializedPayloadBytes(toData());
    final pointCount = annotations.fold<int>(
      0,
      (total, annotation) => total + annotation.points.length,
    );
    final textBytes = annotations.fold<int>(
      0,
      (total, annotation) => total + utf8.encode(annotation.text).length,
    );
    final errors = <String>[...NodeValidation.requiredTitle(title)];
    if (annotations.length > maxImageAnnotations) {
      errors.add('Image contains too many annotations.');
    }
    if (pointCount > maxDrawingPointsTotal) {
      errors.add('Image annotations contain too many points.');
    }
    if (textBytes > maxDrawingTextUtf8BytesTotal) {
      errors.add('Image annotation text exceeds size limit.');
    }
    if (serializedBytes > maxDrawingSerializedPayloadBytes) {
      errors.add('Image payload exceeds size limit.');
    }
    if (hasLocalAttachment == hasRemoteUrl) {
      errors.add('Choose one image attachment or URL.');
    }
    if (hasLocalAttachment &&
        (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(attachmentId) ||
            attachmentId.split('-').length != 5)) {
      errors.add('Attachment ID is invalid.');
    }
    if (hasRemoteUrl) {
      final uri = Uri.tryParse(url.trim());
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        errors.add('Image URL must use http or https.');
      }
    }
    if (mimeType.isNotEmpty &&
        (!supportedNodeAttachmentMimeTypes.contains(mimeType) ||
            !mimeType.startsWith('image/'))) {
      errors.add('Image MIME type is invalid.');
    }
    if (sourceUrl.isNotEmpty) {
      final uri = Uri.tryParse(sourceUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        errors.add('Image source URL must use https.');
      }
    }
    if (annotations.any((item) => item.id.trim().isEmpty)) {
      errors.add('Image annotation ID is required.');
    }
    for (final annotation in annotations) {
      if (annotation.points.length > maxDrawingPointsPerItem) {
        errors.add('Image annotation contains too many points.');
      }
      if (utf8.encode(annotation.text).length >
          maxDrawingTextUtf8BytesPerItem) {
        errors.add('Image annotation text exceeds item size limit.');
      }
      if (!annotation.strokeWidth.isFinite ||
          !annotation.positionX.isFinite ||
          !annotation.positionY.isFinite ||
          !annotation.width.isFinite ||
          !annotation.height.isFinite ||
          !annotation.rotationDegrees.isFinite ||
          annotation.points.any((point) => !_validCanvasPoint(point))) {
        errors.add('Image annotation geometry is invalid.');
      }
    }
    return errors;
  }
}

enum VideoFitMode { contain, cover, fill, fitWidth, fitHeight }

const Set<String> supportedVideoMimeTypes = {
  'video/mp4',
  'video/quicktime',
  'video/webm',
};

final class VideoPayload {
  const VideoPayload({
    this.attachmentId = '',
    this.url = '',
    this.mimeType = '',
    this.fileName = '',
    this.durationSeconds = 0,
    this.thumbnailAttachmentId = '',
    this.thumbnailUrl = '',
    this.playbackPositionSeconds = 0,
    this.muted = false,
    this.caption = '',
    this.altText = '',
    this.fitMode = VideoFitMode.contain,
  });

  factory VideoPayload.fromNode(MindmapNode node) {
    final section = _section(node.data, 'video');
    final duration = _number(section['durationSeconds']) ?? 0;
    final position = _number(section['playbackPositionSeconds']) ?? 0;
    return VideoPayload(
      attachmentId: _text(section['attachmentId']),
      url: _text(section['url']),
      mimeType: _text(section['mimeType']),
      fileName: _text(section['fileName']),
      durationSeconds: duration.isFinite && duration >= 0 ? duration : 0,
      thumbnailAttachmentId: _text(section['thumbnailAttachmentId']),
      thumbnailUrl: _text(section['thumbnailUrl']),
      playbackPositionSeconds: position.isFinite
          ? position.clamp(0, duration > 0 ? duration : double.infinity)
          : 0,
      muted: section['muted'] is bool ? section['muted'] as bool : false,
      caption: _text(section['caption']),
      altText: _text(section['altText']),
      fitMode:
          VideoFitMode.values
              .where((value) => value.name == _text(section['fitMode']))
              .firstOrNull ??
          VideoFitMode.contain,
    );
  }

  final String attachmentId;
  final String url;
  final String mimeType;
  final String fileName;
  final double durationSeconds;
  final String thumbnailAttachmentId;
  final String thumbnailUrl;
  final double playbackPositionSeconds;
  final bool muted;
  final String caption;
  final String altText;
  final VideoFitMode fitMode;

  bool get hasLocalAttachment => attachmentId.trim().isNotEmpty;
  bool get hasRemoteUrl => url.trim().isNotEmpty;

  VideoPayload copyWith({
    String? attachmentId,
    String? url,
    String? mimeType,
    String? fileName,
    double? durationSeconds,
    String? thumbnailAttachmentId,
    String? thumbnailUrl,
    double? playbackPositionSeconds,
    bool? muted,
    String? caption,
    String? altText,
    VideoFitMode? fitMode,
    bool clearAttachment = false,
    bool clearUrl = false,
  }) {
    final nextDuration = durationSeconds ?? this.durationSeconds;
    final nextPosition =
        playbackPositionSeconds ?? this.playbackPositionSeconds;
    return VideoPayload(
      attachmentId: clearAttachment ? '' : attachmentId ?? this.attachmentId,
      url: clearUrl ? '' : url ?? this.url,
      mimeType: mimeType ?? this.mimeType,
      fileName: fileName ?? this.fileName,
      durationSeconds: nextDuration,
      thumbnailAttachmentId:
          thumbnailAttachmentId ?? this.thumbnailAttachmentId,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      playbackPositionSeconds: nextPosition.clamp(
        0,
        nextDuration > 0 ? nextDuration : double.infinity,
      ),
      muted: muted ?? this.muted,
      caption: caption ?? this.caption,
      altText: altText ?? this.altText,
      fitMode: fitMode ?? this.fitMode,
    );
  }

  Map<String, Object?> toData([Map<String, Object?> existingData = const {}]) {
    final sanitized = Map<String, Object?>.of(existingData)
      ..remove('bytes')
      ..remove('base64')
      ..remove('videoBytes')
      ..remove('videoBase64');
    return _mergeSection(sanitized, 'video', {
      'attachmentId': attachmentId,
      'url': url,
      'mimeType': mimeType,
      'fileName': fileName,
      'durationSeconds': durationSeconds,
      'thumbnailAttachmentId': thumbnailAttachmentId,
      'thumbnailUrl': thumbnailUrl,
      'playbackPositionSeconds': playbackPositionSeconds.clamp(
        0,
        durationSeconds > 0 ? durationSeconds : double.infinity,
      ),
      'muted': muted,
      'caption': caption,
      'altText': altText,
      'fitMode': fitMode.name,
    });
  }

  List<String> validate({required String title}) {
    final errors = <String>[...NodeValidation.requiredTitle(title)];
    if (hasLocalAttachment == hasRemoteUrl) {
      errors.add('Choose one video attachment or URL.');
    }
    if (hasLocalAttachment &&
        (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(attachmentId) ||
            attachmentId.split('-').length != 5)) {
      errors.add('Attachment ID is invalid.');
    }
    if (hasRemoteUrl && !_isSafeVideoUrl(url)) {
      errors.add('Video URL must use HTTPS, or HTTP localhost.');
    }
    if (mimeType.isNotEmpty && !supportedVideoMimeTypes.contains(mimeType)) {
      errors.add('Video MIME type is invalid.');
    }
    if (hasLocalAttachment && !supportedVideoMimeTypes.contains(mimeType)) {
      errors.add('Local video MIME type is required.');
    }
    if (!durationSeconds.isFinite || durationSeconds < 0) {
      errors.add('Video duration is invalid.');
    }
    if (!playbackPositionSeconds.isFinite ||
        playbackPositionSeconds < 0 ||
        (durationSeconds > 0 && playbackPositionSeconds > durationSeconds)) {
      errors.add('Playback position is invalid.');
    }
    if (thumbnailUrl.isNotEmpty && !_isHttpUrl(thumbnailUrl)) {
      errors.add('Thumbnail URL must use http or https.');
    }
    return errors;
  }
}

bool _isSafeVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

final class ItineraryAgendaItem {
  const ItineraryAgendaItem({
    required this.id,
    required this.title,
    required this.startMinutes,
    required this.durationMinutes,
    this.dayOffset = 0,
    this.category = 'activity',
    this.location = '',
    this.notes = '',
    this.cost = 0,
    this.completed = false,
  });
  factory ItineraryAgendaItem.fromData(Map<String, Object?> data) =>
      ItineraryAgendaItem(
        id: _text(data['id']),
        title: _text(data['title']),
        startMinutes: _integer(data['startMinutes']) ?? -1,
        durationMinutes: _integer(data['durationMinutes']) ?? -1,
        dayOffset: _integer(data['dayOffset']) ?? 0,
        category: _text(data['category'], fallback: 'activity'),
        location: _text(data['location']),
        notes: _text(data['notes']),
        cost: _number(data['cost']) ?? double.nan,
        completed: data['completed'] is bool
            ? data['completed'] as bool
            : false,
      );
  final String id;
  final String title;
  final int startMinutes;
  final int durationMinutes;
  final int dayOffset;
  final String category;
  final String location;
  final String notes;
  final double cost;
  final bool completed;
  ItineraryAgendaItem copyWith({
    String? id,
    String? title,
    int? startMinutes,
    int? durationMinutes,
    int? dayOffset,
    String? category,
    String? location,
    String? notes,
    double? cost,
    bool? completed,
  }) => ItineraryAgendaItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startMinutes: startMinutes ?? this.startMinutes,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    dayOffset: dayOffset ?? this.dayOffset,
    category: category ?? this.category,
    location: location ?? this.location,
    notes: notes ?? this.notes,
    cost: cost ?? this.cost,
    completed: completed ?? this.completed,
  );
  Map<String, Object?> toData() => {
    'id': id,
    'title': title,
    'startMinutes': startMinutes,
    'durationMinutes': durationMinutes,
    'dayOffset': dayOffset,
    'category': category,
    'location': location,
    'notes': notes,
    'cost': cost,
    'completed': completed,
  };
}

final class ItineraryBooking {
  const ItineraryBooking({
    required this.id,
    required this.title,
    required this.type,
    required this.startAt,
    required this.endAt,
    this.provider = '',
    this.confirmationCode = '',
    this.location = '',
    this.cost = 0,
    this.status = 'planned',
    this.notes = '',
  });

  factory ItineraryBooking.fromData(Map<String, Object?> data) {
    final fallback = DateTime(1970);
    return ItineraryBooking(
      id: _text(data['id']),
      title: _text(data['title']),
      type: _text(data['type'], fallback: 'other'),
      startAt: DateTime.tryParse(_text(data['startAt'])) ?? fallback,
      endAt: DateTime.tryParse(_text(data['endAt'])) ?? fallback,
      provider: _text(data['provider']),
      confirmationCode: _text(data['confirmationCode']),
      location: _text(data['location']),
      cost: _number(data['cost']) ?? double.nan,
      status: _text(data['status'], fallback: 'planned'),
      notes: _text(data['notes']),
    );
  }

  final String id;
  final String title;
  final String type;
  final DateTime startAt;
  final DateTime endAt;
  final String provider;
  final String confirmationCode;
  final String location;
  final double cost;
  final String status;
  final String notes;

  ItineraryBooking copyWith({
    String? id,
    String? title,
    String? type,
    DateTime? startAt,
    DateTime? endAt,
    String? provider,
    String? confirmationCode,
    String? location,
    double? cost,
    String? status,
    String? notes,
  }) => ItineraryBooking(
    id: id ?? this.id,
    title: title ?? this.title,
    type: type ?? this.type,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    provider: provider ?? this.provider,
    confirmationCode: confirmationCode ?? this.confirmationCode,
    location: location ?? this.location,
    cost: cost ?? this.cost,
    status: status ?? this.status,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toData() => {
    'id': id,
    'title': title,
    'type': type,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'provider': provider,
    'confirmationCode': confirmationCode,
    'location': location,
    'cost': cost,
    'status': status,
    'notes': notes,
  };
}

final class ItineraryPackingItem {
  const ItineraryPackingItem({
    required this.id,
    required this.title,
    this.category = 'misc',
    this.quantity = 1,
    this.packed = false,
    this.essential = false,
  });

  factory ItineraryPackingItem.fromData(Map<String, Object?> data) =>
      ItineraryPackingItem(
        id: _text(data['id']),
        title: _text(data['title']),
        category: _text(data['category'], fallback: 'misc'),
        quantity: _integer(data['quantity']) ?? 1,
        packed: data['packed'] is bool ? data['packed'] as bool : false,
        essential: data['essential'] is bool
            ? data['essential'] as bool
            : false,
      );

  final String id;
  final String title;
  final String category;
  final int quantity;
  final bool packed;
  final bool essential;

  ItineraryPackingItem copyWith({
    String? id,
    String? title,
    String? category,
    int? quantity,
    bool? packed,
    bool? essential,
  }) => ItineraryPackingItem(
    id: id ?? this.id,
    title: title ?? this.title,
    category: category ?? this.category,
    quantity: quantity ?? this.quantity,
    packed: packed ?? this.packed,
    essential: essential ?? this.essential,
  );

  Map<String, Object?> toData() => {
    'id': id,
    'title': title,
    'category': category,
    'quantity': quantity,
    'packed': packed,
    'essential': essential,
  };
}

final class ItineraryAgendaConflict {
  const ItineraryAgendaConflict({
    required this.firstId,
    required this.secondId,
    required this.dayOffset,
  });

  final String firstId;
  final String secondId;
  final int dayOffset;
}

final class ItineraryInsights {
  const ItineraryInsights({
    required this.agendaConflicts,
    required this.agendaCost,
    required this.bookingCost,
    required this.totalPlannedCost,
    required this.completedAgenda,
    required this.confirmedBookings,
    required this.pendingBookings,
    required this.packedItems,
    required this.pendingEssentialItems,
    required this.bookingsOutsideTrip,
    required this.readinessScore,
    required this.overBudget,
    required this.warnings,
  });

  factory ItineraryInsights.fromPayload(ItineraryPayload payload) {
    final sortedAgenda = [...payload.agenda]
      ..sort((first, second) {
        final day = first.dayOffset.compareTo(second.dayOffset);
        return day == 0
            ? first.startMinutes.compareTo(second.startMinutes)
            : day;
      });
    final conflicts = <ItineraryAgendaConflict>[];
    for (var index = 0; index < sortedAgenda.length; index++) {
      final first = sortedAgenda[index];
      for (
        var comparedIndex = index + 1;
        comparedIndex < sortedAgenda.length;
        comparedIndex++
      ) {
        final second = sortedAgenda[comparedIndex];
        if (second.dayOffset != first.dayOffset) break;
        if (second.startMinutes >= first.startMinutes + first.durationMinutes) {
          break;
        }
        conflicts.add(
          ItineraryAgendaConflict(
            firstId: first.id,
            secondId: second.id,
            dayOffset: first.dayOffset,
          ),
        );
      }
    }

    final agendaCost = payload.agenda.fold<double>(
      0,
      (total, item) => total + (item.cost.isFinite ? item.cost : 0),
    );
    final activeBookings = payload.bookings
        .where((booking) => booking.status != 'cancelled')
        .toList();
    final confirmedBookings = activeBookings
        .where(
          (booking) =>
              const {'confirmed', 'completed'}.contains(booking.status),
        )
        .length;
    final bookingCost = activeBookings.fold<double>(
      0,
      (total, booking) => total + (booking.cost.isFinite ? booking.cost : 0),
    );
    final tripStart = DateTime(
      payload.startDate.year,
      payload.startDate.month,
      payload.startDate.day,
    );
    final tripEnd = DateTime(
      payload.endDate.year,
      payload.endDate.month,
      payload.endDate.day,
      23,
      59,
      59,
      999,
    );
    final bookingsOutsideTrip = activeBookings
        .where(
          (booking) =>
              booking.startAt.isBefore(tripStart) ||
              booking.endAt.isAfter(tripEnd),
        )
        .length;
    final packedItems = payload.packing.where((item) => item.packed).length;
    final pendingEssentialItems = payload.packing
        .where((item) => item.essential && !item.packed)
        .length;
    final totalPlannedCost = agendaCost + bookingCost;
    final effectiveCost = totalPlannedCost > payload.actualCost
        ? totalPlannedCost
        : payload.actualCost;
    final overBudget = payload.budget > 0 && effectiveCost > payload.budget;

    var readinessScore = 0;
    if (payload.destination.trim().isNotEmpty &&
        payload.timezone.trim().isNotEmpty &&
        !payload.endDate.isBefore(payload.startDate)) {
      readinessScore += 20;
    }
    if (payload.agenda.isNotEmpty) readinessScore += 10;
    if (payload.agenda.isNotEmpty && conflicts.isEmpty) readinessScore += 10;
    readinessScore += activeBookings.isEmpty
        ? 20
        : (confirmedBookings / activeBookings.length * 20).round();
    readinessScore += payload.packing.isEmpty
        ? 20
        : (packedItems / payload.packing.length * 20).round();
    if (!overBudget) readinessScore += 20;

    final warnings = <String>[
      if (payload.agenda.isEmpty) 'Add at least one agenda item.',
      if (conflicts.isNotEmpty)
        '${conflicts.length} agenda conflict${conflicts.length == 1 ? '' : 's'} detected.',
      if (activeBookings.length > confirmedBookings)
        '${activeBookings.length - confirmedBookings} booking${activeBookings.length - confirmedBookings == 1 ? '' : 's'} still pending.',
      if (bookingsOutsideTrip > 0)
        '$bookingsOutsideTrip booking${bookingsOutsideTrip == 1 ? '' : 's'} outside trip dates.',
      if (pendingEssentialItems > 0)
        '$pendingEssentialItems essential packing item${pendingEssentialItems == 1 ? '' : 's'} not packed.',
      if (overBudget) 'Planned or actual cost exceeds budget.',
    ];

    return ItineraryInsights(
      agendaConflicts: List.unmodifiable(conflicts),
      agendaCost: agendaCost,
      bookingCost: bookingCost,
      totalPlannedCost: totalPlannedCost,
      completedAgenda: payload.agenda.where((item) => item.completed).length,
      confirmedBookings: confirmedBookings,
      pendingBookings: activeBookings.length - confirmedBookings,
      packedItems: packedItems,
      pendingEssentialItems: pendingEssentialItems,
      bookingsOutsideTrip: bookingsOutsideTrip,
      readinessScore: readinessScore.clamp(0, 100).toInt(),
      overBudget: overBudget,
      warnings: List.unmodifiable(warnings),
    );
  }

  final List<ItineraryAgendaConflict> agendaConflicts;
  final double agendaCost;
  final double bookingCost;
  final double totalPlannedCost;
  final int completedAgenda;
  final int confirmedBookings;
  final int pendingBookings;
  final int packedItems;
  final int pendingEssentialItems;
  final int bookingsOutsideTrip;
  final int readinessScore;
  final bool overBudget;
  final List<String> warnings;
}

final class ItineraryPayload {
  ItineraryPayload({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.timezone,
    List<ItineraryAgendaItem> agenda = const [],
    List<ItineraryBooking> bookings = const [],
    List<ItineraryPackingItem> packing = const [],
    this.budget = 0,
    this.actualCost = 0,
    this.currency = 'USD',
    this.status = 'planned',
    this.travelers = 1,
    this.transport = '',
    this.accommodation = '',
    this.bookingReference = '',
  }) : agenda = List.unmodifiable(agenda),
       bookings = List.unmodifiable(bookings),
       packing = List.unmodifiable(packing);
  factory ItineraryPayload.fromNode(MindmapNode node) =>
      ItineraryPayload.fromData(node.data, fallbackDate: node.day);
  factory ItineraryPayload.fromData(
    Map<String, Object?> data, {
    DateTime? fallbackDate,
  }) {
    final section = _section(data, 'itinerary');
    final defaultDate = fallbackDate ?? DateTime(1970);
    return ItineraryPayload(
      destination: _text(section['destination']),
      startDate: DateTime.tryParse(_text(section['startDate'])) ?? defaultDate,
      endDate: DateTime.tryParse(_text(section['endDate'])) ?? defaultDate,
      timezone: _text(section['timezone'], fallback: 'Local time'),
      agenda: [
        for (final item in _maps(section['agenda']))
          ItineraryAgendaItem.fromData(item),
      ],
      bookings: [
        for (final item in _maps(section['bookings']))
          ItineraryBooking.fromData(item),
      ],
      packing: [
        for (final item in _maps(section['packing']))
          ItineraryPackingItem.fromData(item),
      ],
      budget: _number(section['budget']) ?? 0,
      actualCost: _number(section['actualCost']) ?? 0,
      currency: _text(section['currency'], fallback: 'USD'),
      status: _text(section['status'], fallback: 'planned'),
      travelers: _integer(section['travelers']) ?? 1,
      transport: _text(section['transport']),
      accommodation: _text(section['accommodation']),
      bookingReference: _text(section['bookingReference']),
    );
  }
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String timezone;
  final List<ItineraryAgendaItem> agenda;
  final List<ItineraryBooking> bookings;
  final List<ItineraryPackingItem> packing;
  final double budget;
  final double actualCost;
  final String currency;
  final String status;
  final int travelers;
  final String transport;
  final String accommodation;
  final String bookingReference;
  ItineraryPayload copyWith({
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    String? timezone,
    List<ItineraryAgendaItem>? agenda,
    List<ItineraryBooking>? bookings,
    List<ItineraryPackingItem>? packing,
    double? budget,
    double? actualCost,
    String? currency,
    String? status,
    int? travelers,
    String? transport,
    String? accommodation,
    String? bookingReference,
  }) => ItineraryPayload(
    destination: destination ?? this.destination,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    timezone: timezone ?? this.timezone,
    agenda: agenda ?? this.agenda,
    bookings: bookings ?? this.bookings,
    packing: packing ?? this.packing,
    budget: budget ?? this.budget,
    actualCost: actualCost ?? this.actualCost,
    currency: currency ?? this.currency,
    status: status ?? this.status,
    travelers: travelers ?? this.travelers,
    transport: transport ?? this.transport,
    accommodation: accommodation ?? this.accommodation,
    bookingReference: bookingReference ?? this.bookingReference,
  );
  Map<String, Object?> toData([Map<String, Object?> existingData = const {}]) =>
      _mergeSection(existingData, 'itinerary', {
        'destination': destination,
        'startDate': _dateKey(startDate),
        'endDate': _dateKey(endDate),
        'timezone': timezone,
        'agenda': [for (final item in agenda) item.toData()],
        'bookings': [for (final item in bookings) item.toData()],
        'packing': [for (final item in packing) item.toData()],
        'budget': budget,
        'actualCost': actualCost,
        'currency': currency,
        'status': status,
        'travelers': travelers,
        'transport': transport,
        'accommodation': accommodation,
        'bookingReference': bookingReference,
      });
  List<String> validate({required String title}) {
    final errors = <String>[
      ...NodeValidation.requiredTitle(title),
      if (timezone.trim().isEmpty) 'Timezone is required.',
      if (endDate.isBefore(startDate)) 'End date must not precede start date.',
      ...NodeValidation.number(budget, min: 0),
      ...NodeValidation.number(actualCost, min: 0),
      if (currency.trim().isEmpty) 'Currency is required.',
      if (travelers < 1 || travelers > 100)
        'Travelers must be between 1 and 100.',
      if (!const <String>{
        'planned',
        'booked',
        'in-progress',
        'completed',
        'cancelled',
      }.contains(status.trim().toLowerCase()))
        'Itinerary status is invalid.',
    ];
    final ids = <String>{};
    final tripDays = endDate.difference(startDate).inDays + 1;
    for (final item in agenda) {
      if (item.id.trim().isEmpty) errors.add('Agenda ID is required.');
      if (!ids.add(item.id)) errors.add('Agenda IDs must be unique.');
      if (item.title.trim().isEmpty) errors.add('Agenda title is required.');
      if (item.startMinutes < 0 || item.startMinutes >= 1440) {
        errors.add('Agenda start minute must be within the day.');
      }
      if (item.durationMinutes <= 0 ||
          item.startMinutes + item.durationMinutes > 1440) {
        errors.add('Agenda duration is invalid.');
      }
      if (item.dayOffset < 0 || item.dayOffset >= tripDays) {
        errors.add('Agenda day must be inside the trip date range.');
      }
      if (!const <String>{
        'activity',
        'transport',
        'food',
        'lodging',
        'reservation',
      }.contains(item.category.trim().toLowerCase())) {
        errors.add('Agenda category is invalid.');
      }
      errors.addAll(NodeValidation.number(item.cost, min: 0));
    }
    final bookingIds = <String>{};
    for (final booking in bookings) {
      if (booking.id.trim().isEmpty) errors.add('Booking ID is required.');
      if (!bookingIds.add(booking.id)) {
        errors.add('Booking IDs must be unique.');
      }
      if (booking.title.trim().isEmpty) {
        errors.add('Booking title is required.');
      }
      if (!const <String>{
        'flight',
        'hotel',
        'train',
        'activity',
        'car',
        'other',
      }.contains(booking.type.trim().toLowerCase())) {
        errors.add('Booking type is invalid.');
      }
      if (!const <String>{
        'planned',
        'reserved',
        'confirmed',
        'completed',
        'cancelled',
      }.contains(booking.status.trim().toLowerCase())) {
        errors.add('Booking status is invalid.');
      }
      if (booking.endAt.isBefore(booking.startAt)) {
        errors.add('Booking end must not precede start.');
      }
      errors.addAll(NodeValidation.number(booking.cost, min: 0));
    }
    final packingIds = <String>{};
    for (final item in packing) {
      if (item.id.trim().isEmpty) errors.add('Packing item ID is required.');
      if (!packingIds.add(item.id)) {
        errors.add('Packing item IDs must be unique.');
      }
      if (item.title.trim().isEmpty) {
        errors.add('Packing item title is required.');
      }
      if (item.quantity < 1 || item.quantity > 99) {
        errors.add('Packing quantity must be between 1 and 99.');
      }
      if (!const <String>{
        'documents',
        'clothing',
        'electronics',
        'toiletries',
        'health',
        'misc',
      }.contains(item.category.trim().toLowerCase())) {
        errors.add('Packing category is invalid.');
      }
    }
    return List.unmodifiable(errors);
  }
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, Object?> _section(Map<String, Object?> data, String key) {
  final raw = data[key];
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Map<String, Object?> _mergeSection(
  Map<String, Object?> data,
  String key,
  Map<String, Object?> values,
) => {
  ...data,
  key: {..._section(data, key), ...values},
};
void _removeSectionField(
  Map<String, Object?> data,
  String sectionKey,
  String fieldKey,
) {
  final section = Map<String, Object?>.from(_section(data, sectionKey))
    ..remove(fieldKey);
  if (section.isEmpty) {
    data.remove(sectionKey);
  } else {
    data[sectionKey] = section;
  }
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map)
        {
          for (final entry in item.entries)
            if (entry.key is String) entry.key as String: entry.value,
        },
  ];
}

List<String> _strings(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String) item,
      ]
    : value is String
    ? value
          .split(RegExp(r'[,\n]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
String _text(Object? value, {String fallback = ''}) =>
    value?.toString() ?? fallback;
double? _number(Object? value) => value is num && value.isFinite
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '');
int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

int? _positiveInteger(Object? value) {
  final parsed = _integer(value);
  return parsed != null && parsed > 0 ? parsed : null;
}
